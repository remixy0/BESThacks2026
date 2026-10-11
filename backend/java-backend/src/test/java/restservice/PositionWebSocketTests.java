package restservice;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.security.crypto.password.PasswordEncoder;
import restservice.position.PositionStore;
import restservice.user.AppUser;
import restservice.user.UserRepository;
import tools.jackson.databind.ObjectMapper;

import java.net.*;
import java.net.http.*;
import java.time.Duration;
import java.util.concurrent.*;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(classes = RestServiceApplication.class,
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = {
        "spring.datasource.url=jdbc:h2:mem:positions;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.sql.init.mode=never", "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.docker.compose.enabled=false"
})
class PositionWebSocketTests {
    @LocalServerPort int port;
    @Autowired UserRepository users;
    @Autowired PasswordEncoder encoder;
    @Autowired ObjectMapper json;
    @Autowired PositionStore positions;
    @Autowired restservice.navigation.NavigationService navigation;

    @BeforeEach
    void createUsers() {
        navigation.alarm(false);
        for (var zone : navigation.policy().zones()) navigation.removeZone(zone.id());
        users.deleteAll();
        String hash = encoder.encode("TestoweHaslo123!");
        users.saveAndFlush(new AppUser("first@example.com", hash));
        users.saveAndFlush(new AppUser("second@example.com", hash));
        var admin = new AppUser("admin@example.com", hash);
        admin.setRole(restservice.user.Role.ADMIN); users.saveAndFlush(admin);
    }

    @Test
    void acceptsUpdatesKeepsUsersSeparateAndRecoversFromInvalidMessages() throws Exception {
        try (var first = loggedInClient("first@example.com");
             var second = loggedInClient("second@example.com")) {
            var firstListener = new Messages();
            var secondListener = new Messages();
            var firstSocket = connect(first, firstListener);
            var secondSocket = connect(second, secondListener);
            try {
                send(firstSocket, "{\"x\":1.2,\"y\":3.4}");
                var accepted = json.readTree(firstListener.next());
                assertThat(accepted.get("type").asText()).isEqualTo("position");
                assertThat(accepted.get("x").doubleValue()).isEqualTo(1.2);
                assertThat(accepted.get("receivedAt").asText()).isNotBlank();
                send(secondSocket, "{\"x\":8,\"y\":9}");
                assertThat(json.readTree(secondListener.next()).get("type").asText()).isEqualTo("position");
                assertThat(latestPosition("first@example.com").orElseThrow().x()).isEqualTo(1.2);
                assertThat(latestPosition("second@example.com").orElseThrow().x()).isEqualTo(8);

                for (String invalid : new String[]{"not json", "{}", "{\"x\":1}",
                        "{\"x\":null,\"y\":2}", "{\"x\":\"1\",\"y\":2}",
                        "{\"x\":1e999,\"y\":2}", "{\"x\":1,\"y\":2,\"userId\":2}"}) {
                    send(firstSocket, invalid);
                    assertThat(json.readTree(firstListener.next()).get("code").asText())
                            .isEqualTo("INVALID_POSITION");
                    assertThat(latestPosition("first@example.com").orElseThrow().x()).isEqualTo(1.2);
                }
                send(firstSocket, "{\"x\":2.6,\"y\":4.8}");
                assertThat(json.readTree(firstListener.next()).get("x").doubleValue()).isEqualTo(2.6);
            } finally {
                firstSocket.sendClose(WebSocket.NORMAL_CLOSURE, "done").join();
                secondSocket.sendClose(WebSocket.NORMAL_CLOSURE, "done").join();
                firstListener.closed.get(5, TimeUnit.SECONDS);
                secondListener.closed.get(5, TimeUnit.SECONDS);
            }
            // The close callback on the server may run just after the client receives the close frame.
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5);
            while (latestPosition("first@example.com").isPresent() && System.nanoTime() < deadline) {
                Thread.sleep(10);
            }
            assertThat(latestPosition("first@example.com")).isEmpty();
        }
    }

    @Test
    void navigatesToTargetThroughActualWebSocketAndCancels() throws Exception {
        try (var client = loggedInClient("first@example.com")) {
            var listener = new Messages();
            var socket = connect(client, listener);
            try {
                send(socket, "{\"type\":\"destination\",\"x\":-0.5,\"y\":51.9}");
                assertThat(json.readTree(listener.next()).get("status").asText()).isEqualTo("awaiting_position");
                send(socket, "{\"type\":\"position\",\"x\":-0.5,\"y\":51.9}");
                assertThat(json.readTree(listener.next()).get("type").asText()).isEqualTo("position");
                assertThat(json.readTree(listener.next()).get("status").asText()).isEqualTo("arrived");

                // North entrance approach from the actual map, with several obstacles on the way.
                tools.jackson.databind.JsonNode data;
                try (var input = new org.springframework.core.io.ClassPathResource(
                        "maps/field-museum-main-level.grid.json").getInputStream()) {
                    data = json.readTree(input);
                }
                var approach = data.get("pointsOfInterest").get(1).get("approach");
                send(socket, "{\"type\":\"destination\",\"x\":" + approach.get("x") + ",\"y\":" + approach.get("y") + "}");
                var guidance = json.readTree(listener.next());
                assertThat(guidance.get("status").asText()).isEqualTo("navigating");
                assertThat(guidance.get("nextWaypoint").isObject()).isTrue();
                int updates = 0;
                while (!guidance.get("status").asText().equals("arrived") && updates++ < 30) {
                    var point = guidance.get("nextWaypoint");
                    send(socket, "{\"x\":" + point.get("x") + ",\"y\":" + point.get("y") + "}");
                    assertThat(json.readTree(listener.next()).get("type").asText()).isEqualTo("position");
                    guidance = json.readTree(listener.next());
                }
                assertThat(guidance.get("status").asText()).isEqualTo("arrived");
                send(socket, "{\"type\":\"destination\",\"x\":9999,\"y\":9999}");
                assertThat(json.readTree(listener.next()).get("code").asText()).isEqualTo("DESTINATION_OUTSIDE_MAP");
                send(socket, "{\"type\":\"cancel\"}");
                assertThat(json.readTree(listener.next()).get("status").asText()).isEqualTo("cancelled");
            } finally {
                socket.sendClose(WebSocket.NORMAL_CLOSURE, "done").join();
                listener.closed.get(5, TimeUnit.SECONDS);
            }
        }
    }

    @Test
    void rejectsUnauthenticatedHandshake() {
        try (var client = client()) {
            assertThatThrownBy(() -> connect(client, new Messages()))
                    .hasCauseInstanceOf(WebSocketHandshakeException.class)
                    .satisfies(exception -> assertThat(((WebSocketHandshakeException) exception.getCause())
                            .getResponse().statusCode()).isEqualTo(401));
        }
    }

    @Test
    void rejectsForeignBrowserOrigin() throws Exception {
        try (var client = loggedInClient("first@example.com")) {
            assertThatThrownBy(() -> client.newWebSocketBuilder()
                    .header("Origin", "https://untrusted.example")
                    .buildAsync(socketUri(), new Messages()).get(5, TimeUnit.SECONDS))
                    .hasCauseInstanceOf(WebSocketHandshakeException.class)
                    .satisfies(exception -> assertThat(((WebSocketHandshakeException) exception.getCause())
                            .getResponse().statusCode()).isEqualTo(403));
        }
    }

    @Test
    void stopsAcceptingPositionsAfterLogout() throws Exception {
        try (var client = loggedInClient("first@example.com")) {
            var listener = new Messages();
            var socket = connect(client, listener);
            try {
                send(socket, "{\"x\":1,\"y\":2}");
                listener.next();
                var logout = client.send(HttpRequest.newBuilder(httpUri("/api/auth/logout"))
                        .header("X-CSRF-TOKEN", csrf(client)).POST(HttpRequest.BodyPublishers.noBody()).build(),
                        HttpResponse.BodyHandlers.ofString());
                assertThat(logout.statusCode()).isEqualTo(204);
                try {
                    send(socket, "{\"x\":3,\"y\":4}");
                } catch (ExecutionException closedDuringLogout) {
                    // Tomcat may close the socket as soon as its HTTP session is invalidated.
                    assertThat(closedDuringLogout.getCause()).isInstanceOf(java.io.IOException.class);
                }
                assertThat(listener.closed.get(5, TimeUnit.SECONDS)).isEqualTo(1008);
                assertThat(latestPosition("first@example.com")).isEmpty();
            } finally {
                socket.abort();
            }
        }
    }

    @Test
    void userCannotAccessAdminSocketOrSendAdminCommands() throws Exception {
        try (var client = loggedInClient("first@example.com")) {
            assertThatThrownBy(() -> adminConnect(client,new Messages()))
                    .hasCauseInstanceOf(WebSocketHandshakeException.class)
                    .satisfies(e -> assertThat(((WebSocketHandshakeException)e.getCause()).getResponse().statusCode()).isEqualTo(403));
            var listener = new Messages(); var socket = connect(client,listener);
            try {
                send(socket,"{\"type\":\"alarm\",\"active\":true}");
                assertThat(json.readTree(listener.next()).get("code").asText()).isEqualTo("UNSUPPORTED_MESSAGE");
                assertThat(navigation.policy().alarmActive()).isFalse();
            } finally { socket.sendClose(1000,"done").join(); listener.closed.get(5,TimeUnit.SECONDS); }
        }
    }

    @Test
    void adminReceivesPositionsAndPushesAlarmAndZoneUpdatesImmediately() throws Exception {
        try (var admin = loggedInClient("admin@example.com"); var user = loggedInClient("first@example.com")) {
            var adminMessages = new Messages(); var userMessages = new Messages();
            var adminSocket = adminConnect(admin,adminMessages); var userSocket = connect(user,userMessages);
            try {
                assertThat(json.readTree(adminMessages.next()).get("type").asText()).isEqualTo("policy");
                assertThat(json.readTree(adminMessages.next()).get("users").size()).isZero();
                send(userSocket,"{\"x\":-0.5,\"y\":51.9}"); userMessages.next();
                var locations = json.readTree(adminMessages.next());
                assertThat(locations.get("users").get(0).get("username").asText()).isEqualTo("first@example.com");
                assertThat(locations.get("users").get(0).get("x").doubleValue()).isEqualTo(-.5);
                send(adminSocket,"{\"type\":\"alarm\",\"active\":true}");
                assertThat(json.readTree(adminMessages.next()).get("alarmActive").booleanValue()).isTrue();
                assertThat(json.readTree(userMessages.next()).get("type").asText()).isEqualTo("policy");
                assertThat(json.readTree(userMessages.next()).get("alarmActive").booleanValue()).isTrue();
                send(adminSocket,"{\"type\":\"zone.add\",\"minX\":10,\"minY\":10,\"maxX\":11,\"maxY\":11}");
                var policy = json.readTree(adminMessages.next());
                String id = policy.get("zones").get(0).get("id").asText();
                assertThat(json.readTree(userMessages.next()).get("zones").size()).isEqualTo(1);
                assertThat(json.readTree(userMessages.next()).get("type").asText()).isEqualTo("navigation");
                send(adminSocket,"{\"type\":\"zone.remove\",\"id\":\""+id+"\"}");
                assertThat(json.readTree(adminMessages.next()).get("zones").size()).isZero();
                userMessages.next(); userMessages.next();
                send(adminSocket,"{\"type\":\"alarm\",\"active\":false}");
                assertThat(json.readTree(adminMessages.next()).get("alarmActive").booleanValue()).isFalse();
                userMessages.next();
                assertThat(json.readTree(userMessages.next()).get("status").asText()).isEqualTo("idle");
                userSocket.sendClose(1000,"done").join(); userMessages.closed.get(5,TimeUnit.SECONDS);
                assertThat(json.readTree(adminMessages.next()).get("users").size()).isZero();
            } finally {
                userSocket.abort(); adminSocket.sendClose(1000,"done").join(); adminMessages.closed.get(5,TimeUnit.SECONDS);
            }
        }
    }

    @Test
    void validatesAdminCommandsAndRevokesSocketOnLogout() throws Exception {
        try (var admin = loggedInClient("admin@example.com")) {
            var listener = new Messages(); var socket = adminConnect(admin,listener);
            try {
                listener.next(); listener.next();
                for (String invalid : new String[]{"null","{}","{\"type\":\"alarm\",\"active\":\"true\"}",
                        "{\"type\":\"zone.add\",\"minX\":0,\"minY\":0,\"maxX\":-1,\"maxY\":1}"}) {
                    send(socket,invalid);
                    assertThat(json.readTree(listener.next()).get("type").asText()).isEqualTo("error");
                }
                var response = admin.send(HttpRequest.newBuilder(httpUri("/api/auth/logout"))
                        .header("X-CSRF-TOKEN",csrf(admin)).POST(HttpRequest.BodyPublishers.noBody()).build(),HttpResponse.BodyHandlers.ofString());
                assertThat(response.statusCode()).isEqualTo(204);
                assertThat(listener.closed.get(5,TimeUnit.SECONDS)).isEqualTo(1008);
                assertThat(navigation.policy().alarmActive()).isFalse();
            } finally { socket.abort(); }
        }
    }

    @Test
    void forwardsHelpToAllAdminsWithAuthenticatedIdentityAndAcknowledgesSender() throws Exception {
        try (var admin = loggedInClient("admin@example.com");
             var user = loggedInClient("first@example.com");
             var other = loggedInClient("second@example.com")) {
            var admins = new Messages(); var secondAdmin = new Messages();
            var sender = new Messages(); var observer = new Messages();
            var adminSocket = adminConnect(admin, admins);
            var secondAdminSocket = adminConnect(admin, secondAdmin);
            var userSocket = connect(user, sender); var otherSocket = connect(other, observer);
            try {
                // Connecting another admin also broadcasts the positions snapshot to existing admins.
                admins.next(); admins.next(); admins.next(); secondAdmin.next(); secondAdmin.next();
                send(userSocket, "{\"x\":-0.5,\"y\":51.9}");
                sender.next(); admins.next(); secondAdmin.next();
                send(userSocket, "{\"type\":\"help\"}");
                var event = json.readTree(admins.next());
                assertThat(event.get("type").asText()).isEqualTo("help.request");
                assertThat(event.get("username").asText()).isEqualTo("first@example.com");
                assertThat(event.get("position").get("x").doubleValue()).isEqualTo(-0.5);
                assertThat(event.get("position").get("y").doubleValue()).isEqualTo(51.9);
                assertThat(event.get("receivedAt").asText()).isNotBlank();
                assertThat(json.readTree(secondAdmin.next())).isEqualTo(event);
                var ack = json.readTree(sender.next());
                assertThat(ack.get("type").asText()).isEqualTo("help.accepted");
                assertThat(ack.get("id")).isEqualTo(event.get("id"));
                assertThat(ack.get("receivedAt")).isEqualTo(event.get("receivedAt"));
                assertThat(observer.messages.poll(200, TimeUnit.MILLISECONDS)).isNull();

                send(userSocket, "{\"type\":\"help\",\"x\":2.5,\"y\":3.5}");
                var explicit = json.readTree(admins.next()); secondAdmin.next(); sender.next();
                assertThat(explicit.get("position").get("x").doubleValue()).isEqualTo(2.5);
                assertThat(explicit.get("id")).isNotEqualTo(event.get("id"));
                // Help coordinates are a snapshot, not a position or navigation update.
                assertThat(latestPosition("first@example.com").orElseThrow().x()).isEqualTo(-0.5);
            } finally {
                userSocket.sendClose(1000, "done").join(); sender.closed.get(5, TimeUnit.SECONDS);
                otherSocket.sendClose(1000, "done").join(); observer.closed.get(5, TimeUnit.SECONDS);
                adminSocket.sendClose(1000, "done").join(); admins.closed.get(5, TimeUnit.SECONDS);
                secondAdminSocket.sendClose(1000, "done").join(); secondAdmin.closed.get(5, TimeUnit.SECONDS);
            }
        }
    }

    @Test
    void acceptsHelpWithoutLocationAndRejectsMalformedOrSpoofedHelp() throws Exception {
        try (var user = loggedInClient("first@example.com")) {
            var sender = new Messages(); var socket = connect(user, sender);
            try {
                for (String invalid : new String[]{"{\"type\":\"help\",\"x\":1}",
                        "{\"type\":\"help\",\"x\":null,\"y\":2}",
                        "{\"type\":\"help\",\"x\":\"1\",\"y\":2}",
                        "{\"type\":\"help\",\"x\":1e999,\"y\":2}",
                        "{\"type\":\"help\",\"username\":\"second@example.com\"}"}) {
                    send(socket, invalid);
                    assertThat(json.readTree(sender.next()).get("code").asText()).isEqualTo("INVALID_HELP");
                }
                // Acceptance does not depend on an admin being online or a known location.
                send(socket, "{\"type\":\"help\"}");
                assertThat(json.readTree(sender.next()).get("type").asText()).isEqualTo("help.accepted");
                try (var admin = loggedInClient("admin@example.com")) {
                    var receiver = new Messages(); var adminSocket = adminConnect(admin, receiver);
                    try {
                        receiver.next(); receiver.next();
                        send(socket, "{\"type\":\"help\"}");
                        var event = json.readTree(receiver.next()); sender.next();
                        assertThat(event.get("position").isNull()).isTrue();
                        assertThat(event.get("username").asText()).isEqualTo("first@example.com");
                    } finally {
                        adminSocket.sendClose(1000, "done").join(); receiver.closed.get(5, TimeUnit.SECONDS);
                    }
                }
            } finally {
                socket.sendClose(1000, "done").join(); sender.closed.get(5, TimeUnit.SECONDS);
            }
        }
    }

    private WebSocket adminConnect(HttpClient client, Messages listener) throws Exception {
        return client.newWebSocketBuilder().buildAsync(URI.create("ws://localhost:"+port+"/ws/admin"),listener).get(5,TimeUnit.SECONDS);
    }

    private java.util.Optional<PositionStore.Position> latestPosition(String username) {
        return positions.snapshot().stream().filter(position -> position.username().equals(username)).findFirst();
    }

    private HttpClient loggedInClient(String email) throws Exception {
        var client = client();
        var response = client.send(HttpRequest.newBuilder(httpUri("/api/auth/login"))
                        .header("X-CSRF-TOKEN", csrf(client)).header("Content-Type", "application/json")
                        .POST(HttpRequest.BodyPublishers.ofString("{\"email\":\"" + email
                                + "\",\"password\":\"TestoweHaslo123!\"}")).build(),
                HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(json.readTree(response.body()).get("role").asText())
                .isEqualTo(email.equals("admin@example.com") ? "ADMIN" : "USER");
        return client;
    }

    private String csrf(HttpClient client) throws Exception {
        var response = client.send(HttpRequest.newBuilder(httpUri("/api/auth/csrf")).GET().build(),
                HttpResponse.BodyHandlers.ofString());
        assertThat(response.statusCode()).isEqualTo(200);
        return json.readTree(response.body()).get("token").asText();
    }

    private HttpClient client() {
        return HttpClient.newBuilder().cookieHandler(new CookieManager(null, CookiePolicy.ACCEPT_ALL))
                .connectTimeout(Duration.ofSeconds(5)).build();
    }

    private URI httpUri(String path) { return URI.create("http://localhost:" + port + path); }
    private URI socketUri() { return URI.create("ws://localhost:" + port + "/ws/position"); }

    private WebSocket connect(HttpClient client, Messages listener) throws Exception {
        return client.newWebSocketBuilder().buildAsync(socketUri(), listener).get(5, TimeUnit.SECONDS);
    }

    private void send(WebSocket socket, String body) throws Exception {
        socket.sendText(body, true).get(5, TimeUnit.SECONDS);
    }

    private static class Messages implements WebSocket.Listener {
        private final BlockingQueue<String> messages = new LinkedBlockingQueue<>();
        private final StringBuilder buffer = new StringBuilder();
        private final CompletableFuture<Integer> closed = new CompletableFuture<>();

        @Override
        public void onOpen(WebSocket socket) { socket.request(1); }

        @Override
        public CompletionStage<?> onText(WebSocket socket, CharSequence data, boolean last) {
            buffer.append(data);
            if (last) {
                messages.add(buffer.toString());
                buffer.setLength(0);
            }
            socket.request(1);
            return null;
        }

        @Override
        public CompletionStage<?> onClose(WebSocket socket, int status, String reason) {
            closed.complete(status);
            return null;
        }

        @Override
        public void onError(WebSocket socket, Throwable error) { closed.completeExceptionally(error); }

        String next() throws Exception {
            String message = messages.poll(5, TimeUnit.SECONDS);
            assertThat(message).as("WebSocket response").isNotNull();
            return message;
        }
    }
}

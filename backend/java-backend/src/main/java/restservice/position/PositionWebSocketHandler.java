package restservice.position;

import org.springframework.stereotype.Component;
import org.springframework.web.socket.*;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;
import java.io.IOException;
import restservice.navigation.MapPoint;
import restservice.navigation.NavigationException;
import restservice.navigation.NavigationService;

@Component
public class PositionWebSocketHandler extends TextWebSocketHandler {
    private final SocketHub hub;
    private final ObjectMapper json;
    private final PositionStore positions;
    private final NavigationService navigation;

    public PositionWebSocketHandler(ObjectMapper json, PositionStore positions, NavigationService navigation, SocketHub hub) {
        this.hub = hub;
        this.json = json;
        this.positions = positions;
        this.navigation = navigation;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        session.setTextMessageSizeLimit(1024);
        if (!SocketAuthentication.isAuthenticated(session)) {
            session.close(CloseStatus.POLICY_VIOLATION);
        } else { hub.addUser(session); }
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        synchronized (navigation) {
            process(session, message);
        }
    }

    private void process(WebSocketSession session, TextMessage message) throws Exception {
        // A WebSocket can outlive its HTTP session: re-check before each update.
        if (!SocketAuthentication.isAuthenticated(session)) {
            positions.remove(session.getId());
            navigation.remove(session.getId());
            session.close(new CloseStatus(1008, "Session expired; log in again"));
            return;
        }
        double x;
        double y;
        String type;
        try {
            var data = json.readTree(message.getPayload());
            if (data == null || !data.isObject()) {
                invalidPosition(session);
                return;
            }
            type = data.has("type") && data.get("type").isString() ? data.get("type").asText() : "position";
            if (type.equals("cancel") && data.size() == 1) {
                send(session, navigation.cancel(session.getId()));
                return;
            }
            if (!type.equals("position") && !type.equals("destination")) {
                send(session, new PositionError("error", "UNSUPPORTED_MESSAGE", "Dozwolone typy: position, destination, cancel."));
                return;
            }
            if ((data.has("type") && (!data.get("type").isString() || data.size() != 3))
                    || (!data.has("type") && data.size() != 2)
                    || !data.has("x") || !data.has("y")
                    || !data.get("x").isNumber() || !data.get("y").isNumber()) {
                invalidPosition(session);
                return;
            }
            x = data.get("x").doubleValue();
            y = data.get("y").doubleValue();
            if (!Double.isFinite(x) || !Double.isFinite(y)) {
                invalidPosition(session);
                return;
            }
        } catch (JacksonException exception) {
            invalidPosition(session);
            return;
        }
        if (type.equals("destination")) {
            try {
                send(session, navigation.destination(session.getId(), new MapPoint(x, y)));
            } catch (NavigationException exception) {
                send(session, new PositionError("error", exception.code(), exception.getMessage()));
            }
            return;
        }
        var position = positions.update(session.getId(), session.getPrincipal().getName(), x, y);
        send(session, new PositionAccepted("position", x, y, position.receivedAt().toString()));
        var guidance = navigation.position(session.getId(), new MapPoint(x, y));
        if (guidance != null) send(session, guidance);
        hub.positionsChanged();
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        hub.removeUser(session.getId());
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) throws Exception {
        hub.removeUser(session.getId());
        if (session.isOpen()) {
            session.close(CloseStatus.SERVER_ERROR);
        }
    }

    private void invalidPosition(WebSocketSession session) throws IOException {
        send(session, new PositionError("error", "INVALID_POSITION", "Wyślij skończone współrzędne x i y w metrach."));
    }

    private void send(WebSocketSession session, Object message) throws IOException {
        hub.sendUser(session.getId(), message);
    }

    private record PositionAccepted(String type, double x, double y, String receivedAt) {}
    private record PositionError(String type, String code, String message) {}
}

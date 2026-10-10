package restservice.position;

import org.springframework.stereotype.Component;
import org.springframework.web.socket.*;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import restservice.navigation.NavigationException;
import restservice.navigation.NavigationService;
import tools.jackson.databind.ObjectMapper;
import tools.jackson.databind.JsonNode;
import tools.jackson.core.JacksonException;

@Component
public class AdminWebSocketHandler extends TextWebSocketHandler {
    private final SocketHub hub;
    private final NavigationService navigation;
    private final ObjectMapper json;
    public AdminWebSocketHandler(SocketHub hub, NavigationService navigation, ObjectMapper json) {
        this.hub = hub; this.navigation = navigation; this.json = json;
    }

    @Override public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        session.setTextMessageSizeLimit(2048);
        if (!SocketAuthentication.isAdmin(session)) session.close(CloseStatus.POLICY_VIOLATION);
        else hub.addAdmin(session);
    }

    @Override protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        synchronized (navigation) {
            if (!SocketAuthentication.isAdmin(session)) {
                hub.removeAdmin(session.getId()); session.close(CloseStatus.POLICY_VIOLATION); return;
            }
            try {
                JsonNode data = json.readTree(message.getPayload());
                if (data == null || !data.isObject() || !data.has("type") || !data.get("type").isString()) invalid();
                switch (data.get("type").asText()) {
                    case "alarm" -> {
                        if (data.size()!=2 || !data.has("active") || !data.get("active").isBoolean()) invalid();
                        navigation.alarm(data.get("active").booleanValue());
                    }
                    case "zone.add" -> {
                        if (data.size()!=5) invalid();
                        navigation.addZone(number(data,"minX"),number(data,"minY"),number(data,"maxX"),number(data,"maxY"));
                    }
                    case "zone.remove" -> {
                        if (data.size()!=2 || !data.has("id") || !data.get("id").isString()) invalid();
                        navigation.removeZone(data.get("id").asText());
                    }
                    case "snapshot" -> {
                        if (data.size()!=1) invalid();
                        hub.sendAdmin(session.getId(), navigation.policy()); hub.positionsChanged(); return;
                    }
                    default -> invalid();
                }
                hub.policyChanged();
            } catch (NavigationException invalid) {
                hub.sendAdmin(session.getId(), new Error("error", invalid.code(), invalid.getMessage()));
            } catch (JacksonException malformed) {
                hub.sendAdmin(session.getId(), new Error("error", "INVALID_COMMAND", "Niepoprawny JSON."));
            }
        }
    }

    private static double number(JsonNode data, String field) {
        if (!data.has(field) || !data.get(field).isNumber() || !Double.isFinite(data.get(field).doubleValue())) invalid();
        return data.get(field).doubleValue();
    }
    private static void invalid() { throw new NavigationException("INVALID_COMMAND", "Niepoprawna komenda administratora."); }
    @Override public void afterConnectionClosed(WebSocketSession session, CloseStatus status) { hub.removeAdmin(session.getId()); }
    @Override public void handleTransportError(WebSocketSession session, Throwable error) throws Exception {
        hub.removeAdmin(session.getId()); if (session.isOpen()) session.close(CloseStatus.SERVER_ERROR);
    }
    private record Error(String type, String code, String message) {}
}

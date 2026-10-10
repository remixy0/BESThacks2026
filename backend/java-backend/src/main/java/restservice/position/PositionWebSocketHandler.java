package restservice.position;

import jakarta.servlet.http.HttpSession;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.web.context.HttpSessionSecurityContextRepository;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.*;
import org.springframework.web.socket.handler.TextWebSocketHandler;
import tools.jackson.core.JacksonException;
import tools.jackson.databind.ObjectMapper;
import java.io.IOException;

@Component
public class PositionWebSocketHandler extends TextWebSocketHandler {
    private final ObjectMapper json;
    private final PositionStore positions;

    public PositionWebSocketHandler(ObjectMapper json, PositionStore positions) {
        this.json = json;
        this.positions = positions;
    }

    @Override
    public void afterConnectionEstablished(WebSocketSession session) throws Exception {
        session.setTextMessageSizeLimit(1024);
        if (!isAuthenticated(session)) {
            session.close(CloseStatus.POLICY_VIOLATION);
        }
    }

    @Override
    protected void handleTextMessage(WebSocketSession session, TextMessage message) throws Exception {
        // A WebSocket can outlive its HTTP session: re-check before each update.
        if (!isAuthenticated(session)) {
            positions.remove(session.getId());
            session.close(new CloseStatus(1008, "Session expired; log in again"));
            return;
        }
        double x;
        double y;
        try {
            var data = json.readTree(message.getPayload());
            if (data == null || !data.isObject() || data.size() != 2
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
        var position = positions.update(session.getId(), session.getPrincipal().getName(), x, y);
        session.sendMessage(new TextMessage(json.writeValueAsString(
                new PositionAccepted("position", x, y, position.receivedAt().toString()))));
    }

    @Override
    public void afterConnectionClosed(WebSocketSession session, CloseStatus status) {
        positions.remove(session.getId());
    }

    @Override
    public void handleTransportError(WebSocketSession session, Throwable exception) throws Exception {
        positions.remove(session.getId());
        if (session.isOpen()) {
            session.close(CloseStatus.SERVER_ERROR);
        }
    }

    private boolean isAuthenticated(WebSocketSession session) {
        if (session.getPrincipal() == null) return false;
        var httpSession = (HttpSession) session.getAttributes().get(PositionHandshakeInterceptor.HTTP_SESSION);
        if (httpSession == null) return false;
        try {
            var stored = httpSession.getAttribute(HttpSessionSecurityContextRepository.SPRING_SECURITY_CONTEXT_KEY);
            if (!(stored instanceof SecurityContext context)) return false;
            var authentication = context.getAuthentication();
            return authentication != null && authentication.isAuthenticated()
                    && authentication.getName().equals(session.getPrincipal().getName());
        } catch (IllegalStateException expiredSession) {
            return false;
        }
    }

    private void invalidPosition(WebSocketSession session) throws IOException {
        session.sendMessage(new TextMessage(json.writeValueAsString(
                new PositionError("error", "INVALID_POSITION", "Wyślij obiekt JSON z dwiema skończonymi liczbami x i y w metrach."))));
    }

    private record PositionAccepted(String type, double x, double y, String receivedAt) {}
    private record PositionError(String type, String code, String message) {}
}

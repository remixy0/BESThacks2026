package restservice.position;

import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.web.socket.*;
import org.springframework.web.socket.handler.ConcurrentWebSocketSessionDecorator;
import restservice.navigation.NavigationService;
import tools.jackson.databind.ObjectMapper;
import java.util.*;

/** Serializes policy changes with position updates; never broadcasts to expired sessions. */
@Component
public class SocketHub {
    private final Map<String, WebSocketSession> users = new HashMap<>(), admins = new HashMap<>();
    private final NavigationService navigation;
    private final PositionStore positions;
    private final ObjectMapper json;

    public SocketHub(NavigationService navigation, PositionStore positions, ObjectMapper json) {
        this.navigation = navigation; this.positions = positions; this.json = json;
    }

    public void addUser(WebSocketSession session) {
        synchronized (navigation) {
            users.put(session.getId(), wrap(session));
            if (navigation.policy().alarmActive() || !navigation.policy().zones().isEmpty()) sendUser(session.getId(), navigation.policy());
        }
    }

    public void addAdmin(WebSocketSession session) {
        synchronized (navigation) {
            admins.put(session.getId(), wrap(session));
            sendAdmin(session.getId(), navigation.policy());
            positionsChanged();
        }
    }

    private WebSocketSession wrap(WebSocketSession session) {
        return new ConcurrentWebSocketSessionDecorator(session, 5000, 256*1024);
    }

    public void removeUser(String id) {
        synchronized (navigation) {
            users.remove(id); positions.remove(id); navigation.remove(id); positionsChanged();
        }
    }

    public void removeAdmin(String id) { synchronized (navigation) { admins.remove(id); } }

    public void sendUser(String id, Object message) {
        synchronized (navigation) { deliver(users.get(id), message, false); }
    }
    public void sendAdmin(String id, Object message) {
        synchronized (navigation) { deliver(admins.get(id), message, true); }
    }

    private void deliver(WebSocketSession session, Object message, boolean admin) {
        if (session == null) return;
        try {
            if (!session.isOpen() || !(admin ? SocketAuthentication.isAdmin(session) : SocketAuthentication.isAuthenticated(session))) {
                discard(session, admin);
                if (!admin) positionsChanged();
                return;
            }
            session.sendMessage(new TextMessage(json.writeValueAsString(message)));
        } catch (Exception failed) {
            discard(session, admin);
            if (!admin) positionsChanged();
        }
    }

    private void discard(WebSocketSession session, boolean admin) {
        if (admin) admins.remove(session.getId());
        else { users.remove(session.getId()); positions.remove(session.getId()); navigation.remove(session.getId()); }
        try { if (session.isOpen()) session.close(CloseStatus.POLICY_VIOLATION); } catch (Exception ignored) {}
    }

    @Scheduled(fixedDelay = 1000)
    public void pruneExpiredSessions() {
        synchronized (navigation) {
            boolean changed = false;
            for (var session : List.copyOf(users.values())) {
                if (!session.isOpen() || !SocketAuthentication.isAuthenticated(session)) { discard(session,false); changed = true; }
            }
            for (var session : List.copyOf(admins.values())) {
                if (!session.isOpen() || !SocketAuthentication.isAdmin(session)) discard(session,true);
            }
            if (changed) positionsChanged();
        }
    }

    public void positionsChanged() {
        synchronized (navigation) {
            // Filtering also happens on broadcasts, not only during the periodic cleanup.
            for (var session : List.copyOf(users.values()))
                if (!SocketAuthentication.isAuthenticated(session)) discard(session,false);
            var snapshot = new Positions("positions", positions.snapshot());
            for (String id : List.copyOf(admins.keySet())) sendAdmin(id, snapshot);
        }
    }

    public void policyChanged() {
        synchronized (navigation) {
            var policy = navigation.policy();
            for (String id : List.copyOf(admins.keySet())) sendAdmin(id, policy);
            for (String id : List.copyOf(users.keySet())) {
                sendUser(id, policy);
                var guidance = navigation.refresh(id);
                if (guidance != null) sendUser(id, guidance);
            }
        }
    }

    private record Positions(String type, List<PositionStore.Position> users) {}
}

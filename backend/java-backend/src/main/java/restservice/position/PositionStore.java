package restservice.position;

import org.springframework.stereotype.Service;
import java.time.Instant;
import java.util.List;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;

/** Latest position per active connection; no location history is retained. */
@Service
public class PositionStore {
    private final ConcurrentHashMap<String, Position> positions = new ConcurrentHashMap<>();

    public Position update(String connectionId, String username, double x, double y) {
        var position = new Position(username, x, y, Instant.now());
        positions.put(connectionId, position);
        return position;
    }

    public List<Position> snapshot() {
        var latest = new TreeMap<String, Position>();
        positions.values().forEach(p -> latest.merge(p.username(), p,
                (a,b) -> a.receivedAt().isAfter(b.receivedAt()) ? a : b));
        return List.copyOf(latest.values());
    }

    public void remove(String connectionId) {
        positions.remove(connectionId);
    }

    public Position forConnection(String connectionId) {
        return positions.get(connectionId);
    }

    public record Position(String username, double x, double y, Instant receivedAt) {}
}

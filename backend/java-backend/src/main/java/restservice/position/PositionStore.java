package restservice.position;

import org.springframework.stereotype.Service;
import java.time.Instant;
import java.util.Comparator;
import java.util.Optional;
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

    public Optional<Position> latestForUser(String username) {
        return positions.values().stream().filter(position -> position.username().equals(username))
                .max(Comparator.comparing(Position::receivedAt));
    }

    public java.util.List<Position> snapshot() {
        var latest = new java.util.TreeMap<String, Position>();
        positions.values().forEach(p -> latest.merge(p.username(), p,
                (a,b) -> a.receivedAt().isAfter(b.receivedAt()) ? a : b));
        return java.util.List.copyOf(latest.values());
    }

    public void remove(String connectionId) {
        positions.remove(connectionId);
    }

    public record Position(String username, double x, double y, Instant receivedAt) {}
}

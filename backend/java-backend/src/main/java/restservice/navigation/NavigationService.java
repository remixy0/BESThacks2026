package restservice.navigation;

import org.springframework.stereotype.Service;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class NavigationService {
    public static final double WAYPOINT_TOLERANCE_M = 0.4;
    public static final double ARRIVAL_TOLERANCE_M = 0.3;
    public static final double OFF_ROUTE_TOLERANCE_M = 0.75;
    private final NavigationMap map;
    private final Pathfinder pathfinder;
    private final ConcurrentHashMap<String, State> states = new ConcurrentHashMap<>();

    public NavigationService(NavigationMap map, Pathfinder pathfinder) {
        this.map = map;
        this.pathfinder = pathfinder;
    }

    public Guidance destination(String connection, MapPoint destination) {
        map.requireWalkable(destination, "DESTINATION");
        State state = states.computeIfAbsent(connection, ignored -> new State());
        synchronized (state) {
            state.destination = destination;
            state.turns = List.of();
            state.index = 0;
            state.arrived = false;
            state.routeId = null;
            return update(state);
        }
    }

    /** Null means the client has not selected a destination. */
    public Guidance position(String connection, MapPoint position) {
        State state = states.computeIfAbsent(connection, ignored -> new State());
        synchronized (state) {
            state.position = position;
            return state.destination == null ? null : update(state);
        }
    }

    public Guidance cancel(String connection) {
        State state = states.computeIfAbsent(connection, ignored -> new State());
        synchronized (state) {
            state.destination = null;
            state.turns = List.of();
            state.routeId = null;
            state.index = 0;
            state.arrived = false;
            return response(state, "cancelled", null, false, null);
        }
    }

    public void remove(String connection) { states.remove(connection); }

    private Guidance update(State state) {
        if (state.position == null) return response(state, "awaiting_position", null, false, null);
        if (state.arrived) return response(state, "arrived", null, false, null);
        boolean recalculated = false;
        try {
            map.requireWalkable(state.position, "POSITION");
            if (state.position.distanceTo(state.destination) <= ARRIVAL_TOLERANCE_M
                    && map.lineOfSight(state.position, state.destination)) {
                state.arrived = true;
                return response(state, "arrived", null, false, null);
            }
            if (!state.turns.isEmpty()) {
                while (state.index < state.turns.size() - 1) {
                    MapPoint corner = state.turns.get(state.index), following = state.turns.get(state.index + 1);
                    boolean reached = state.position.distanceTo(corner) <= WAYPOINT_TOLERANCE_M
                            || segmentDistance(state.position, corner, following) <= WAYPOINT_TOLERANCE_M;
                    if (!reached || !map.lineOfSight(state.position, following)) break;
                    state.segmentStart = corner;
                    state.index++;
                }
            }
            if (state.turns.isEmpty() || !map.lineOfSight(state.position, state.turns.get(state.index))
                    || segmentDistance(state.position, state.segmentStart, state.turns.get(state.index)) > OFF_ROUTE_TOLERANCE_M) {
                state.turns = pathfinder.find(state.position, state.destination);
                state.index = 0;
                state.segmentStart = state.position;
                state.routeId = UUID.randomUUID().toString();
                recalculated = true;
            }
            return response(state, "navigating", state.turns.get(state.index), recalculated, null);
        } catch (NavigationException exception) {
            state.turns = List.of();
            state.index = 0;
            state.routeId = null;
            return response(state, "blocked", null, false, exception.code());
        }
    }

    private Guidance response(State state, String status, MapPoint next, boolean recalculated, String reason) {
        Double distance = next == null ? null : state.position.distanceTo(next);
        Double remaining = distance;
        if (remaining != null) {
            for (int i = state.index; i < state.turns.size() - 1; i++) remaining += state.turns.get(i).distanceTo(state.turns.get(i + 1));
        } else if (status.equals("arrived")) {
            remaining = 0.0;
        }
        return new Guidance("navigation", status, map.id(), state.routeId, state.destination, next,
                next == null ? null : state.index, state.turns.size(), distance, remaining,
                recalculated, reason, WAYPOINT_TOLERANCE_M, ARRIVAL_TOLERANCE_M);
    }

    static double segmentDistance(MapPoint point, MapPoint a, MapPoint b) {
        double dx = b.x() - a.x(), dy = b.y() - a.y(), lengthSquared = dx * dx + dy * dy;
        if (lengthSquared == 0) return point.distanceTo(a);
        double projection = Math.clamp(((point.x() - a.x()) * dx + (point.y() - a.y()) * dy) / lengthSquared, 0.0, 1.0);
        return point.distanceTo(new MapPoint(a.x() + projection * dx, a.y() + projection * dy));
    }

    private static class State {
        MapPoint position, destination, segmentStart;
        List<MapPoint> turns = List.of();
        int index;
        String routeId;
        boolean arrived;
    }

    public record Guidance(String type, String status, String mapId, String routeId, MapPoint destination,
                           MapPoint nextWaypoint, Integer waypointIndex, int waypointCount,
                           Double distanceToWaypointM, Double remainingDistanceM, boolean recalculated,
                           String reason, double waypointToleranceM, double arrivalToleranceM) {}
}

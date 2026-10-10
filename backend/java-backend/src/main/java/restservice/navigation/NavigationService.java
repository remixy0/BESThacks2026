package restservice.navigation;

import org.springframework.stereotype.Service;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class NavigationService {
    public static final double WAYPOINT_TOLERANCE_M = 0.4;
    public static final double ARRIVAL_TOLERANCE_M = 0.3;
    public static final double OFF_ROUTE_TOLERANCE_M = 0.75;
    private final NavigationMap map;
    private final Pathfinder pathfinder;
    private final LinkedHashMap<String, ExclusionZone> zones = new LinkedHashMap<>();
    private boolean alarmActive;
    private long revision;

    public synchronized Policy policy() {
        return new Policy("policy", revision, alarmActive, List.copyOf(zones.values()), map.exits());
    }

    public synchronized Policy alarm(boolean active) {
        if (alarmActive != active) { alarmActive = active; revision++; }
        return policy();
    }

    public synchronized Policy addZone(double minX, double minY, double maxX, double maxY) {
        MapPoint low = map.center(0,0), high = map.center(map.width()-1,map.height()-1);
        if (!Double.isFinite(minX) || !Double.isFinite(minY) || !Double.isFinite(maxX) || !Double.isFinite(maxY)
                || minX >= maxX || minY >= maxY || minX < low.x()-map.cellSize()/2
                || minY < low.y()-map.cellSize()/2 || maxX > high.x()+map.cellSize()/2
                || maxY > high.y()+map.cellSize()/2)
            throw new NavigationException("INVALID_ZONE", "Prostokąt musi mieścić się na mapie i mieć dodatnią szerokość oraz wysokość.");
        if (zones.size() >= 100) throw new NavigationException("ZONE_LIMIT", "Maksymalnie 100 aktywnych stref.");
        String id = UUID.randomUUID().toString();
        zones.put(id, new ExclusionZone(id,minX,minY,maxX,maxY)); revision++;
        return policy();
    }

    public synchronized Policy removeZone(String id) {
        if (zones.remove(id) == null) throw new NavigationException("ZONE_NOT_FOUND", "Nie znaleziono strefy.");
        revision++; return policy();
    }

    public synchronized Guidance refresh(String connection) {
        State state = states.get(connection);
        return state == null ? null : update(state);
    }

    public record Policy(String type, long revision, boolean alarmActive, List<ExclusionZone> zones, List<MapPoint> exits) {}

    private final ConcurrentHashMap<String, State> states = new ConcurrentHashMap<>();

    public NavigationService(NavigationMap map, Pathfinder pathfinder) {
        this.map = map;
        this.pathfinder = pathfinder;
    }

    public synchronized Guidance destination(String connection, MapPoint destination) {
        map.requireWalkable(destination, "DESTINATION");
        State state = states.computeIfAbsent(connection, ignored -> new State());
        synchronized (state) {
            state.requestedDestination = destination;
            state.destination = destination;
            state.turns = List.of();
            state.index = 0;
            state.arrived = false;
            state.routeId = null;
            return update(state);
        }
    }

    /** Null means the client has not selected a destination. */
    public synchronized Guidance position(String connection, MapPoint position) {
        State state = states.computeIfAbsent(connection, ignored -> new State());
        synchronized (state) {
            state.position = position;
            return state.requestedDestination == null && !alarmActive && zones.isEmpty() ? null : update(state);
        }
    }

    public synchronized Guidance cancel(String connection) {
        State state = states.computeIfAbsent(connection, ignored -> new State());
        synchronized (state) {
            state.requestedDestination = null;
            if (alarmActive) return update(state);
            state.destination = null;
            state.turns = List.of();
            state.routeId = null;
            state.index = 0;
            state.arrived = false;
            if (state.position != null && new RestrictedMap(map,List.copyOf(zones.values()),state.position).excluded(state.position))
                return update(state);
            return response(state, "cancelled", null, false, null);
        }
    }

    public synchronized void remove(String connection) { states.remove(connection); }

    private Guidance update(State state) {
        if (state.revision != revision) {
            state.turns = List.of(); state.index = 0; state.arrived = false; state.routeId = null;
            state.revision = revision;
        }
        if (state.escapeRoute) { state.turns = List.of(); state.index = 0; state.escapeRoute = false; }
        if (!alarmActive) state.destination = state.requestedDestination;
        if (state.position == null) {
            if (alarmActive) state.destination = null;
            return response(state, "awaiting_position", null, false, null);
        }

        boolean recalculated = false;
        try {
            map.requireWalkable(state.position, "POSITION");
            RestrictedMap view = new RestrictedMap(map, List.copyOf(zones.values()), state.position);
            NavigationMap map = view;
            if (alarmActive && (state.turns.isEmpty() || state.destination == null)) {
                List<MapPoint> best = null; MapPoint exit = null; double bestLength = Double.POSITIVE_INFINITY;
                for (MapPoint candidate : this.map.exits()) {
                    try {
                        var route = pathfinder.find(state.position, candidate, view);
                        double length = length(state.position, route);
                        if (length < bestLength) { best = route; bestLength = length; exit = candidate; }
                    } catch (NavigationException unavailable) { /* Try every exit. */ }
                }
                if (best == null) {
                    state.destination = null;
                    if (view.excluded(state.position)) return escape(state, view, "NO_REACHABLE_EXIT");
                    throw new NavigationException("NO_REACHABLE_EXIT", "Brak dostępnej trasy do wyjścia.");
                }
                state.destination = exit; state.turns = best; state.index = 0;
                state.segmentStart = state.position; state.routeId = UUID.randomUUID().toString(); recalculated = true;
            }
            if (state.destination == null) {
                if (view.excluded(state.position)) return escape(state, view, null);
                state.turns = List.of(); state.routeId = null;
                return response(state, "idle", null, false, null);
            }
            try { view.requireWalkable(state.destination, "DESTINATION"); }
            catch (NavigationException blocked) {
                if (view.excluded(state.position)) return escape(state, view, blocked.code());
                throw blocked;
            }
            if (state.arrived && !alarmActive) return response(state, "arrived", null, false, null);
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
                try { state.turns = pathfinder.find(state.position, state.destination, view); }
                catch (NavigationException blocked) {
                    if (view.excluded(state.position)) return escape(state, view, blocked.code());
                    throw blocked;
                }
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

    private Guidance escape(State state, RestrictedMap view, String reason) {
        state.escapeRoute = true;
        state.turns = pathfinder.escape(state.position, view); state.index = 0;
        state.segmentStart = state.position; state.routeId = UUID.randomUUID().toString(); state.arrived = false;
        return response(state, "escaping", state.turns.getFirst(), true, reason);
    }

    private static double length(MapPoint start, List<MapPoint> points) {
        double result = 0; MapPoint previous = start;
        for (MapPoint point : points) { result += previous.distanceTo(point); previous = point; }
        return result;
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
                recalculated, reason, WAYPOINT_TOLERANCE_M, ARRIVAL_TOLERANCE_M, alarmActive, revision);
    }

    static double segmentDistance(MapPoint point, MapPoint a, MapPoint b) {
        double dx = b.x() - a.x(), dy = b.y() - a.y(), lengthSquared = dx * dx + dy * dy;
        if (lengthSquared == 0) return point.distanceTo(a);
        double projection = Math.clamp(((point.x() - a.x()) * dx + (point.y() - a.y()) * dy) / lengthSquared, 0.0, 1.0);
        return point.distanceTo(new MapPoint(a.x() + projection * dx, a.y() + projection * dy));
    }

    private static class State {
        MapPoint position, destination, requestedDestination, segmentStart;
        long revision = -1;
        List<MapPoint> turns = List.of();
        int index;
        String routeId;
        boolean arrived, escapeRoute;
    }

    public record Guidance(String type, String status, String mapId, String routeId, MapPoint destination,
                           MapPoint nextWaypoint, Integer waypointIndex, int waypointCount,
                           Double distanceToWaypointM, Double remainingDistanceM, boolean recalculated,
                           String reason, double waypointToleranceM, double arrivalToleranceM, boolean alarmActive, long policyRevision) {}
}

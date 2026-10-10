package restservice.navigation;

import org.springframework.stereotype.Service;
import java.util.*;

@Service
public class Pathfinder {
    private final NavigationMap map;

    public Pathfinder(NavigationMap map) { this.map = map; }

    /** Returns turn points and the exact destination, without the starting point. */
    public List<MapPoint> find(MapPoint start, MapPoint destination) {
        map.requireWalkable(start, "POSITION");
        map.requireWalkable(destination, "DESTINATION");
        if (map.lineOfSight(start, destination)) return List.of(destination);

        int width = map.width(), size = width * map.height();
        int first = map.row(start) * width + map.column(start);
        int goal = map.row(destination) * width + map.column(destination);
        int[] cost = new int[size], parent = new int[size];
        Arrays.fill(cost, Integer.MAX_VALUE);
        Arrays.fill(parent, -1);
        var open = new PriorityQueue<Node>(Comparator.comparingInt(Node::estimate)
                .thenComparing(Comparator.comparingInt(Node::cost).reversed()).thenComparingInt(Node::index));
        cost[first] = 0;
        open.add(new Node(first, 0, heuristic(first, goal, width)));
        while (!open.isEmpty()) {
            var node = open.remove();
            if (cost[node.index()] != node.cost()) continue;
            if (node.index() == goal) return simplify(reconstruct(parent, first, goal, start, destination));
            int c = node.index() % width, r = node.index() / width;
            for (int direction = 0; direction < 4; direction++) {
                int nc = c + (direction == 0 ? -1 : direction == 1 ? 1 : 0);
                int nr = r + (direction == 2 ? -1 : direction == 3 ? 1 : 0);
                if (!map.canStep(c, r, nc, nr)) continue;
                int next = nr * width + nc, candidate = node.cost() + 1;
                if (candidate < cost[next]) {
                    cost[next] = candidate;
                    parent[next] = node.index();
                    open.add(new Node(next, candidate, candidate + heuristic(next, goal, width)));
                }
            }
        }
        throw new NavigationException("NO_ROUTE", "Brak dostępnej trasy do celu.");
    }

    public List<MapPoint> find(MapPoint start, MapPoint destination, NavigationMap view) {
        return new Pathfinder(view).find(start, destination);
    }

    /** Breadth-first escape to the closest safe cell; directed edges forbid re-entry. */
    public List<MapPoint> escape(MapPoint start, RestrictedMap view) {
        map.requireWalkable(start, "POSITION");
        int width = map.width(), size = width * map.height();
        boolean[] seen = new boolean[size];
        var queue = new ArrayDeque<Integer>();
        int first = map.row(start) * width + map.column(start);
        seen[first] = true; queue.add(first);
        while (!queue.isEmpty()) {
            int current = queue.remove(), c = current % width, r = current / width;
            MapPoint point = map.center(c, r);
            if (!view.excluded(point)) return find(start, point, view);
            for (int[] d : new int[][]{{-1,0},{1,0},{0,-1},{0,1}}) {
                int nc = c+d[0], nr = r+d[1];
                if (!view.canStep(c,r,nc,nr)) continue;
                int next = nr*width+nc;
                if (!seen[next]) { seen[next] = true; queue.add(next); }
            }
        }
        throw new NavigationException("NO_ESCAPE_ROUTE", "Brak dostępnego wyjścia ze strefy.");
    }

    private int heuristic(int a, int b, int width) {
        return Math.abs(a % width - b % width) + Math.abs(a / width - b / width);
    }

    private List<MapPoint> reconstruct(int[] parent, int first, int goal, MapPoint start, MapPoint destination) {
        var reversed = new ArrayList<MapPoint>();
        for (int index = goal; index != -1; index = parent[index]) {
            reversed.add(map.center(index % map.width(), index / map.width()));
            if (index == first) break;
        }
        Collections.reverse(reversed);
        var points = new ArrayList<MapPoint>();
        points.add(start);
        points.addAll(reversed);
        points.add(destination);
        return points;
    }

    private List<MapPoint> simplify(List<MapPoint> points) {
        var turns = new ArrayList<MapPoint>();
        int anchor = 0;
        while (anchor < points.size() - 1) {
            int farthest = points.size() - 1;
            while (farthest > anchor && !map.lineOfSight(points.get(anchor), points.get(farthest))) farthest--;
            if (farthest == anchor) throw new NavigationException("NO_ROUTE", "Brak bezpiecznego odcinka trasy.");
            turns.add(points.get(farthest));
            anchor = farthest;
        }
        return List.copyOf(turns);
    }

    private record Node(int index, int cost, int estimate) {}
}

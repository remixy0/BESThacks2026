package restservice.navigation;

import org.junit.jupiter.api.Test;
import org.springframework.core.io.ClassPathResource;
import tools.jackson.databind.json.JsonMapper;
import java.util.*;
import static org.assertj.core.api.Assertions.*;

class PathfinderTests {
    static NavigationMap openMap() {
        return new NavigationMap("test", 0, 0, 1, Collections.nCopies(20, "1".repeat(20)));
    }

    static NavigationMap wallMap() {
        var rows = new ArrayList<>(Collections.nCopies(12, "111112111111"));
        rows.set(9, "111111111111");
        rows.set(10, "111111111111");
        rows.set(11, "111111111111");
        return new NavigationMap("wall", 0, 0, 1, rows);
    }

    @Test
    void openSpaceReturnsExactDestinationAtAnArbitraryAngle() {
        var destination = new MapPoint(18.72, 12.23);
        assertThat(new Pathfinder(openMap()).find(new MapPoint(1.3, 1.4), destination)).containsExactly(destination);
    }

    @Test
    void routesAroundWallAndRemovesEveryUnnecessaryGridPoint() {
        var map = wallMap();
        var start = new MapPoint(1.5, 1.5);
        var end = new MapPoint(9.3, 1.7);
        var turns = new Pathfinder(map).find(start, end);
        assertThat(turns.size()).isBetween(2, 6);
        assertThat(turns.getLast()).isEqualTo(end);
        var previous = start;
        for (int i = 0; i < turns.size(); i++) {
            assertThat(map.lineOfSight(previous, turns.get(i))).isTrue();
            if (i + 1 < turns.size()) assertThat(map.lineOfSight(previous, turns.get(i + 1))).isFalse();
            previous = turns.get(i);
        }
    }

    @Test
    void rejectsBlockedEndpointsAndDisconnectedDestinations() {
        var map = new NavigationMap("separate", -2, -2, 1, List.of("11211", "11211", "11211"));
        assertThatThrownBy(() -> new Pathfinder(map).find(new MapPoint(-1.5, -.5), new MapPoint(1.5, -.5)))
                .isInstanceOfSatisfying(NavigationException.class, e -> assertThat(e.code()).isEqualTo("NO_ROUTE"));
        assertThatThrownBy(() -> map.requireWalkable(new MapPoint(.5, -.5), "DESTINATION"))
                .isInstanceOfSatisfying(NavigationException.class, e -> assertThat(e.code()).isEqualTo("DESTINATION_BLOCKED"));
        assertThatThrownBy(() -> map.requireWalkable(new MapPoint(3, 0), "POSITION"))
                .isInstanceOfSatisfying(NavigationException.class, e -> assertThat(e.code()).isEqualTo("POSITION_OUTSIDE_MAP"));
        assertThatThrownBy(() -> map.requireWalkable(new MapPoint(Double.NaN, 0), "POSITION"))
                .isInstanceOf(NavigationException.class);
    }

    @Test
    void neverCutsBlockedCornersOrTravelsAlongBlockedEdges() {
        var map = new NavigationMap("corner", 0, 0, 1, List.of("1111", "1121", "1211", "1111"));
        assertThat(map.lineOfSight(new MapPoint(1.5, 1.5), new MapPoint(2.5, 2.5))).isFalse();
        assertThat(map.lineOfSight(new MapPoint(1, 1.5), new MapPoint(1, 3.5))).isFalse();
        assertThat(map.lineOfSight(new MapPoint(.5, .5), new MapPoint(3.5, .5))).isTrue();
    }

    @Test
    void supercoverMatchesIndependentSegmentRectangleCollisionChecks() {
        var rows = List.of("11111111", "11211111", "11111211", "11121111", "11111111", "12111111", "11111111", "11111111");
        var map = new NavigationMap("oracle", 0, 0, 1, rows);
        var random = new Random(25);
        for (int i = 0; i < 600; i++) {
            var a = new MapPoint(.5 + random.nextInt(14)*.5, .5 + random.nextInt(14)*.5);
            var b = new MapPoint(.5 + random.nextInt(14)*.5, .5 + random.nextInt(14)*.5);
            boolean clear = true;
            for (int r = 0; r < 8; r++) for (int c = 0; c < 8; c++) {
                if (rows.get(r).charAt(c) != '1' && intersects(a, b, c, r)) clear = false;
            }
            assertThat(map.lineOfSight(a, b)).as("%s -> %s", a, b).isEqualTo(clear);
            assertThat(map.lineOfSight(b, a)).isEqualTo(clear);
        }
    }

    private boolean intersects(MapPoint a, MapPoint b, int column, int row) {
        double low = 0, high = 1;
        double[] starts = {a.x(), a.y()}, changes = {b.x()-a.x(), b.y()-a.y()}, mins = {column, row};
        for (int axis = 0; axis < 2; axis++) {
            if (changes[axis] == 0) {
                if (starts[axis] < mins[axis] || starts[axis] > mins[axis]+1) return false;
            } else {
                double first = (mins[axis]-starts[axis])/changes[axis];
                double second = (mins[axis]+1-starts[axis])/changes[axis];
                low = Math.max(low, Math.min(first, second));
                high = Math.min(high, Math.max(first, second));
                if (low > high) return false;
            }
        }
        return true;
    }

    @Test
    void museumRoutesToAllAccessiblePoisHaveCollisionFreeTurnSegments() throws Exception {
        var json = new JsonMapper();
        var map = new NavigationMap(json);
        var finder = new Pathfinder(map);
        try (var input = new ClassPathResource("maps/field-museum-main-level.grid.json").getInputStream()) {
            var data = json.readTree(input);
            var startNode = data.get("navigation").get("start");
            var start = new MapPoint(startNode.get("x").doubleValue(), startNode.get("y").doubleValue());
            int checked = 0;
            for (var poi : data.get("pointsOfInterest")) {
                var approach = poi.get("approach");
                if (approach.isNull()) continue;
                var end = new MapPoint(approach.get("x").doubleValue(), approach.get("y").doubleValue());
                var turns = finder.find(start, end);
                assertThat(turns.getLast()).isEqualTo(end);
                var previous = start;
                for (var turn : turns) {
                    assertThat(map.lineOfSight(previous, turn)).as(poi.get("id").asText()).isTrue();
                    previous = turn;
                }
                checked++;
            }
            assertThat(checked).isEqualTo(24);
        }
    }
}

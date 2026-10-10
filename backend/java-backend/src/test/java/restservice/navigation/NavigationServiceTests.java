package restservice.navigation;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.*;

class NavigationServiceTests {
    @Test
    void keepsWaypointUntilTurnThenAdvancesUntilArrival() {
        var map = PathfinderTests.wallMap();
        var service = new NavigationService(map, new Pathfinder(map));
        var start = new MapPoint(1.5, 1.5);
        var end = new MapPoint(9.3, 1.7);
        assertThat(service.position("one", start)).isNull();
        var guidance = service.destination("one", end);
        assertThat(guidance.status()).isEqualTo("navigating");
        assertThat(guidance.recalculated()).isTrue();
        var first = guidance.nextWaypoint();
        var moved = new MapPoint(start.x()*.9+first.x()*.1, start.y()*.9+first.y()*.1);
        var unchanged = service.position("one", moved);
        assertThat(unchanged.nextWaypoint()).isEqualTo(first);
        assertThat(unchanged.routeId()).isEqualTo(guidance.routeId());
        assertThat(unchanged.recalculated()).isFalse();
        String routeId = guidance.routeId();
        int updates = 0;
        while (guidance.nextWaypoint() != null && updates++ < 20) {
            var previous = guidance.nextWaypoint();
            guidance = service.position("one", previous);
            if (guidance.nextWaypoint() != null) assertThat(guidance.nextWaypoint()).isNotEqualTo(previous);
            assertThat(guidance.routeId()).isEqualTo(routeId);
        }
        assertThat(guidance.status()).isEqualTo("arrived");
        assertThat(guidance.remainingDistanceM()).isZero();
    }

    @Test
    void waitsForPositionAndKeepsConnectionsIndependent() {
        var map = PathfinderTests.openMap();
        var service = new NavigationService(map, new Pathfinder(map));
        var target = new MapPoint(18, 12);
        assertThat(service.destination("one", target).status()).isEqualTo("awaiting_position");
        assertThat(service.position("two", new MapPoint(2, 3))).isNull();
        assertThat(service.position("one", new MapPoint(2, 3)).nextWaypoint()).isEqualTo(target);
        assertThat(service.cancel("one").status()).isEqualTo("cancelled");
        assertThat(service.position("one", new MapPoint(3, 4))).isNull();
        service.destination("one", target);
        service.remove("one");
        assertThat(service.position("one", new MapPoint(3, 4))).isNull();
    }

    @Test
    void recalculatesAfterDeviationAndRecoversFromInvalidLocation() {
        var map = PathfinderTests.openMap();
        var service = new NavigationService(map, new Pathfinder(map));
        service.position("one", new MapPoint(1, 1));
        var initial = service.destination("one", new MapPoint(18, 1));
        var deviation = service.position("one", new MapPoint(3, 4));
        assertThat(deviation.recalculated()).isTrue();
        assertThat(deviation.routeId()).isNotEqualTo(initial.routeId());
        var invalid = service.position("one", new MapPoint(-10, -10));
        assertThat(invalid.status()).isEqualTo("blocked");
        assertThat(invalid.reason()).isEqualTo("POSITION_OUTSIDE_MAP");
        assertThat(invalid.nextWaypoint()).isNull();
        assertThat(service.position("one", new MapPoint(3, 4)).status()).isEqualTo("navigating");
    }

    @Test
    void nearCornerDoesNotPermitAnUnsafeEarlyTurn() {
        var map = PathfinderTests.wallMap();
        var service = new NavigationService(map, new Pathfinder(map));
        var start = new MapPoint(1.5, 1.5);
        service.position("one", start);
        var first = service.destination("one", new MapPoint(9.5, 1.5));
        var corner = first.nextWaypoint();
        double length = start.distanceTo(corner);
        var approaching = new MapPoint(corner.x()+(start.x()-corner.x())*.35/length,
                corner.y()+(start.y()-corner.y())*.35/length);
        var next = service.position("one", approaching);
        assertThat(map.lineOfSight(approaching, next.nextWaypoint())).isTrue();
    }

    @Test
    void invalidReplacementDoesNotOverwriteCurrentDestination() {
        var map = PathfinderTests.openMap();
        var service = new NavigationService(map, new Pathfinder(map));
        service.position("one", new MapPoint(1, 1));
        var target = new MapPoint(18, 12);
        service.destination("one", target);
        assertThatThrownBy(() -> service.destination("one", new MapPoint(500, 500))).isInstanceOf(NavigationException.class);
        assertThat(service.position("one", new MapPoint(1, 1)).destination()).isEqualTo(target);
    }
}

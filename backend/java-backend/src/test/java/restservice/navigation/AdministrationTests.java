package restservice.navigation;

import org.junit.jupiter.api.Test;
import tools.jackson.databind.json.JsonMapper;
import java.util.List;
import static org.assertj.core.api.Assertions.*;

class AdministrationTests {
    @Test void protectsUserWithoutGoalAndWaitsForPositionDuringAlarm() {
        var map = PathfinderTests.openMap(); var service = new NavigationService(map,new Pathfinder(map));
        service.position("u",new MapPoint(8.5,8.5)); service.addZone(7,7,11,11);
        assertThat(service.refresh("u").status()).isEqualTo("escaping");
        assertThat(service.cancel("u").status()).isEqualTo("escaping");
        service.alarm(true);
        var waiting = service.destination("new",new MapPoint(15.5,15.5));
        assertThat(waiting.status()).isEqualTo("awaiting_position");
        assertThat(waiting.destination()).isNull();
        assertThat(waiting.alarmActive()).isTrue();
    }

    @Test void routesAroundZonesAndRestoresDirectRouteAfterRemoval() {
        var map = PathfinderTests.openMap();
        var service = new NavigationService(map,new Pathfinder(map));
        var start = new MapPoint(2.5,8.5); var goal = new MapPoint(17.5,8.5);
        service.position("u",start);
        assertThat(service.destination("u",goal).nextWaypoint()).isEqualTo(goal);
        var zone = service.addZone(8,5,11,12).zones().getFirst();
        var guidance = service.refresh("u");
        assertThat(guidance.recalculated()).isTrue();
        assertThat(guidance.nextWaypoint()).isNotEqualTo(goal);
        var view = new RestrictedMap(map,List.of(zone),start);
        MapPoint previous = start;
        for (var point : new Pathfinder(map).find(start,goal,view)) {
            assertThat(view.lineOfSight(previous,point)).isTrue();
            assertThat(view.excluded(point)).isFalse(); previous = point;
        }
        service.removeZone(zone.id());
        assertThat(service.refresh("u").nextWaypoint()).isEqualTo(goal);
    }

    @Test void leavesNewZoneAndContinuesToGoalWithoutReentry() {
        var map = PathfinderTests.openMap();
        var service = new NavigationService(map,new Pathfinder(map));
        var start = new MapPoint(8.5,8.5); var goal = new MapPoint(17.5,8.5);
        service.position("u",start); service.destination("u",goal);
        var zone = service.addZone(7,7,10,10).zones().getFirst();
        var guidance = service.refresh("u");
        assertThat(guidance.status()).isEqualTo("navigating");
        var view = new RestrictedMap(map,List.of(zone),start);
        assertThat(view.lineOfSight(start,guidance.nextWaypoint())).isTrue();
        assertThat(view.lineOfSight(goal,start)).isFalse();
        assertThat(service.position("u",goal).status()).isEqualTo("arrived");
    }

    @Test void overlappingZonesDoNotPermitEnteringAnotherZone() {
        var map = PathfinderTests.openMap(); var start = new MapPoint(5.5,8.5); var goal = new MapPoint(17.5,8.5);
        var zones = List.of(new ExclusionZone("a",4,6,8,11),new ExclusionZone("b",7,7,12,13));
        var view = new RestrictedMap(map,zones,start);
        var forbidden = new RestrictedMap(map,List.of(zones.get(1)),null);
        MapPoint previous = start;
        for (MapPoint point : new Pathfinder(map).find(start,goal,view)) {
            assertThat(forbidden.lineOfSight(previous,point)).isTrue(); previous = point;
        }
    }

    @Test void escapesEvenWhenGoalIsBlockedAndResumesAfterZoneRemoval() {
        var map = PathfinderTests.openMap(); var service = new NavigationService(map,new Pathfinder(map));
        service.position("u",new MapPoint(8.5,8.5)); service.destination("u",new MapPoint(9.5,9.5));
        var zone = service.addZone(7,7,11,11).zones().getFirst();
        var result = service.refresh("u");
        assertThat(result.status()).isEqualTo("escaping");
        int steps=0;
        while (result.status().equals("escaping") && steps++<20) result = service.position("u",result.nextWaypoint());
        assertThat(result.status()).isEqualTo("blocked");
        assertThat(result.reason()).isEqualTo("DESTINATION_BLOCKED");
        service.removeZone(zone.id());
        assertThat(service.refresh("u").status()).isEqualTo("navigating");
    }

    @Test void evacuatesWithoutSelectedGoalAndCannotCancelAlarm() throws Exception {
        var map = new NavigationMap(JsonMapper.builder().build()); var service = new NavigationService(map,new Pathfinder(map));
        var exit = map.exits().getFirst();
        service.position("u",exit); service.alarm(true);
        var result = service.refresh("u");
        assertThat(result.alarmActive()).isTrue();
        assertThat(result.destination()).isEqualTo(exit);
        assertThat(result.status()).isEqualTo("arrived");
        assertThat(service.cancel("u").alarmActive()).isTrue();
        var goal = map.exits().getLast();
        assertThat(service.destination("u",goal).destination()).isEqualTo(exit);
        service.alarm(false);
        assertThat(service.refresh("u").destination()).isEqualTo(goal);
    }

    @Test void usesAlternativeExitAndReportsWhenAllExitsAreBlocked() throws Exception {
        var map = new NavigationMap(JsonMapper.builder().build()); var service = new NavigationService(map,new Pathfinder(map));
        service.position("u",new MapPoint(-.5,51.9)); service.alarm(true);
        MapPoint nearest = service.refresh("u").destination();
        service.addZone(nearest.x()-.1,nearest.y()-.1,nearest.x()+.1,nearest.y()+.1);
        var alternative = service.refresh("u");
        assertThat(alternative.status()).isEqualTo("navigating");
        assertThat(alternative.destination()).isNotEqualTo(nearest);
        MapPoint other = alternative.destination();
        service.addZone(other.x()-.1,other.y()-.1,other.x()+.1,other.y()+.1);
        var blocked = service.refresh("u");
        assertThat(blocked.status()).isIn("blocked","escaping");
        assertThat(blocked.reason()).isEqualTo("NO_REACHABLE_EXIT");
    }

    @Test void rejectsMalformedZonesAndUnreachableEscape() {
        var map = PathfinderTests.openMap(); var service = new NavigationService(map,new Pathfinder(map));
        assertThatThrownBy(() -> service.addZone(5,5,4,7)).isInstanceOf(NavigationException.class);
        assertThatThrownBy(() -> service.addZone(Double.NaN,0,1,1)).isInstanceOf(NavigationException.class);
        assertThatThrownBy(() -> service.addZone(-1,0,1,1)).isInstanceOf(NavigationException.class);
        assertThatThrownBy(() -> service.removeZone("missing")).isInstanceOf(NavigationException.class);
        service.position("u",new MapPoint(8.5,8.5)); service.addZone(0,0,20,20);
        assertThat(service.refresh("u").reason()).isEqualTo("NO_ESCAPE_ROUTE");
    }
}

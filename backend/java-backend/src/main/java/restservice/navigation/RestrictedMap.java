package restservice.navigation;

import java.util.List;

/** Immutable routing snapshot. Inside -> outside is allowed, outside -> inside never is. */
public final class RestrictedMap extends NavigationMap {
    public static final double CLEARANCE_M = 0.3;
    private final List<Box> boxes;
    private final MapPoint start;

    public RestrictedMap(NavigationMap base, List<ExclusionZone> zones, MapPoint start) {
        super(base);
        this.start = start;
        boxes = zones.stream().map(z -> {
            int c0 = column(new MapPoint(z.minX()-CLEARANCE_M, z.minY()-CLEARANCE_M));
            int r0 = row(new MapPoint(z.minX()-CLEARANCE_M, z.minY()-CLEARANCE_M));
            int c1 = column(new MapPoint(z.maxX()+CLEARANCE_M, z.maxY()+CLEARANCE_M));
            int r1 = row(new MapPoint(z.maxX()+CLEARANCE_M, z.maxY()+CLEARANCE_M));
            return new Box(center(c0,r0).x()-cellSize()/2, center(c0,r0).y()-cellSize()/2,
                    center(c1,r1).x()+cellSize()/2, center(c1,r1).y()+cellSize()/2);
        }).toList();
    }

    public boolean excluded(MapPoint point) { return boxes.stream().anyMatch(b -> b.contains(point)); }

    @Override public boolean walkable(int c, int r) {
        if (!super.walkable(c,r)) return false;
        MapPoint point = center(c,r);
        return boxes.stream().noneMatch(b -> b.contains(point) && (start == null || !b.contains(start)));
    }

    @Override public void requireWalkable(MapPoint point, String role) {
        super.requireWalkable(point, role);
        if (role.equals("DESTINATION") && excluded(point))
            throw new NavigationException("DESTINATION_BLOCKED", "Cel znajduje się w wyłączonej strefie.");
    }

    @Override public boolean canStep(int c, int r, int nc, int nr) {
        return walkable(nc,nr) && lineOfSight(center(c,r), center(nc,nr));
    }

    @Override public boolean lineOfSight(MapPoint from, MapPoint to) {
        if (!super.lineOfSight(from,to)) return false;
        return boxes.stream().noneMatch(b -> !b.contains(from) && b.intersects(from,to));
    }

    private record Box(double minX, double minY, double maxX, double maxY) {
        boolean contains(MapPoint p) {
            return p.x() >= minX-1e-9 && p.x() <= maxX+1e-9 && p.y() >= minY-1e-9 && p.y() <= maxY+1e-9;
        }
        boolean intersects(MapPoint a, MapPoint b) {
            double low = 0, high = 1;
            double[] origin = {a.x(), a.y()}, delta = {b.x()-a.x(), b.y()-a.y()};
            double[] min = {minX-1e-9,minY-1e-9}, max = {maxX+1e-9,maxY+1e-9};
            for (int axis=0;axis<2;axis++) {
                if (delta[axis] == 0) { if (origin[axis]<min[axis] || origin[axis]>max[axis]) return false; }
                else {
                    double t1=(min[axis]-origin[axis])/delta[axis], t2=(max[axis]-origin[axis])/delta[axis];
                    low=Math.max(low,Math.min(t1,t2)); high=Math.min(high,Math.max(t1,t2));
                    if(low>high) return false;
                }
            }
            return true;
        }
    }
}

package restservice.navigation;

public record MapPoint(double x, double y) {
    public double distanceTo(MapPoint other) {
        return Math.hypot(x - other.x, y - other.y);
    }
}

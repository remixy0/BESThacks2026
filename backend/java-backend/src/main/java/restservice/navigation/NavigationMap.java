package restservice.navigation;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;
import tools.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

@Component
public class NavigationMap {
    private static final double EPSILON = 1e-9;
    private final String id;
    private final double originX, originY, cellSize;
    private final int width, height;
    private final List<String> rows;

    @Autowired
    public NavigationMap(ObjectMapper json) throws IOException {
        try (var input = new ClassPathResource("maps/field-museum-main-level.grid.json").getInputStream()) {
            var data = json.readTree(input);
            id = data.get("id").asText();
            originX = data.get("origin").get("x").doubleValue();
            originY = data.get("origin").get("y").doubleValue();
            cellSize = data.get("cellSizeM").doubleValue();
            width = data.get("width").intValue();
            height = data.get("height").intValue();
            var loaded = new ArrayList<String>();
            for (var row : data.get("cells")) loaded.add(row.asText());
            rows = List.copyOf(loaded);
            validate();
        }
    }

    public NavigationMap(String id, double originX, double originY, double cellSize, List<String> rows) {
        this.id = id;
        this.originX = originX;
        this.originY = originY;
        this.cellSize = cellSize;
        this.rows = List.copyOf(rows);
        height = rows.size();
        width = rows.isEmpty() ? 0 : rows.getFirst().length();
        validate();
    }

    private void validate() {
        if (width <= 0 || height <= 0 || rows.size() != height || cellSize <= 0
                || !Double.isFinite(cellSize) || !Double.isFinite(originX) || !Double.isFinite(originY)
                || (long) width * height > Integer.MAX_VALUE
                || rows.stream().anyMatch(row -> row.length() != width || !row.matches("[0-5]+"))) {
            throw new IllegalArgumentException("Invalid navigation map");
        }
    }

    public String id() { return id; }
    public int width() { return width; }
    public int height() { return height; }
    public double cellSize() { return cellSize; }

    public boolean walkable(int column, int row) {
        return column >= 0 && row >= 0 && column < width && row < height && rows.get(row).charAt(column) == '1';
    }

    public int column(MapPoint p) { return (int) Math.floor(gridX(p)); }
    public int row(MapPoint p) { return (int) Math.floor(gridY(p)); }

    public MapPoint center(int column, int row) {
        return new MapPoint(originX + (column + .5) * cellSize, originY + (row + .5) * cellSize);
    }

    public void requireWalkable(MapPoint p, String role) {
        if (!Double.isFinite(p.x()) || !Double.isFinite(p.y())) {
            throw new NavigationException(role + "_INVALID", "Współrzędne muszą być skończonymi liczbami.");
        }
        if (p.x() < originX || p.y() < originY || p.x() >= originX + width * cellSize
                || p.y() >= originY + height * cellSize) {
            throw new NavigationException(role + "_OUTSIDE_MAP", "Punkt znajduje się poza mapą.");
        }
        if (!clearPoint(gridX(p), gridY(p))) {
            throw new NavigationException(role + "_BLOCKED", "Punkt znajduje się w zablokowanej komórce lub na jej granicy.");
        }
    }

    private double gridX(MapPoint p) { return normalize((p.x() - originX) / cellSize); }
    private double gridY(MapPoint p) { return normalize((p.y() - originY) / cellSize); }
    private double normalize(double value) {
        return Math.abs(value - Math.rint(value)) < EPSILON ? Math.rint(value) : value;
    }
    private boolean integral(double value) { return value == Math.rint(value); }

    private boolean clearPoint(double x, double y) {
        if (!Double.isFinite(x) || !Double.isFinite(y) || x < 0 || y < 0 || x >= width || y >= height) return false;
        int c = (int) Math.floor(x), r = (int) Math.floor(y);
        return walkable(c, r) && (!integral(x) || walkable(c - 1, r))
                && (!integral(y) || walkable(c, r - 1))
                && (!(integral(x) && integral(y)) || walkable(c - 1, r - 1));
    }

    /** Supercover grid traversal: touching a blocked edge or corner is not a safe shortcut. */
    public boolean lineOfSight(MapPoint from, MapPoint to) {
        double ax = gridX(from), ay = gridY(from), bx = gridX(to), by = gridY(to);
        if (!clearPoint(ax, ay) || !clearPoint(bx, by)) return false;
        double dx = bx - ax, dy = by - ay;
        int c = (int) Math.floor(ax), r = (int) Math.floor(ay);
        int ec = (int) Math.floor(bx), er = (int) Math.floor(by);
        int sx = Double.compare(dx, 0), sy = Double.compare(dy, 0);
        double deltaX = sx == 0 ? Double.POSITIVE_INFINITY : 1 / Math.abs(dx);
        double deltaY = sy == 0 ? Double.POSITIVE_INFINITY : 1 / Math.abs(dy);
        double nextX = sx == 0 ? Double.POSITIVE_INFINITY : ((sx > 0 ? c + 1 : c) - ax) / dx;
        double nextY = sy == 0 ? Double.POSITIVE_INFINITY : ((sy > 0 ? r + 1 : r) - ay) / dy;
        boolean verticalBoundary = sx == 0 && integral(ax);
        boolean horizontalBoundary = sy == 0 && integral(ay);
        for (int steps = 0; steps <= width + height + 2; steps++) {
            if (!walkable(c, r) || (verticalBoundary && !walkable(c - 1, r))
                    || (horizontalBoundary && !walkable(c, r - 1))) return false;
            if (c == ec && r == er) return true;
            // At an endpoint corner, a simultaneous step can overshoot the final
            // cell on a decreasing axis. clearPoint already checked all endpoint neighbours.
            if (Math.min(nextX, nextY) >= 1 - EPSILON) return true;
            if (Math.abs(nextX - nextY) < EPSILON) {
                if (!walkable(c + sx, r) || !walkable(c, r + sy)) return false;
                c += sx;
                r += sy;
                nextX += deltaX;
                nextY += deltaY;
            } else if (nextX < nextY) {
                c += sx;
                nextX += deltaX;
            } else {
                r += sy;
                nextY += deltaY;
            }
        }
        return false;
    }
}

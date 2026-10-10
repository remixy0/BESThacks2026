package restservice.navigation;

/** Map coordinates in metres. The routing view adds pedestrian clearance. */
public record ExclusionZone(String id, double minX, double minY, double maxX, double maxY) {}

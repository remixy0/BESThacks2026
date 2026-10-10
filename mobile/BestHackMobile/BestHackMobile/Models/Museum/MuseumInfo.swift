import Foundation
import simd

/// Everything we know about the Field Museum's Main Level, from `FieldMuseum_MainLevel_info.json`.
///
/// Coordinates are metres: +X east, -Z north, +Y up, floor at y = 0, origin = centre of the building.
nonisolated struct MuseumInfo: Decodable, Sendable {
    struct Exhibit: Decodable, Identifiable, Hashable, Sendable {
        let key: String
        /// Path inside the floor scene, e.g. "Exhibits/Maximo".
        let node: String
        let title: String
        let gallery: String
        let text: String
        let position: [Float]
        let yawDegrees: Float
        /// e.g. "Artifacts/Maximo.usdz", the high-detail stand-alone model.
        let detailModel: String
        /// Width x depth in metres, before rotation.
        let footprint: [Float]?

        var id: String { key }

        /// Position on the floor plan: (x, z).
        var floorPoint: SIMD2<Float> { SIMD2(position[0], position[2]) }

        /// Bundle resource name of the detailed model, e.g. "Maximo".
        var detailResource: String {
            ((detailModel as NSString).lastPathComponent as NSString).deletingPathExtension
        }

        /// Half the size along x (east-west) and z (north-south), taking the exhibit's rotation into account.
        var halfExtents: SIMD2<Float> {
            let size = footprint ?? [4, 4]
            let sideways = abs(abs(yawDegrees) - 90) < 45
            let w = (size.first ?? 4) / 2
            let d = (size.count > 1 ? size[1] : size.first ?? 4) / 2
            return sideways ? SIMD2(d, w) : SIMD2(w, d)
        }

        enum CodingKeys: String, CodingKey {
            case key, node, title, gallery, text, position
            case yawDegrees = "yaw_degrees"
            case detailModel = "detail_model"
            case footprint = "footprint_m"
        }
    }

    struct Room: Decodable, Identifiable, Sendable {
        let id: String
        let node: String
        let name: String?
        let theme: String
        let status: String
        /// Floor-plan polygon as [[x, z], ...].
        let outline: [[Float]]
        /// The outline as floor points (worked out once: the guide asks "which room am I in?" often).
        let polygon: [SIMD2<Float>]
        /// The middle of the room, for its label.
        let center: SIMD2<Float>
        private let minCorner: SIMD2<Float>
        private let maxCorner: SIMD2<Float>

        enum CodingKeys: String, CodingKey {
            case id, node, name, theme, status, outline
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            node = try container.decode(String.self, forKey: .node)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            theme = try container.decode(String.self, forKey: .theme)
            status = try container.decode(String.self, forKey: .status)
            outline = try container.decode([[Float]].self, forKey: .outline)
            let points = outline.compactMap { $0.count >= 2 ? SIMD2($0[0], $0[$0.count - 1]) : nil }
            polygon = points
            center = points.isEmpty ? .zero : points.reduce(SIMD2<Float>.zero, +) / Float(points.count)
            minCorner = points.reduce(SIMD2<Float>(repeating: .greatestFiniteMagnitude)) { simd_min($0, $1) }
            maxCorner = points.reduce(SIMD2<Float>(repeating: -.greatestFiniteMagnitude)) { simd_max($0, $1) }
        }

        func contains(_ point: SIMD2<Float>) -> Bool {
            // Cheap box test first.
            guard point.x >= minCorner.x, point.x <= maxCorner.x, point.y >= minCorner.y, point.y <= maxCorner.y else { return false }
            return MuseumGeometry.polygon(polygon, contains: point)
        }
    }

    struct PointOfInterest: Decodable, Identifiable, Sendable {
        let node: String
        /// "exhibit", "entrance" or "amenity".
        let kind: String
        let label: String?
        let position: [Float]

        var id: String { node }
        var floorPoint: SIMD2<Float> { SIMD2(position[0], position[2]) }
    }

    struct Meta: Decodable, Sendable {
        struct Nave: Decodable, Sendable {
            let x: [Float]
            let z: [Float]
        }
        let nave: Nave?
    }

    let exhibits: [Exhibit]
    let rooms: [Room]
    let pointsOfInterest: [PointOfInterest]
    let meta: Meta?
    /// The building's outer wall as [[x, z], ...].
    let buildingOutline: [[Float]]?

    enum CodingKeys: String, CodingKey {
        case exhibits, rooms, meta
        case pointsOfInterest = "points_of_interest"
        case buildingOutline = "building_outline"
    }

    /// The building's outer wall as floor points.
    var outline: [SIMD2<Float>] {
        (buildingOutline ?? []).compactMap { $0.count >= 2 ? SIMD2($0[0], $0[$0.count - 1]) : nil }
    }

    /// The `count` exhibits closest to `point`, nearest first (optionally leaving one out).
    func nearest(to point: SIMD2<Float>, count: Int, excluding key: String? = nil) -> [Exhibit] {
        Array(exhibits.filter { $0.key != key }
            .sorted { simd_distance($0.floorPoint, point) < simd_distance($1.floorPoint, point) }
            .prefix(count))
    }

    /// Stanley Field Hall as a rectangle (x0, z0, x1, z1).
    var hallRect: (min: SIMD2<Float>, max: SIMD2<Float>) {
        guard let nave = meta?.nave, nave.x.count == 2, nave.z.count == 2 else {
            return (SIMD2(-12, -45), SIMD2(10.8, 45))
        }
        return (SIMD2(nave.x[0], nave.z[0]), SIMD2(nave.x[1], nave.z[1]))
    }

    // MARK: - Floor-plan helpers

    /// Stanley Field Hall, the great central hall (not in the room list).
    var hallName: String { "Stanley Field Hall" }

    func isInHall(_ point: SIMD2<Float>) -> Bool {
        guard let nave = meta?.nave, nave.x.count == 2, nave.z.count == 2 else {
            return abs(point.x) < 12 && abs(point.y) < 45
        }
        return point.x >= nave.x[0] && point.x <= nave.x[1] && point.y >= nave.z[0] && point.y <= nave.z[1]
    }

    /// The named room at a floor point, if any.
    func room(at point: SIMD2<Float>) -> Room? {
        rooms.first { $0.name != nil && $0.contains(point) }
    }

    /// "Birds", "Stanley Field Hall", or "Corridor".
    func placeName(at point: SIMD2<Float>) -> String {
        if let name = room(at: point)?.name { return name }
        if isInHall(point) { return hallName }
        let entrance = pointsOfInterest.first { $0.kind == "entrance" && simd_distance($0.floorPoint, point) < 16 }
        return entrance?.label ?? "Corridor"
    }

    /// Where to stand to look at an exhibit: just outside its footprint, inside the same room,
    /// on the side closest to `from`. Falls back to the exhibit's centre (e.g. walk into the lodge).
    func viewingSpot(for exhibit: Exhibit, from: SIMD2<Float>) -> SIMD2<Float> {
        let center = exhibit.floorPoint
        let half = exhibit.halfExtents
        let margin: Float = 3.5
        let candidates: [SIMD2<Float>] = [
            center + SIMD2(0, half.y + margin),   // south
            center - SIMD2(0, half.y + margin),   // north
            center + SIMD2(half.x + margin, 0),   // east
            center - SIMD2(half.x + margin, 0),   // west
        ]

        let home = room(at: center)
        let valid = candidates.filter { spot in
            let inSameSpace = home.map { $0.contains(spot) } ?? isInHall(spot)
            return inSameSpace && !isBlocked(spot, except: exhibit)
        }
        guard !valid.isEmpty else { return center + SIMD2(0, 1) }
        return valid.min { simd_distance($0, from) < simd_distance($1, from) }!
    }

    /// True if `spot` is on top of (or right against) another exhibit.
    private func isBlocked(_ spot: SIMD2<Float>, except exhibit: Exhibit) -> Bool {
        exhibits.contains { other in
            guard other.key != exhibit.key else { return false }
            let reach = other.halfExtents + SIMD2<Float>(repeating: 1.5)
            return abs(spot.x - other.floorPoint.x) < reach.x && abs(spot.y - other.floorPoint.y) < reach.y
        }
    }

    /// Building outline used to keep the walker inside.
    static let bounds = (x: Float(-106)...Float(106), z: Float(-67)...Float(67))

    static func load() throws -> MuseumInfo {
        guard let url = MuseumAssets.url(named: "FieldMuseum_MainLevel_info", extension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(MuseumInfo.self, from: Data(contentsOf: url))
    }
}

/// Small 2D maths on the floor plan. Angles: 0 = north (-z), positive = counter-clockwise (to the left).
nonisolated enum MuseumGeometry {
    static func polygon(_ polygon: [SIMD2<Float>], contains point: SIMD2<Float>) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Direction you face for a yaw: yaw 0 looks north (-z).
    static func forward(yaw: Float) -> SIMD2<Float> {
        SIMD2(-sin(yaw), -cos(yaw))
    }

    /// The yaw that looks from `from` toward `to`.
    static func yaw(from: SIMD2<Float>, to: SIMD2<Float>) -> Float {
        let d = to - from
        return atan2(-d.x, -d.y)
    }

    /// Wraps an angle into -pi...pi.
    static func wrap(_ angle: Float) -> Float {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }
}

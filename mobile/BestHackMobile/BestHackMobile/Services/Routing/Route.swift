import Foundation
import simd

/// Maths on a walking route: a polyline of floor-plan points (x, z) in metres.
nonisolated enum RouteMath {
    /// Where you are relative to the route.
    struct Progress: Sendable {
        /// Index of the segment you're on (route[segment] -> route[segment + 1]).
        let segment: Int
        /// The closest point on the route.
        let point: SIMD2<Float>
        /// How far you are from the route, in metres.
        let offset: Float
    }

    /// Closest point on the route, searching from `startSegment` onward (routes are walked forward).
    static func progress(of position: SIMD2<Float>, along route: [SIMD2<Float>], from startSegment: Int) -> Progress {
        guard route.count >= 2 else {
            let only = route.first ?? position
            return Progress(segment: 0, point: only, offset: simd_distance(only, position))
        }
        let first = min(max(startSegment, 0), route.count - 2)
        var best = Progress(segment: first, point: route[first], offset: .infinity)
        for i in first..<(route.count - 1) {
            let a = route[i], b = route[i + 1]
            let ab = b - a
            let lengthSquared = simd_length_squared(ab)
            let t = lengthSquared > 0 ? min(max(simd_dot(position - a, ab) / lengthSquared, 0), 1) : 0
            let closest = a + ab * t
            let offset = simd_distance(position, closest)
            if offset < best.offset - 0.01 {
                best = Progress(segment: i, point: closest, offset: offset)
            }
        }
        return best
    }

    /// Metres left to walk from `progress` to the end of the route.
    static func remainingLength(of route: [SIMD2<Float>], from progress: Progress) -> Float {
        guard route.count >= 2 else { return progress.offset }
        var total = simd_distance(progress.point, route[progress.segment + 1])
        if progress.segment + 2 < route.count {
            for i in (progress.segment + 1)..<(route.count - 1) {
                total += simd_distance(route[i], route[i + 1])
            }
        }
        return total
    }

    /// The point `distance` metres further along the route (clamped to its end).
    static func point(on route: [SIMD2<Float>], from progress: Progress, ahead distance: Float) -> SIMD2<Float> {
        guard route.count >= 2 else { return route.first ?? progress.point }
        var left = distance
        var current = progress.point
        var index = progress.segment + 1
        while index < route.count {
            let next = route[index]
            let step = simd_distance(current, next)
            if step >= left {
                return step > 0 ? current + (next - current) * (left / step) : next
            }
            left -= step
            current = next
            index += 1
        }
        return route[route.count - 1]
    }
}

/// Reads a route from JSON. Accepts any of these shapes (numbers or numeric strings):
///
///     [[x, y], [x, y], ...]
///     [{"x": 1.5, "y": -20}, ...]
///     {"route": [...]}   // also "points", "path", "coordinates" or "waypoints"
///
/// x = metres east, y = the model's z (metres south, same as `position[2]` in FieldMuseum_MainLevel_info.json),
/// origin = centre of the building. If your service uses +y = north instead, pass `.north`.
nonisolated enum RouteDecoder {
    enum YAxis: String, Sendable {
        /// +y = south (the model's z). Default.
        case modelZ = "model_z"
        /// +y = north.
        case north
    }

    enum DecodeError: LocalizedError {
        case badFormat
        var errorDescription: String? { "The route JSON isn't a list of (x, y) points." }
    }

    static func decode(_ data: Data, yAxis: YAxis = .modelZ) throws -> [SIMD2<Float>] {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let list = pointList(in: json) else { throw DecodeError.badFormat }
        let points = list.compactMap(point(from:))
        guard !points.isEmpty, points.count == list.count else { throw DecodeError.badFormat }
        return yAxis == .north ? points.map { SIMD2($0.x, -$0.y) } : points
    }

    /// The same points as JSON, e.g. to log or to send back to a server.
    static func encode(_ points: [SIMD2<Float>], yAxis: YAxis = .modelZ) -> [[String: Float]] {
        points.map { ["x": $0.x, "y": yAxis == .north ? -$0.y : $0.y] }
    }

    private static func pointList(in json: Any) -> [Any]? {
        if let array = json as? [Any] { return array }
        if let object = json as? [String: Any] {
            for key in ["route", "points", "path", "coordinates", "waypoints"] {
                if let value = object[key] { return pointList(in: value) }
            }
        }
        return nil
    }

    private static func point(from value: Any) -> SIMD2<Float>? {
        if let pair = value as? [Any], pair.count >= 2, let x = number(pair[0]), let y = number(pair[1]) {
            return SIMD2(x, y)
        }
        if let object = value as? [String: Any], let x = number(object["x"]), let y = number(object["y"] ?? object["z"]) {
            return SIMD2(x, y)
        }
        return nil
    }

    private static func number(_ value: Any?) -> Float? {
        if let number = value as? NSNumber { return number.floatValue }
        if let text = value as? String { return Float(text) }
        return nil
    }
}

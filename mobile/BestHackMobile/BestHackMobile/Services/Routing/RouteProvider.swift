import Foundation

/// Where the guide is taking you.
nonisolated struct RouteTarget: Sendable {
    let key: String
    let title: String
    /// Where to stand to see the exhibit (floor plan x, z).
    let point: SIMD2<Float>
}

/// Something that can plan a walking route. Swap in your own by changing `RouteProviders.configured()`.
protocol RouteProvider: Sendable {
    /// True for a network service (the guide then starts with a straight line and swaps in the real route).
    var isRemote: Bool { get }
    func route(from start: SIMD2<Float>, to target: RouteTarget) async throws -> [SIMD2<Float>]
}

/// No routing data: straight from you to the exhibit.
nonisolated struct StraightLineRoute: RouteProvider {
    var isRemote: Bool { false }

    func route(from start: SIMD2<Float>, to target: RouteTarget) async throws -> [SIMD2<Float>] {
        [start, target.point]
    }
}

/// Your route service.
///
/// Request: `POST <ROUTE_API_URL>` with JSON
///
///     {"from": {"x": 0.2, "y": 56.0},
///      "to": {"id": "totems", "name": "Totem Poles", "x": -0.6, "y": 22.5}}
///
/// Response: a list of (x, y) points, in any format `RouteDecoder` accepts, e.g.
///
///     {"route": [[0.2, 56.0], [0.0, 40.0], [-0.6, 22.5]]}
///
/// Coordinates: metres, x = east, y = the model's z (south) unless ROUTE_Y_AXIS = "north".
nonisolated struct RouteAPI: RouteProvider {
    let url: URL
    let yAxis: RouteDecoder.YAxis

    var isRemote: Bool { true }

    func route(from start: SIMD2<Float>, to target: RouteTarget) async throws -> [SIMD2<Float>] {
        let flip: Float = yAxis == .north ? -1 : 1
        let body: [String: Any] = [
            "from": ["x": start.x, "y": start.y * flip],
            "to": ["id": target.key, "name": target.title, "x": target.point.x, "y": target.point.y * flip],
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 8

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Route service answered HTTP \(status)."])
        }
        let points = try RouteDecoder.decode(data, yAxis: yAxis)
        print("[Route] \(points.count) points to \(target.key)")
        return points
    }
}

enum RouteProviders {
    /// The route service from Secrets.plist (ROUTE_API_URL), or straight lines when none is set.
    static func configured() -> any RouteProvider {
        if let url = Secrets.routeAPIURL {
            return RouteAPI(url: url, yAxis: RouteDecoder.YAxis(rawValue: Secrets.routeYAxis) ?? .modelZ)
        }
        return StraightLineRoute()
    }
}

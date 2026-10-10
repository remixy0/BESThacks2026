import Foundation

/// Settings read from `Secrets.plist` (the app's ".env" file).
///
/// `Secrets.plist` lives next to this file, is git-ignored, and gets bundled into the app automatically.
/// To set it up on a new machine: copy `Secrets.example.plist` (repo root) to
/// `BestHackMobile/Config/Secrets.plist` and fill in the values. Every key is optional.
nonisolated enum Secrets {
    /// Built-in ElevenLabs key. Used when nobody has pasted their own key in the app.
    static let elevenLabsAPIKey = value(for: "ELEVENLABS_API_KEY")

    /// The museum backend (login, navigation over WebSocket, alarm). Just the server's IP is enough,
    /// e.g. "192.168.1.20" (http and port 8081 are assumed), or a full address like "http://192.168.1.20:8081".
    /// Empty = no server: everything runs on the app's own data. Can also be set in the app
    /// (Settings → Server, beacons and keys), which wins. The older key BACKEND_URL still works.
    static let backendHost: String = {
        let host = value(for: "BACKEND_HOST")
        return host.isEmpty ? value(for: "BACKEND_URL") : host
    }()

    /// Not used any more (routes come from the backend's WebSocket, or the bundled map when it's down).
    /// Kept so old Secrets.plist files still read fine.
    static let routeAPIURL: URL? = {
        let text = value(for: "ROUTE_API_URL")
        return text.isEmpty ? nil : URL(string: text)
    }()

    /// How y values from your services (routes, beacon positions) are meant: "model_z" (default, same as the
    /// info JSON's z: +y = south) or "north" (+y = north).
    static let routeYAxis = value(for: "ROUTE_Y_AXIS")

    /// The calibration spot as "x, y, facingDegrees" (museum metres; facing 0 = north, 90 = west).
    /// Empty = just inside the South Entrance, facing into the hall.
    static let calibrationPoint = value(for: "CALIBRATION_POINT")

    static func value(for key: String) -> String {
        guard let plist else { return "" }
        guard let value = plist[key] as? String else { return "" }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Read once.
    private static let plist: [String: Any]? = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }()
}

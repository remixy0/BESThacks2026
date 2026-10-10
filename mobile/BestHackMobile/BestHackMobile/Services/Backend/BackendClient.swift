import Foundation

/// The team's backend: logging in, and the list of BLE beacons with their positions.
///
///     POST <base>/auth/login   {"email": "...", "password": "..."}  →  {"token": "..."}   (any 2xx = logged in)
///     GET  <base>/beacons      (Authorization: Bearer <token>)       →  see BeaconDirectory
///
/// If the server answers 404 the next usual path is tried (login: /login, /api/login, /api/auth/login;
/// beacons: /api/beacons), so the app works with most simple backends without changes.
nonisolated struct BackendClient: Sendable {
    let baseURL: URL
    var token: String?

    enum BackendError: LocalizedError {
        case unauthorized
        case http(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized: trNow("The server didn't accept the login.", "Serwer nie przyjął logowania.")
            case .http(let status): trNow("The server answered with error \(status).", "Serwer zwrócił błąd \(status).")
            case .badResponse: trNow("The server's answer didn't make sense.", "Odpowiedź serwera jest nieczytelna.")
            }
        }
    }

    struct LoginResult: Sendable {
        let token: String?
        let name: String?
    }

    static let loginPaths = ["auth/login", "login", "api/login", "api/auth/login"]
    static let beaconPaths = ["beacons", "api/beacons"]

    /// "192.168.1.20:8000" → "http://192.168.1.20:8000". Nil when empty or not a URL.
    static func url(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "http://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), url.host() != nil else { return nil }
        return url
    }

    @concurrent
    func login(email: String, password: String, timeout: TimeInterval = 8) async throws -> LoginResult {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await send(paths: Self.loginPaths, method: "POST", body: body, timeout: timeout)
        let json = try? JSONSerialization.jsonObject(with: data)
        return LoginResult(token: Self.find(["token", "access_token", "accessToken", "jwt", "session"], in: json),
                           name: Self.find(["name", "username", "display_name", "displayName"], in: json))
    }

    @concurrent
    func beacons() async throws -> BeaconDirectory {
        let data = try await send(paths: Self.beaconPaths, method: "GET", body: nil, timeout: 8)
        return try BeaconDirectory.decode(data)
    }

    /// Tries each path in turn, moving on only when the server says the path doesn't exist.
    private func send(paths: [String], method: String, body: Data?, timeout: TimeInterval) async throws -> Data {
        var lastError: Error = BackendError.badResponse
        for path in paths {
            var request = URLRequest(url: baseURL.appending(path: path))
            request.httpMethod = method
            request.timeoutInterval = timeout
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if let token, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.badResponse }
            switch http.statusCode {
            case 200..<300:
                return data
            case 401, 403:
                throw BackendError.unauthorized
            case 404, 405:
                lastError = BackendError.http(http.statusCode)
                continue
            default:
                throw BackendError.http(http.statusCode)
            }
        }
        throw lastError
    }

    /// The first string under any of `keys`, at the top level or one level down (e.g. {"data": {"token": …}}).
    private static func find(_ keys: [String], in json: Any?) -> String? {
        guard let object = json as? [String: Any] else { return nil }
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let found = find(keys, in: nested) { return found }
        }
        return nil
    }
}

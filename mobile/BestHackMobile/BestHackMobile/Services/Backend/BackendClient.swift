import Foundation

/// The museum backend's HTTP side (contract: the backend team's INTEGRATION.md).
///
/// - **Login is a server session, not a token:** `GET /api/auth/csrf` (gives a CSRF token + the `JSESSIONID`
///   cookie) → `POST /api/auth/login` with that cookie and the token in the header it names (`X-CSRF-TOKEN`).
///   Logging in changes the session id; `URLSession.shared` keeps the cookies in `HTTPCookieStorage.shared`
///   and sends them with every request, and `webSocketRequest()` copies them onto the WebSocket handshake.
/// - **Navigation** runs over the `/ws/position` WebSocket (`PositionSocket`).
/// - **Coordinates:** metres, map x = model X, map y = model Z, i.e. exactly the app's floor point.
/// - **Host:** BACKEND_HOST in Secrets.plist, or typed in Settings. A bare IP is enough ("192.168.1.20"):
///   http and port 8081 are assumed. The same host serves HTTP and the WebSocket.
nonisolated struct BackendClient: Sendable {
    let baseURL: URL

    /// The backend's port when none is given.
    static let defaultPort = 8081

    enum BackendError: LocalizedError {
        /// 401: wrong email or password, or no (more) session.
        case unauthorized
        /// 403: CSRF token missing or from another session, or not allowed.
        case forbidden
        /// 400: the server didn't accept the data (its explanation, if any).
        case invalid(String)
        /// 409: e.g. an account with this email already exists.
        case conflict
        case http(Int)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .unauthorized: trNow("The server didn't accept the login.", "Serwer nie przyjął logowania.")
            case .forbidden: trNow("The server refused the request (403).", "Serwer odrzucił żądanie (403).")
            case .invalid(let detail): detail.isEmpty ? trNow("The server didn't accept the data.", "Serwer nie przyjął danych.") : detail
            case .conflict: trNow("An account with this email already exists.", "Konto z tym adresem e-mail już istnieje.")
            case .http(let status): trNow("The server answered with error \(status).", "Serwer zwrócił błąd \(status).")
            case .badResponse: trNow("The server's answer didn't make sense.", "Odpowiedź serwera jest nieczytelna.")
            }
        }
    }

    /// `{"id": 1, "email": "user@example.com", "role": "USER"}`
    struct Account: Decodable, Sendable {
        let id: Int?
        let email: String
        let role: String?
    }

    /// True when the problem is the server (unreachable, down, broken answers), not what you typed:
    /// the app then carries on with its local data (the failsafe).
    static func isServerProblem(_ error: any Error) -> Bool {
        if error is URLError || error is DecodingError { return true }
        guard let error = error as? BackendError else { return true }
        switch error {
        case .unauthorized, .invalid, .conflict: return false
        case .forbidden, .badResponse: return true
        case .http: return true
        }
    }

    /// "192.168.1.20" → "http://192.168.1.20:8081"; "https://museum.example" stays as it is. Nil when empty.
    static func url(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") { trimmed = "http://" + trimmed }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard var components = URLComponents(string: trimmed), let host = components.host, !host.isEmpty else { return nil }
        if components.port == nil, components.scheme == "http" { components.port = defaultPort }
        return components.url
    }

    // MARK: - Account

    /// Logs in: fresh CSRF token for this session, then the login itself. The session cookie is kept for later.
    @concurrent
    func login(email: String, password: String, timeout: TimeInterval = 8) async throws -> Account {
        let csrf = try await csrfToken(timeout: timeout)
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await send("api/auth/login", method: "POST", body: body, headers: [csrf.header: csrf.token], timeout: timeout)
        return try JSONDecoder().decode(Account.self, from: data)
    }

    /// Creates an account (always a USER). Doesn't log in.
    @concurrent
    func register(email: String, password: String) async throws -> Account {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await send("api/auth/register", method: "POST", body: body, headers: [:], timeout: 8)
        return try JSONDecoder().decode(Account.self, from: data)
    }

    /// Who the current session belongs to (401 = not logged in any more).
    @concurrent
    func me(timeout: TimeInterval = 6) async throws -> Account {
        let data = try await send("api/auth/me", method: "GET", body: nil, headers: [:], timeout: timeout)
        return try JSONDecoder().decode(Account.self, from: data)
    }

    /// Ends the session on the server (needs a fresh CSRF token). Errors don't matter here.
    @concurrent
    func logout() async {
        guard let csrf = try? await csrfToken(timeout: 5) else { return }
        _ = try? await send("api/auth/logout", method: "POST", body: nil, headers: [csrf.header: csrf.token], timeout: 5)
    }

    /// Forgets this server's cookies (after logging out).
    func clearCookies() {
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies(for: baseURL) ?? [] {
            storage.deleteCookie(cookie)
        }
    }

    private func csrfToken(timeout: TimeInterval) async throws -> (header: String, token: String) {
        struct Answer: Decodable {
            let headerName: String?
            let token: String
        }
        let data = try await send("api/auth/csrf", method: "GET", body: nil, headers: [:], timeout: timeout)
        let answer = try JSONDecoder().decode(Answer.self, from: data)
        return (answer.headerName ?? "X-CSRF-TOKEN", answer.token)
    }

    // MARK: - Beacons (not part of the current contract: used if the server has it, else the saved list)

    @concurrent
    func beacons() async throws -> BeaconDirectory {
        var lastError: any Error = BackendError.http(404)
        for path in ["api/beacons", "beacons"] {
            do {
                let data = try await send(path, method: "GET", body: nil, headers: [:], timeout: 8)
                return try BeaconDirectory.decode(data)
            } catch BackendError.http(let status) where status == 404 || status == 405 {
                lastError = BackendError.http(status)
            }
        }
        throw lastError
    }

    // MARK: - WebSocket

    /// `ws://<host>/ws/position` (`wss://` for an https server), carrying the session cookie.
    func webSocketRequest(path: String = "ws/position") -> URLRequest? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        let base = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = base + "/" + path
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        // The cookie is added by hand (the WebSocket doesn't reliably share the HTTP cookie jar).
        request.httpShouldHandleCookies = false
        let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) ?? []
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    // MARK: - HTTP

    private func send(_ path: String, method: String, body: Data?, headers: [String: String],
                      timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.badResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 400: throw BackendError.invalid(Self.detail(in: data))
        case 401: throw BackendError.unauthorized
        case 403: throw BackendError.forbidden
        case 409: throw BackendError.conflict
        default:
            print("[Backend] \(method) /\(path) → HTTP \(http.statusCode)")
            throw BackendError.http(http.statusCode)
        }
    }

    /// The `detail` of a ProblemDetail answer, if there is one.
    private static func detail(in data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        return (json["detail"] as? String) ?? (json["title"] as? String) ?? ""
    }
}

import Foundation
import Observation

/// Who's signed in, and the session with the museum backend.
///
/// - **Log in:** email + password → the backend's session login (CSRF + cookie, see `BackendClient`).
/// - **Create account:** registers on the backend, then logs in.
/// - **Failsafe:** when the server can't be reached or answers with errors (not "wrong password"), you're still let in,
///   on the phone's own data (`Account.isLocal`). The email and password are kept in the Keychain, so the app logs in
///   to the server by itself once it's back, and again whenever the server's session runs out (30 min idle, restart).
/// - **Demo:** test@test.test / test. Tries the server too, carries on without it.
@Observable
final class AccountStore {
    nonisolated struct Account: Codable, Equatable, Sendable {
        var email: String
        var isDemo: Bool
        var name: String?
        /// "USER" or "ADMIN", from the server.
        var role: String?
        /// Signed in on the phone only (the server wasn't reachable): guidance uses local data.
        var isLocal: Bool?
    }

    static let demoEmail = "test@test.test"
    static let demoPassword = "test"

    private(set) var account: Account?
    private(set) var isWorking = false
    /// Something to tell you after signing in (e.g. "the server isn't answering, working locally").
    private(set) var notice: String?
    /// The server has accepted our login in this run of the app (the cookie is good, as far as we know).
    private(set) var hasServerSession = false

    /// The server typed in the app; empty = BACKEND_HOST from Secrets.plist.
    var serverOverride: String {
        didSet {
            UserDefaults.standard.set(serverOverride, forKey: Keys.server)
            hasServerSession = false
            credentialsRejected = false
        }
    }

    /// The server said no to the saved password: stop trying until you sign in again.
    @ObservationIgnored private var credentialsRejected = false

    private enum Keys {
        static let account = "account.current"
        static let server = "backend.url"
    }

    private static let keychain = (service: "Backend", account: "login")

    init() {
        serverOverride = UserDefaults.standard.string(forKey: Keys.server) ?? ""
        if let data = UserDefaults.standard.data(forKey: Keys.account) {
            account = try? JSONDecoder().decode(Account.self, from: data)
        }
    }

    var isSignedIn: Bool { account != nil }

    /// The server in use, as typed (for display).
    var serverText: String {
        let typed = serverOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? Secrets.backendHost : typed
    }

    var serverURL: URL? { BackendClient.url(from: serverText) }

    /// A client for the backend. Nil when no server is set.
    var backend: BackendClient? {
        serverURL.map { BackendClient(baseURL: $0) }
    }

    func clearNotice() {
        notice = nil
    }

    // MARK: - Signing in and out

    nonisolated enum LoginError: LocalizedError {
        case noServer
        case wrongCredentials
        case unreachable(String)
        case other(String)

        var errorDescription: String? {
            switch self {
            case .noServer: trNow("No server is set up yet. Put its address in BACKEND_HOST (Secrets.plist) or set it below.",
                                  "Nie ustawiono serwera. Wpisz jego adres w BACKEND_HOST (Secrets.plist) albo ustaw go poniżej.")
            case .wrongCredentials: trNow("That email and password don't match.", "Nieprawidłowy e-mail lub hasło.")
            case .unreachable(let detail): trNow("Can't reach the server (\(detail)).", "Nie można połączyć się z serwerem (\(detail)).")
            case .other(let detail): detail
            }
        }
    }

    /// Logs in. Wrong password → error. Server down or misbehaving → you're in anyway, on local data.
    func signIn(email: String, password: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        notice = nil
        guard let client = backend else {
            saveCredentials(email: email, password: password)
            finish(Account(email: email, isDemo: false, isLocal: true))
            notice = trNow("No server is set, so the app works on its own data.", "Nie ustawiono serwera, więc aplikacja działa na własnych danych.")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let server = try await client.login(email: email, password: password)
            saveCredentials(email: email, password: password)
            hasServerSession = true
            finish(Account(email: server.email, isDemo: false, role: server.role, isLocal: false))
        } catch BackendClient.BackendError.unauthorized {
            throw LoginError.wrongCredentials
        } catch BackendClient.BackendError.invalid(let detail) {
            throw LoginError.other(detail.isEmpty ? trNow("Check the email and password.", "Sprawdź e-mail i hasło.") : detail)
        } catch let error where BackendClient.isServerProblem(error) {
            // Failsafe: let you in on local data; the app logs in to the server by itself when it's back.
            print("[Account] server problem while logging in (\(error.localizedDescription)); continuing on local data")
            saveCredentials(email: email, password: password)
            finish(Account(email: email, isDemo: false, isLocal: true))
            notice = trNow("The server isn't answering (\(error.localizedDescription)). Working on local data; it connects by itself when the server is back.",
                           "Serwer nie odpowiada (\(error.localizedDescription)). Działam na danych lokalnych, połączę się sam, gdy serwer wróci.")
        } catch {
            throw LoginError.other(error.localizedDescription)
        }
    }

    /// Creates an account on the server, then logs in.
    func register(email: String, password: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...72).contains(password.count), password.utf8.count <= 72 else {
            throw LoginError.other(trNow("The password needs 8 to 72 characters.", "Hasło musi mieć od 8 do 72 znaków."))
        }
        guard let client = backend else { throw LoginError.noServer }
        isWorking = true
        do {
            _ = try await client.register(email: email, password: password)
        } catch BackendClient.BackendError.conflict {
            isWorking = false
            throw LoginError.other(trNow("This email already has an account. Log in instead.", "Ten e-mail ma już konto. Zaloguj się."))
        } catch BackendClient.BackendError.invalid(let detail) {
            isWorking = false
            throw LoginError.other(detail.isEmpty ? trNow("Check the email and password.", "Sprawdź e-mail i hasło.") : detail)
        } catch let error as URLError {
            isWorking = false
            throw LoginError.unreachable(error.localizedDescription)
        } catch {
            isWorking = false
            throw LoginError.other(error.localizedDescription)
        }
        isWorking = false
        try await signIn(email: email, password: password)
    }

    /// Signs in as the demo account. Always succeeds; uses the server if it accepts the demo login.
    func signInDemo() async {
        isWorking = true
        defer { isWorking = false }
        notice = nil
        var onServer = false
        if let client = backend {
            do {
                _ = try await client.login(email: Self.demoEmail, password: Self.demoPassword, timeout: 5)
                onServer = true
                hasServerSession = true
            } catch {
                print("[Account] the server didn't take the demo login (\(error.localizedDescription)); demo runs on local data")
            }
        }
        saveCredentials(email: Self.demoEmail, password: Self.demoPassword)
        finish(Account(email: Self.demoEmail, isDemo: true, name: "Demo", isLocal: !onServer))
    }

    func signOut() {
        if let client = backend {
            let hadSession = hasServerSession
            Task {
                if hadSession { await client.logout() }
                client.clearCookies()
            }
        }
        hasServerSession = false
        credentialsRejected = false
        account = nil
        notice = nil
        UserDefaults.standard.removeObject(forKey: Keys.account)
        KeychainStore.save("", service: Self.keychain.service, account: Self.keychain.account)
    }

    // MARK: - Server session (for the WebSocket)

    /// A logged-in server session, logging in again with the saved password when the old one ran out.
    /// `.noServer`: none set. `.unavailable`: can't right now (the app keeps working on local data).
    func socketSession() async -> PositionSocket.SessionResult {
        guard let client = backend else { return .noServer }
        guard account != nil else { return .unavailable(trNow("Not signed in.", "Nie zalogowano.")) }
        if hasServerSession { return .ready(client) }

        // Maybe the cookie we have is still good.
        if (try? await client.me()) != nil {
            hasServerSession = true
            markOnServer()
            return .ready(client)
        }
        guard !credentialsRejected, let saved = savedCredentials() else {
            return .unavailable(trNow("Log in again to use the server.", "Zaloguj się ponownie, żeby korzystać z serwera."))
        }
        do {
            let server = try await client.login(email: saved.email, password: saved.password, timeout: 6)
            hasServerSession = true
            markOnServer(role: server.role)
            return .ready(client)
        } catch BackendClient.BackendError.unauthorized {
            credentialsRejected = true
            return .unavailable(trNow("The server doesn't know this account. Log in again (or create an account) to use it.",
                                      "Serwer nie zna tego konta. Zaloguj się ponownie (albo załóż konto), żeby z niego korzystać."))
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    /// The server ended our session (WebSocket closed for policy, handshake refused): log in again next time.
    func sessionExpired() {
        hasServerSession = false
    }

    private func markOnServer(role: String? = nil) {
        guard var current = account, current.isLocal != false || (role != nil && current.role != role) else { return }
        current.isLocal = false
        if let role { current.role = role }
        finish(current)
    }

    // MARK: - Storage

    private nonisolated struct Credentials: Codable {
        let email: String
        let password: String
    }

    private func saveCredentials(email: String, password: String) {
        credentialsRejected = false
        guard let data = try? JSONEncoder().encode(Credentials(email: email, password: password)),
              let text = String(data: data, encoding: .utf8) else { return }
        KeychainStore.save(text, service: Self.keychain.service, account: Self.keychain.account)
    }

    private func savedCredentials() -> Credentials? {
        let text = KeychainStore.load(service: Self.keychain.service, account: Self.keychain.account)
        guard !text.isEmpty else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: Data(text.utf8))
    }

    private func finish(_ account: Account) {
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: Keys.account)
        }
        self.account = account
    }
}

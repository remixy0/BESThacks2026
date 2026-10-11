import Foundation
import Observation

/// Who's signed in, and which server the app talks to.
///
/// - Log in: email + password → the backend's session login (CSRF token + `JSESSIONID` cookie, see `BackendClient`).
///   The cookie lives in `HTTPCookieStorage.shared`, so later requests carry the session by themselves.
/// - Demo: signs in as test@test.test / test. The login is still sent to the server, but the app continues
///   whatever happens (no answer, an error, no server set at all).
@Observable
final class AccountStore {
    nonisolated struct Account: Codable, Equatable, Sendable {
        var email: String
        var isDemo: Bool
        var name: String?
    }

    static let demoEmail = "test@test.test"
    static let demoPassword = "test"

    private(set) var account: Account?
    private(set) var isWorking = false

    /// The server typed in the app; empty = BACKEND_URL from Secrets.plist, else the built-in 172.20.10.6.
    var serverOverride: String {
        didSet { UserDefaults.standard.set(serverOverride, forKey: Keys.server) }
    }

    private enum Keys {
        static let account = "account.current"
        static let server = "backend.url"
        static let serverDefault = "backend.defaultSeen"
    }

    init() {
        let defaults = UserDefaults.standard
        // When the built-in server address changes, forget an address typed in an older version,
        // so the new one is actually used.
        if defaults.string(forKey: Keys.serverDefault) != Secrets.defaultBackendURL {
            defaults.removeObject(forKey: Keys.server)
            defaults.set(Secrets.defaultBackendURL, forKey: Keys.serverDefault)
        }
        serverOverride = defaults.string(forKey: Keys.server) ?? ""
        if let data = defaults.data(forKey: Keys.account) {
            account = try? JSONDecoder().decode(Account.self, from: data)
        }
        // The old token login is gone (the server uses a session cookie now): drop a saved token.
        KeychainStore.save("", service: KeychainStore.backendToken.service, account: KeychainStore.backendToken.account)
    }

    var isSignedIn: Bool { account != nil }

    /// The server in use, as typed (for display).
    var serverText: String {
        let typed = serverOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? Secrets.backendURL : typed
    }

    /// A bare IP gets http and the backend's port (8081), see `BackendClient.url(from:)`.
    var serverURL: URL? { BackendClient.url(from: serverText) }

    /// A client for the backend. The login session travels in the shared cookie storage. Nil when no server is set.
    var backend: BackendClient? {
        serverURL.map { BackendClient(baseURL: $0) }
    }

    // MARK: - Signing in and out

    nonisolated enum LoginError: LocalizedError {
        case noServer
        case wrongCredentials
        case unreachable(String)
        case other(String)

        var errorDescription: String? {
            switch self {
            case .noServer: trNow("No server is set up yet. Try the demo, or set the server below.",
                                  "Nie ustawiono serwera. Wypróbuj demo albo ustaw serwer poniżej.")
            case .wrongCredentials: trNow("That email and password don't match.", "Nieprawidłowy e-mail lub hasło.")
            case .unreachable(let detail): trNow("Can't reach the server (\(detail)). Check the Wi-Fi, or try the demo.",
                                               "Nie można połączyć się z serwerem (\(detail)). Sprawdź Wi-Fi albo wypróbuj demo.")
            case .other(let detail): detail
            }
        }
    }

    func signIn(email: String, password: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client = backend else { throw LoginError.noServer }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await client.login(email: email, password: password)
            let confirmed = result.email.trimmingCharacters(in: .whitespacesAndNewlines)
            finish(Account(email: confirmed.isEmpty ? email : confirmed, isDemo: false, name: nil))
        } catch BackendClient.BackendError.unauthorized {
            throw LoginError.wrongCredentials
        } catch let error as URLError {
            throw LoginError.unreachable(error.localizedDescription)
        } catch {
            throw LoginError.other(error.localizedDescription)
        }
    }

    /// Signs in as the demo account. Always succeeds; the server is told if it can be reached.
    func signInDemo() async {
        isWorking = true
        defer { isWorking = false }
        if let client = backend {
            do {
                _ = try await client.login(email: Self.demoEmail, password: Self.demoPassword, timeout: 5)
            } catch {
                print("[Account] demo login wasn't confirmed by the server (\(error.localizedDescription)); continuing anyway")
            }
        }
        finish(Account(email: Self.demoEmail, isDemo: true, name: "Demo"))
    }

    func signOut() {
        let client = backend
        account = nil
        UserDefaults.standard.removeObject(forKey: Keys.account)
        // End the server session too (best effort), then forget its cookies.
        if let client {
            Task {
                await client.logout()
                client.clearCookies()
            }
        }
    }

    private func finish(_ account: Account) {
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: Keys.account)
        }
        self.account = account
    }
}

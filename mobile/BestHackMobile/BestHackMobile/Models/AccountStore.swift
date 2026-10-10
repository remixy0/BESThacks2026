import Foundation
import Observation

/// Who's signed in, and which server the app talks to.
///
/// - Log in: email + password, sent to the backend. You're in once the server says yes.
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

    /// The server typed in the app; empty = BACKEND_URL from Secrets.plist.
    var serverOverride: String {
        didSet { UserDefaults.standard.set(serverOverride, forKey: Keys.server) }
    }

    @ObservationIgnored private var token: String

    private enum Keys {
        static let account = "account.current"
        static let server = "backend.url"
    }

    init() {
        serverOverride = UserDefaults.standard.string(forKey: Keys.server) ?? ""
        token = KeychainStore.load(service: KeychainStore.backendToken.service, account: KeychainStore.backendToken.account)
        if let data = UserDefaults.standard.data(forKey: Keys.account) {
            account = try? JSONDecoder().decode(Account.self, from: data)
        }
    }

    var isSignedIn: Bool { account != nil }

    /// The server in use, as typed (for display).
    var serverText: String {
        let typed = serverOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? Secrets.backendURL : typed
    }

    var serverURL: URL? { BackendClient.url(from: serverText) }

    /// A client for the backend, carrying the login token. Nil when no server is set.
    var backend: BackendClient? {
        serverURL.map { BackendClient(baseURL: $0, token: token.isEmpty ? nil : token) }
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
        guard let client = BackendClient.url(from: serverText).map({ BackendClient(baseURL: $0) }) else {
            throw LoginError.noServer
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await client.login(email: email, password: password)
            finish(Account(email: email, isDemo: false, name: result.name), token: result.token)
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
        var token: String?
        if let client = BackendClient.url(from: serverText).map({ BackendClient(baseURL: $0) }) {
            do {
                token = try await client.login(email: Self.demoEmail, password: Self.demoPassword, timeout: 5).token
            } catch {
                print("[Account] demo login wasn't confirmed by the server (\(error.localizedDescription)); continuing anyway")
            }
        }
        finish(Account(email: Self.demoEmail, isDemo: true, name: "Demo"), token: token)
    }

    func signOut() {
        account = nil
        token = ""
        UserDefaults.standard.removeObject(forKey: Keys.account)
        KeychainStore.save("", service: KeychainStore.backendToken.service, account: KeychainStore.backendToken.account)
    }

    private func finish(_ account: Account, token: String?) {
        self.token = token ?? ""
        KeychainStore.save(self.token, service: KeychainStore.backendToken.service, account: KeychainStore.backendToken.account)
        if let data = try? JSONEncoder().encode(account) {
            UserDefaults.standard.set(data, forKey: Keys.account)
        }
        self.account = account
    }
}

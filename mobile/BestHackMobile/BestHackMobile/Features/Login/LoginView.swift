import SwiftUI

/// The first screen: log in (or create an account), or try the demo. The language switch sits at the top.
///
/// Logging in goes to the museum backend. If the server can't be reached or answers with errors, you're let in
/// anyway and the app works on its own data (see `AccountStore`). Demo = test@test.test / test, same failsafe.
struct LoginView: View {
    let account: AccountStore
    var onSignedIn: () -> Void

    private enum Field { case email, password }

    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var showServer = false
    @State private var serverDraft = ""
    /// Creating an account instead of logging in.
    @State private var isRegistering = false
    @FocusState private var focus: Field?

    private var canLogIn: Bool {
        !account.isWorking && email.contains("@") && (isRegistering ? password.count >= 8 : !password.isEmpty)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    LanguageSwitch()
                }
                .padding(.top, 8)

                VStack(spacing: 14) {
                    BloopOrb(size: 76)
                    VStack(spacing: 6) {
                        Text("Spatial Bloop")
                            .font(Theme.title(.largeTitle))
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(tr("An audio guide to the Field Museum", "Przewodnik dźwiękowy po Field Museum"))
                            .font(Theme.body)
                            .foregroundStyle(Theme.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                }

                VStack(spacing: 12) {
                    VStack(spacing: 0) {
                        TextField(tr("Email", "E-mail"), text: $email)
                            .textContentType(.username)
                            #if os(iOS)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                        Divider().padding(.leading, 16)
                        SecureField(isRegistering ? tr("Password (8 or more characters)", "Hasło (co najmniej 8 znaków)") : tr("Password", "Hasło"),
                                    text: $password)
                            .textContentType(isRegistering ? .newPassword : .password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { if canLogIn { logIn() } }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                    }
                    .background(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))

                    if let error {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(Theme.small)
                            .foregroundStyle(Theme.redText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: logIn) {
                        if account.isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text(isRegistering ? tr("Create account", "Załóż konto") : tr("Log in", "Zaloguj się"))
                        }
                    }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .disabled(!canLogIn)

                    Button {
                        isRegistering.toggle()
                        error = nil
                    } label: {
                        Text(isRegistering ? tr("Already have an account? Log in", "Masz już konto? Zaloguj się")
                                           : tr("No account yet? Create one", "Nie masz konta? Załóż je"))
                            .font(Theme.small.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accentText)
                    .disabled(account.isWorking || account.serverURL == nil)
                }

                HStack(spacing: 12) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    Text(tr("or", "lub")).font(Theme.small).foregroundStyle(Theme.inkSoft)
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
                .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Button {
                        Task {
                            await account.signInDemo()
                            onSignedIn()
                        }
                    } label: {
                        Label(tr("Try the demo", "Wypróbuj demo"), systemImage: "play.fill")
                    }
                    .buttonStyle(AppButtonStyle(kind: .secondary))
                    .disabled(account.isWorking)
                    Text(tr("No account needed. You'll be signed in as \(AccountStore.demoEmail).",
                            "Bez konta. Zalogujesz się jako \(AccountStore.demoEmail)."))
                        .font(Theme.small)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                }

                Button {
                    serverDraft = account.serverText
                    showServer = true
                } label: {
                    Label(account.serverURL?.host() ?? tr("Set server", "Ustaw serwer"), systemImage: "server.rack")
                        .font(Theme.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkSoft)
                .accessibilityLabel(account.serverURL == nil ? tr("Set the server", "Ustaw serwer")
                                                             : tr("Server: ", "Serwer: ") + (account.serverURL?.host() ?? ""))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.page.ignoresSafeArea())
        .alert(tr("Server", "Serwer"), isPresented: $showServer) {
            TextField("192.168.1.20", text: $serverDraft)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            Button(tr("Save", "Zapisz")) { account.serverOverride = serverDraft }
            Button(tr("Cancel", "Anuluj"), role: .cancel) {}
        } message: {
            Text(tr("The museum backend: its IP is enough (port 8081 is assumed). Empty = BACKEND_HOST from Secrets.plist.",
                    "Backend muzeum: wystarczy jego IP (domyślnie port 8081). Puste = BACKEND_HOST z Secrets.plist."))
        }
    }

    private func logIn() {
        error = nil
        focus = nil
        Task {
            do {
                if isRegistering {
                    try await account.register(email: email, password: password)
                } else {
                    try await account.signIn(email: email, password: password)
                }
                onSignedIn()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

/// PL | EN, as a small sliding switch.
struct LanguageSwitch: View {
    @State private var language = LanguageSettings.shared

    var body: some View {
        Picker(tr("Language", "Język"), selection: $language.current) {
            ForEach(AppLanguage.allCases) { option in
                Text("\(option.flag) \(option.short)").tag(option)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 150)
        .accessibilityLabel(tr("Language", "Język"))
    }
}

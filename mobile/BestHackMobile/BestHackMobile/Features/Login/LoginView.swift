import SwiftUI

/// The first screen: log in, or try the demo. The language switch sits at the top.
///
/// Demo signs in as test@test.test / test. That login still goes to the server, but the app carries on
/// whether or not the server answers.
struct LoginView: View {
    let account: AccountStore
    var onSignedIn: () -> Void

    private enum Field { case email, password }

    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var showServer = false
    @State private var serverDraft = ""
    @FocusState private var focus: Field?

    private var canLogIn: Bool {
        !account.isWorking && email.contains("@") && !password.isEmpty
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
                        SecureField(tr("Password", "Hasło"), text: $password)
                            .textContentType(.password)
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
                            Text(tr("Log in", "Zaloguj się"))
                        }
                    }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .disabled(!canLogIn)
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
            TextField("http://192.168.1.20:8000", text: $serverDraft)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            Button(tr("Save", "Zapisz")) { account.serverOverride = serverDraft }
            Button(tr("Cancel", "Anuluj"), role: .cancel) {}
        } message: {
            Text(tr("Your team's backend, used for logging in and for the beacon positions.",
                    "Backend Twojego zespołu: logowanie i pozycje beaconów."))
        }
    }

    private func logIn() {
        error = nil
        focus = nil
        Task {
            do {
                try await account.signIn(email: email, password: password)
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
                Text(option.short).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 110)
        .accessibilityLabel(tr("Language", "Język"))
    }
}

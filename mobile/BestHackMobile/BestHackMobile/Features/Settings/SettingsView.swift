import Foundation
import SwiftUI

/// Settings, kept short: language, how you explore, the voice, calibration, and your account up front;
/// the server, beacons and API keys one level down.
struct SettingsView: View {
    @Bindable var guide: GuideModel
    let visits: VisitLog
    let account: AccountStore
    @Binding var mode: UserMode
    var onShowIntro: () -> Void
    var onRecalibrate: () -> Void
    var onLogout: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var confirmLogout = false
    @State private var language = LanguageSettings.shared

    var body: some View {
        NavigationStack {
            Form {
                modeSection
                Section {
                    NavigationLink {
                        VoicePickerView(guide: guide)
                    } label: {
                        SettingsRow(title: tr("Voice", "Głos"), systemImage: "waveform", tint: Theme.coral, value: guide.voice.shortSummary)
                    }
                    speedRow
                    Button(action: onRecalibrate) {
                        SettingsRow(title: tr("Calibrate again", "Skalibruj ponownie"), systemImage: "scope", tint: Theme.accent)
                    }
                } footer: {
                    Text(tr("Calibrate again if the directions feel off, or after your AirPods reconnect.",
                            "Skalibruj ponownie, jeśli kierunki się nie zgadzają albo po ponownym połączeniu AirPodsów."))
                }
                guidanceSection
                wakeSection
                positionSection
                Section {
                    NavigationLink {
                        AdvancedSettingsView(guide: guide, account: account)
                    } label: {
                        SettingsRow(title: tr("Server, beacons and keys", "Serwer, beacony i klucze"), systemImage: "slider.horizontal.3", tint: Theme.inkSoft)
                    }
                }
                languageSection
                accountSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page)
            .navigationTitle(tr("Settings", "Ustawienia"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Done", "Gotowe")) { dismiss() }
                        .font(Theme.bodyBold)
                }
            }
            .confirmationDialog(tr("Forget which exhibits you've visited?", "Zapomnieć odwiedzone eksponaty?"),
                                isPresented: $confirmReset, titleVisibility: .visible) {
                Button(tr("Reset", "Wyczyść"), role: .destructive) { visits.reset() }
            }
            .confirmationDialog(tr("Log out?", "Wylogować?"), isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(tr("Log out", "Wyloguj"), role: .destructive, action: onLogout)
            }
        }
    }

    // MARK: - Sections

    /// The two ways to explore, as two big cards side by side.
    private var modeSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                ForEach([UserMode.standard, UserMode.blind]) { option in
                    ModeCard(mode: option, isSelected: mode == option) {
                        withAnimation(.easeOut(duration: 0.15)) { mode = option }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } header: {
            Text(tr("How you explore", "Jak zwiedzasz"))
        }
    }

    /// How fast the narrator speaks. Letting go plays a short sample at the new speed.
    private var speedRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: tr("Narrator speed", "Tempo lektora"), systemImage: "speedometer", tint: Theme.coral,
                        value: VoiceSettings.speedName(guide.voice.speed))
            HStack(spacing: 10) {
                Image(systemName: "tortoise.fill")
                    .foregroundStyle(Theme.inkSoft)
                    .accessibilityHidden(true)
                Slider(value: Bindable(guide.voice).speed, in: 0.7...1.2, step: 0.02,
                       onEditingChanged: { editing in
                           if !editing { guide.previewSpeed() }
                       })
                    .tint(Theme.coral)
                    .accessibilityLabel(tr("Narrator speed", "Tempo lektora"))
                    .accessibilityValue(VoiceSettings.speedName(guide.voice.speed))
                Image(systemName: "hare.fill")
                    .foregroundStyle(Theme.inkSoft)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
    }

    /// The app's language, with its flag.
    private var languageSection: some View {
        Section {
            Picker(selection: $language.current) {
                ForEach(AppLanguage.allCases) { option in
                    Text("\(option.flag)  \(option.title)").tag(option)
                }
            } label: {
                SettingsRow(title: tr("Language", "Język"), systemImage: "globe", tint: Theme.accent)
            }
            .pickerStyle(.menu)
        }
    }

    /// The backend connection, in a few words.
    private var serverStatus: (text: String, tint: Color) {
        switch guide.server.state {
        case .online: (text: tr("Connected", "Połączono"), tint: Theme.mint)
        case .connecting: (text: tr("Connecting…", "Łączę…"), tint: Theme.amber)
        case .noServer: (text: tr("None, local data", "Brak, dane lokalne"), tint: Theme.inkSoft)
        case .offline: (text: tr("Local data (server unavailable)", "Dane lokalne (serwer niedostępny)"), tint: Theme.amber)
        case .off: (text: tr("Paused", "Wstrzymane"), tint: Theme.inkSoft)
        }
    }

    private var guidanceSection: some View {
        @Bindable var audio = guide.audio
        return Section {
            if mode == .standard {
                Toggle(isOn: $guide.autoAnnounce) {
                    SettingsRow(title: tr("Read nearby exhibits aloud", "Czytaj na głos pobliskie eksponaty"), systemImage: "speaker.wave.2.fill", tint: Theme.accent)
                }
                Toggle(isOn: $guide.selectByLooking) {
                    SettingsRow(title: tr("Choose an exhibit by facing it", "Wybieraj eksponat patrząc na niego"), systemImage: "eye.fill", tint: Theme.accent)
                }
            }
            Toggle(isOn: $guide.listenOnArrival) {
                SettingsRow(title: tr("Listen for my voice when asked", "Słuchaj mojego głosu, gdy pytasz"), systemImage: "mic.fill", tint: Theme.coral)
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(title: tr("Bloop rhythm", "Rytm dźwięków"), systemImage: "metronome.fill", tint: Theme.coral)
                Picker(tr("Bloop rhythm", "Rytm dźwięków"), selection: $audio.bloopStyle) {
                    ForEach(BloopStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(audio.bloopStyle.detail)
                    .font(Theme.small)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: audio.bloopStyle) { _, _ in guide.previewBloopStyle() }
            VStack(alignment: .leading, spacing: 6) {
                SettingsRow(title: tr("Bloop volume", "Głośność dźwięków"), systemImage: "dot.radiowaves.left.and.right", tint: Theme.coral)
                Slider(value: $audio.bloopVolume, in: 0...1)
                    .tint(Theme.coral)
            }
        } header: {
            Text(tr("Guide", "Przewodnik"))
        }
    }

    private var wakeSection: some View {
        @Bindable var wake = guide.wakeWord
        return Section {
            Toggle(isOn: $wake.isEnabled) {
                SettingsRow(title: tr("Wake phrase", "Wywołuj hasłem"), systemImage: "waveform.badge.mic", tint: Theme.coral)
            }
            if wake.isEnabled {
                LabeledContent {
                    TextField(WakeWordListener.defaultPhrase, text: $wake.phrase)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                } label: {
                    Text(tr("Phrase", "Hasło"))
                }
                LabeledContent(tr("Status", "Stan")) {
                    Text(wake.statusText)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text(tr("Talk without touching", "Mów bez dotykania"))
        } footer: {
            Text(tr("Say the phrase (for example \u{201C}\(wake.effectivePhrase)\u{201D}) and then your command, like \u{201C}tell me\u{201D} or an exhibit's name. While this is on, the microphone stays on, which uses some battery. Two or three words work best.",
                    "Powiedz hasło (np. „\(wake.effectivePhrase)”), a potem polecenie, np. „opowiedz” albo nazwę eksponatu. Gdy to jest włączone, mikrofon cały czas słucha, co zużywa trochę baterii. Najlepiej działają dwa–trzy słowa."))
        }
    }

    private var positionSection: some View {
        Section {
            LabeledContent {
                Text(guide.positioning.statusText)
                    .multilineTextAlignment(.trailing)
            } label: {
                SettingsRow(title: tr("Position", "Pozycja"), systemImage: "location", tint: guide.positioning.isHealthy ? Theme.mint : Theme.amber)
            }
            Toggle(isOn: $guide.demoWalk) {
                SettingsRow(title: tr("Demo: walk routes by itself", "Demo: sam przechodź trasę"), systemImage: "figure.walk.motion", tint: Theme.inkSoft)
            }
        } header: {
            Text(tr("Position", "Pozycja"))
        } footer: {
            Text(tr("For showing the app without walking: when you start guidance, the guide moves you along the route.",
                    "Do pokazów bez chodzenia: po rozpoczęciu prowadzenia przewodnik sam przesuwa Cię po trasie."))
        }
    }

    private var accountSection: some View {
        Section {
            if let current = account.account {
                LabeledContent(tr("Signed in as", "Zalogowano jako"), value: current.isDemo ? "\(current.email) (demo)" : current.email)
            }
            LabeledContent {
                Text(serverStatus.text)
                    .multilineTextAlignment(.trailing)
            } label: {
                SettingsRow(title: tr("Server", "Serwer"), systemImage: "server.rack", tint: serverStatus.tint)
            }
            Button(action: onShowIntro) {
                SettingsRow(title: tr("Back to the welcome screen", "Wróć do ekranu powitalnego"), systemImage: "house", tint: Theme.accent)
            }
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                SettingsRow(title: tr("Reset visited exhibits", "Wyczyść odwiedzone eksponaty"), systemImage: "arrow.counterclockwise", tint: Theme.red)
            }
            .disabled(visits.visited.isEmpty)
            Button(role: .destructive) {
                confirmLogout = true
            } label: {
                SettingsRow(title: tr("Log out", "Wyloguj"), systemImage: "rectangle.portrait.and.arrow.right", tint: Theme.red)
            }
        } header: {
            Text(tr("Account", "Konto"))
        }
    }
}

// MARK: - Voice

/// Pick the voice: Apple (offline) or one of the ElevenLabs voices, each with a play button to hear it first.
struct VoicePickerView: View {
    @Bindable var guide: GuideModel
    @State private var customID = ""
    @State private var savedUsage = SpeechCache.Usage()
    @State private var savedStories: (saved: Int, total: Int)?

    var body: some View {
        let voice = guide.voice
        Form {
            Section {
                Picker(tr("Voice", "Głos"), selection: Bindable(voice).engine) {
                    ForEach(VoiceSettings.Engine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(voiceStatus)
            }

            if voice.engine == .elevenLabs, voice.hasAPIKey {
                Section {
                    if voice.isLoadingVoices {
                        HStack {
                            ProgressView()
                            Text(tr("Loading your voices…", "Wczytuję Twoje głosy…")).foregroundStyle(Theme.inkSoft)
                        }
                    }
                    ForEach(voice.availableVoices) { item in
                        VoiceRow(voice: item, isSelected: item.voiceID == voice.voiceID) {
                            voice.pick(voiceID: item.voiceID)
                        } onPlay: {
                            guide.previewVoice(id: item.voiceID, name: item.name)
                        }
                    }
                } header: {
                    Text(tr("ElevenLabs voices", "Głosy ElevenLabs"))
                } footer: {
                    if voice.preferredVoiceMissing {
                        Text(tr("\(VoiceSettings.preferredVoiceName) isn't among your ElevenLabs voices. Add it to My Voices on elevenlabs.io (Voice Library), or paste its voice ID below.",
                                "Głosu \(VoiceSettings.preferredVoiceName) nie ma wśród Twoich głosów ElevenLabs. Dodaj go do „My Voices” na elevenlabs.io (Voice Library) albo wklej jego ID poniżej."))
                    }
                }

                Section {
                    Picker(tr("Quality", "Jakość"), selection: Bindable(voice).model) {
                        ForEach(ElevenLabsTTS.Model.allCases) { model in
                            Text(model.title).tag(model)
                        }
                    }
                } footer: {
                    Text(tr("Lifelike sounds best. Fast starts speaking sooner.", "„Lifelike” brzmi najlepiej. „Fast” zaczyna mówić szybciej."))
                }

                savedSpeechSection

                Section {
                    TextField(tr("Voice ID from the ElevenLabs Voice Library", "ID głosu z biblioteki ElevenLabs"), text: $customID)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    Button(tr("Use this voice", "Użyj tego głosu")) {
                        voice.pick(voiceID: customID.trimmingCharacters(in: .whitespacesAndNewlines))
                        customID = ""
                    }
                    .disabled(customID.trimmingCharacters(in: .whitespacesAndNewlines).count < 10)
                } header: {
                    Text(tr("Another voice", "Inny głos"))
                }
            }

            Section {
                Button(tr("Try the voice", "Wypróbuj głos")) {
                    guide.announceLocation()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .navigationTitle(tr("Voice", "Głos"))
        .task(id: guide.voice.effectiveKey) {
            if guide.voice.engine == .elevenLabs, !guide.voice.isKeyVerified {
                await guide.voice.loadVoices()
            }
        }
        .onChange(of: guide.voice.engine) { _, engine in
            if engine == .elevenLabs, !guide.voice.isKeyVerified {
                Task { await guide.voice.loadVoices() }
            }
        }
        .task(id: savedSpeechKey) { refreshSavedSpeech() }
    }

    // MARK: - Saved speech (ElevenLabs cache)

    private var savedSpeechSection: some View {
        let download = guide.storyDownload
        let running = download?.isRunning == true
        let allSaved = savedStories.map { $0.saved == $0.total } ?? false
        return Section {
            LabeledContent(tr("Saved sentences", "Zapisane zdania"),
                           value: "\(savedUsage.clips) · " + ByteCountFormatter.string(fromByteCount: savedUsage.bytes, countStyle: .file))
            Button {
                guide.downloadStories()
            } label: {
                HStack(spacing: 10) {
                    Label {
                        Text(downloadTitle(running: running, allSaved: allSaved))
                    } icon: {
                        Image(systemName: allSaved ? "checkmark.circle.fill" : "arrow.down.circle")
                            .foregroundStyle(allSaved ? Theme.mintText : Theme.accent)
                    }
                    Spacer(minLength: 0)
                    if running { ProgressView() }
                }
            }
            .disabled(running || allSaved || savedStories == nil)
            Button(tr("Delete saved speech", "Usuń zapisane nagrania"), role: .destructive) {
                SpeechCache.shared.removeAll()
                refreshSavedSpeech()
            }
            .disabled(savedUsage.clips == 0 || running)
        } header: {
            Text(tr("Saved speech", "Zapamiętane nagrania"))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let error = download?.error {
                    Text(error).foregroundStyle(Theme.redText)
                }
                Text(tr("Each sentence is sent to ElevenLabs only once, then played from the phone, even without internet. Changing the voice, quality or speed records sentences again.",
                        "Każde zdanie trafia do ElevenLabs tylko raz, potem gra z telefonu, także bez internetu. Po zmianie głosu, jakości albo tempa zdania nagrywają się od nowa."))
            }
        }
    }

    private func downloadTitle(running: Bool, allSaved: Bool) -> String {
        if running, let download = guide.storyDownload {
            return tr("Downloading stories… \(download.done)/\(download.total)", "Pobieram opowieści… \(download.done)/\(download.total)")
        }
        if allSaved { return tr("All exhibit stories are on the phone", "Wszystkie opowieści są w telefonie") }
        if let stories = savedStories {
            let missing = stories.total - stories.saved
            return tr("Download exhibit stories now (\(missing))", "Pobierz opowieści teraz (\(missing))")
        }
        return tr("Download exhibit stories now", "Pobierz opowieści teraz")
    }

    /// Refreshes the numbers when a download moves on or the voice changes.
    private var savedSpeechKey: String {
        let download = guide.storyDownload
        return "\(download?.done ?? -1)|\(download?.isRunning ?? false)|\(guide.voice.voiceID)|\(guide.voice.model.rawValue)|\(guide.voice.speed)|\(guide.voice.engine)"
    }

    private func refreshSavedSpeech() {
        savedUsage = SpeechCache.shared.usage()
        savedStories = guide.savedStoryCount()
    }

    private var voiceStatus: String {
        let voice = guide.voice
        if voice.engine == .apple { return tr("The built-in Apple voice works offline.", "Wbudowany głos Apple działa bez internetu.") }
        if !voice.hasAPIKey { return tr("Add an ElevenLabs API key in Settings › Server, beacons and keys.", "Dodaj klucz API ElevenLabs w Ustawieniach › Serwer, beacony i klucze.") }
        if voice.isLoadingVoices { return tr("Checking your ElevenLabs key…", "Sprawdzam klucz ElevenLabs…") }
        if let error = voice.voicesError { return error }
        if let note = voice.voicesNote { return note }
        return tr("Tap a voice to use it, or ▶︎ to hear it first. If ElevenLabs fails, the Apple voice takes over.",
                  "Stuknij głos, żeby go wybrać, albo ▶︎, żeby posłuchać. Gdy ElevenLabs zawiedzie, odezwie się głos Apple.")
    }
}

private struct VoiceRow: View {
    let voice: ElevenLabsTTS.Voice
    var isSelected: Bool
    var onSelect: () -> Void
    var onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.lineStrong)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name)
                            .font(Theme.body)
                            .foregroundStyle(Theme.ink)
                        if !voice.details.isEmpty {
                            Text(voice.details)
                                .font(Theme.small)
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Button(action: onPlay) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.coral)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("Hear \(voice.name)", "Posłuchaj: \(voice.name)"))
        }
    }
}

// MARK: - Advanced

/// Server, beacons, routes, the ElevenLabs key, and credits.
struct AdvancedSettingsView: View {
    @Bindable var guide: GuideModel
    let account: AccountStore
    @State private var keyDraft = ""
    @State private var serverDraft = ""

    var body: some View {
        Form {
            serverSection
            beaconSection
            apiKeySection
            routeSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .navigationTitle(tr("Server, beacons and keys", "Serwer, beacony i klucze"))
        .onAppear { serverDraft = account.serverOverride }
    }

    // MARK: Server

    private var serverSection: some View {
        Section {
            TextField(Secrets.backendHost.isEmpty ? "192.168.1.20" : Secrets.backendHost, text: $serverDraft)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .onSubmit(saveServer)
            Button(tr("Save and connect", "Zapisz i połącz"), action: saveServer)
            LabeledContent(tr("Connection", "Połączenie")) {
                Text(connectionText)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text(tr("Server", "Serwer"))
        } footer: {
            Text(tr("The museum backend (login, guidance, alarm). Its IP is enough; port 8081 is assumed. Empty = BACKEND_HOST from Secrets.plist. Now: ",
                    "Backend muzeum (logowanie, prowadzenie, alarm). Wystarczy IP, domyślnie port 8081. Puste = BACKEND_HOST z Secrets.plist. Teraz: ")
                 + (account.serverURL?.absoluteString ?? tr("not set", "nie ustawiono")) + ".")
        }
    }

    private var connectionText: String {
        let server = guide.server
        switch server.state {
        case .online: return tr("Connected", "Połączono")
        case .connecting: return tr("Connecting…", "Łączę…")
        case .noServer: return tr("No server: local data", "Brak serwera: dane lokalne")
        case .off: return tr("Paused", "Wstrzymane")
        case .offline: return tr("Local data. ", "Dane lokalne. ") + (server.problem ?? "")
        }
    }

    private func saveServer() {
        account.serverOverride = serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guide.server.reconnect()
        Task { await guide.positioning.loadDirectory(using: account.backend) }
    }

    // MARK: Beacons

    private var beaconSection: some View {
        Section {
            LabeledContent(tr("Now", "Teraz"), value: guide.positioning.statusText)
            LabeledContent(tr("Known beacons", "Znane beacony"), value: "\(guide.positioning.directory.beacons.count)")
            NavigationLink(tr("What the phone hears", "Co słyszy telefon")) {
                BeaconsView(positioning: guide.positioning)
            }
            Button(guide.positioning.isLoadingDirectory ? tr("Loading…", "Wczytuję…") : tr("Reload beacon positions", "Wczytaj pozycje beaconów")) {
                Task { await guide.positioning.loadDirectory(using: account.backend) }
            }
            .disabled(guide.positioning.isLoadingDirectory)
            if let error = guide.positioning.directoryError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.redText)
            }
        } header: {
            Text(tr("Beacons", "Beacony"))
        } footer: {
            Text("UUID \(BeaconScanner.uuid.uuidString). " + tr("Calibration spot", "Punkt kalibracji")
                 + ": x \(Int(guide.positioning.spot.point.x)), y \(Int(guide.positioning.spot.point.y)), \(Int(guide.positioning.spot.facingDegrees))°.")
        }
    }

    // MARK: ElevenLabs key

    private var trimmedDraft: String {
        keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveKey() {
        guard !trimmedDraft.isEmpty else { return }
        guide.voice.apiKey = trimmedDraft
        guide.voice.engine = .elevenLabs
        keyDraft = ""
    }

    private var apiKeySection: some View {
        Section {
            if guide.voice.hasOwnKey {
                LabeledContent(tr("In use", "W użyciu"), value: tr("Your key ••••", "Twój klucz ••••") + guide.voice.apiKey.suffix(4))
                Button(guide.voice.builtInKey.isEmpty ? tr("Remove key", "Usuń klucz") : tr("Remove and use Secrets.plist key", "Usuń i użyj klucza z Secrets.plist"),
                       role: .destructive) {
                    guide.voice.apiKey = ""
                }
            } else if guide.voice.usesBuiltInKey {
                LabeledContent(tr("In use", "W użyciu"), value: "Secrets.plist ••••" + guide.voice.builtInKey.suffix(4))
            }
            SecureField(guide.voice.hasAPIKey ? tr("Paste a different key", "Wklej inny klucz") : tr("Paste your ElevenLabs API key", "Wklej klucz API ElevenLabs"),
                        text: $keyDraft)
                .textContentType(.password)
                .autocorrectionDisabled()
                .onSubmit(saveKey)
            Button(tr("Save key", "Zapisz klucz"), action: saveKey)
                .disabled(trimmedDraft.isEmpty)
            if guide.voice.hasAPIKey {
                Button(tr("Check connection", "Sprawdź połączenie")) {
                    Task { await guide.voice.recheck() }
                }
                .disabled(guide.voice.isLoadingVoices)
            }
        } header: {
            Text(tr("ElevenLabs API key", "Klucz API ElevenLabs"))
        } footer: {
            Text(tr("A key pasted here wins over Secrets.plist and is stored in this device's Keychain. It needs Text to Speech, Speech to Text and Voices (Read) access.",
                    "Klucz wklejony tutaj ma pierwszeństwo przed Secrets.plist i jest zapisany w pęku kluczy urządzenia. Potrzebuje uprawnień Text to Speech, Speech to Text i Voices (Read)."))
        }
    }

    // MARK: Routes

    private var routeSection: some View {
        Section {
            LabeledContent(tr("Guidance now", "Prowadzenie teraz"),
                           value: guide.routeSource == .server ? tr("From the server", "Z serwera") : tr("From the map on the phone", "Z mapy w telefonie"))
            LabeledContent(tr("Map on the phone", "Mapa w telefonie"),
                           value: MuseumGrid.shared != nil ? tr("Ready", "Gotowa") : tr("Missing", "Brak pliku"))
        } header: {
            Text(tr("Routes", "Trasy"))
        } footer: {
            Text(tr("Routes come from the server step by step (it knows about closed areas and the alarm). If it's down or answers with errors, the phone plans the route itself on its copy of the same map, avoiding the closed areas it last heard about.",
                    "Trasy przychodzą z serwera krok po kroku (zna zamknięte strefy i alarm). Gdy serwer nie działa albo zwraca błędy, telefon sam wyznacza trasę na swojej kopii tej samej mapy, omijając ostatnio znane zamknięte strefy."))
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            Text(tr("Floor-plan data © 2020 Field Museum of Natural History, CC BY 4.0. The building and exhibit models are simplified reconstructions, not scans.",
                    "Dane planu piętra © 2020 Field Museum of Natural History, CC BY 4.0. Modele budynku i eksponatów to uproszczone rekonstrukcje, nie skany."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text(tr("About", "O aplikacji"))
        }
    }
}

/// Every beacon the phone hears right now: signal, estimated distance, how long ago. Refreshes every second.
struct BeaconsView: View {
    let positioning: PositionService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let sightings = positioning.sightings()
            List {
                Section {
                    LabeledContent(tr("Position", "Pozycja"), value: positioning.statusText)
                    LabeledContent("x, y", value: String(format: "%.1f, %.1f", positioning.position.x, positioning.position.y))
                    Stepper(value: Binding(get: { Double(positioning.pathLossExponent) },
                                           set: { positioning.pathLossExponent = Float($0) }),
                            in: 1.6...4, step: 0.1) {
                        LabeledContent(tr("Signal fade (n)", "Zanik sygnału (n)"), value: String(format: "%.1f", positioning.pathLossExponent))
                    }
                }
                Section(tr("Heard", "Słyszane")) {
                    if sightings.isEmpty {
                        Text(tr("Nothing yet", "Na razie nic")).foregroundStyle(.secondary)
                    }
                    ForEach(sightings) { sighting in
                        LabeledContent(sighting.id) {
                            Text("\(Int(sighting.rssi)) dBm · \(sighting.distance.map { String(format: "%.1f m", $0) } ?? "?") · \(Int(sighting.secondsAgo)) s")
                                .monospacedDigit()
                        }
                    }
                }
                if !positioning.unknownBeacons.isEmpty {
                    Section(tr("Heard, but not in the server's list", "Słyszane, ale spoza listy serwera")) {
                        ForEach(positioning.unknownBeacons, id: \.self) { Text($0) }
                    }
                }
                Section(tr("From the server", "Z serwera")) {
                    ForEach(positioning.directory.beacons) { beacon in
                        LabeledContent(beacon.name ?? beacon.id,
                                       value: String(format: "%@ · %.1f, %.1f · %.0f dBm", beacon.id, beacon.point.x, beacon.point.y, beacon.txPower))
                    }
                }
            }
        }
        .navigationTitle(tr("Beacons", "Beacony"))
    }
}

/// An icon in a coloured rounded square, a title and an optional value (like Settings on iPhone).
/// One way to explore (with the map / just listening) as a big card: picture-like icon, name, one line about it.
private struct ModeCard: View {
    let mode: UserMode
    let isSelected: Bool
    var action: () -> Void

    private var tint: Color { mode == .blind ? Theme.coral : Theme.accent }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : tint)
                        .frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(isSelected ? tint : tint.opacity(0.14)))
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? tint : Theme.line)
                }
                Text(mode.title)
                    .font(Theme.bodyBold)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(mode.cardDetail)
                    .font(Theme.small)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(padding: 14, fill: isSelected ? tint.opacity(0.08) : Theme.card,
                                     highlight: isSelected ? tint : nil))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

struct SettingsRow: View {
    var title: String
    var systemImage: String
    var tint: Color
    var value: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint))
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)
            if let value {
                Spacer(minLength: 8)
                Text(value)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(1)
            }
        }
    }
}

import Foundation
import Observation

/// Which text-to-speech voice the app uses, and the ElevenLabs configuration. Persisted between launches.
///
/// API key: a key pasted in the app (stored in the Keychain) always wins. Without one,
/// the built-in key from `Secrets.swift` is used, so ElevenLabs works out of the box.
@Observable
final class VoiceSettings {
    enum Engine: String, CaseIterable, Identifiable {
        case apple
        case elevenLabs

        var id: Self { self }

        var title: String {
            switch self {
            case .apple: "Apple (offline)"
            case .elevenLabs: "ElevenLabs"
            }
        }
    }

    var engine: Engine {
        didSet { defaults.set(engine.rawValue, forKey: Keys.engine) }
    }

    /// The key pasted into the app. Empty = use the built-in key.
    var apiKey: String {
        didSet {
            KeychainStore.save(apiKey)
            resetConnection()
        }
    }

    var voiceID: String {
        didSet { defaults.set(voiceID, forKey: Keys.voiceID) }
    }

    var model: ElevenLabsTTS.Model {
        didSet { defaults.set(model.rawValue, forKey: Keys.model) }
    }

    /// Speaking speed, 0.7…1.2. A bit slower than normal by default: easier to follow while walking.
    var speed: Float {
        didSet { defaults.set(speed, forKey: Keys.speed) }
    }

    /// The voice used until you pick one yourself (matched by name in your ElevenLabs voices, ignoring accents).
    static let preferredVoiceName = "Makłowicz"

    /// "Slower (88%)" / "Normal" / "Faster (110%)" for the speed slider.
    static func speedName(_ speed: Float) -> String {
        let percent = Int((speed * 100).rounded())
        if speed < 0.95 { return tr("Slower (\(percent)%)", "Wolniej (\(percent)%)") }
        if speed > 1.05 { return tr("Faster (\(percent)%)", "Szybciej (\(percent)%)") }
        return tr("Normal", "Normalnie")
    }
    /// True once the preferred voice was looked for and not found among your voices.
    private(set) var preferredVoiceMissing = false

    private(set) var voices: [ElevenLabsTTS.Voice] = []
    private(set) var isLoadingVoices = false
    private(set) var voicesError: String?
    /// True once ElevenLabs has accepted the key.
    private(set) var isKeyVerified = false
    /// A non-fatal problem, e.g. the key works but isn't allowed to list voices.
    private(set) var voicesNote: String?

    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        // "v2": an older build saved "Apple" as the default; start fresh so ElevenLabs is the default.
        static let engine = "voice.engine.v2"
        static let voiceID = "voice.elevenLabs.voiceID"
        static let model = "voice.elevenLabs.model"
        static let speed = "voice.speed"
        static let userPicked = "voice.elevenLabs.userPicked"
    }

    /// Lowercase, no accents, ł → l ("Makłowicz" and "Maklowicz" match).
    private static func fold(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "ł", with: "l")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Choose a voice yourself (from Settings). From then on the preferred voice isn't forced.
    func pick(voiceID: String) {
        self.voiceID = voiceID
        defaults.set(true, forKey: Keys.userPicked)
    }

    init() {
        let apiKey = KeychainStore.load()
        self.apiKey = apiKey
        let hasAnyKey = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !Secrets.elevenLabsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // ElevenLabs is the default whenever a key is available.
        engine = defaults.string(forKey: Keys.engine).flatMap(Engine.init) ?? (hasAnyKey ? .elevenLabs : .apple)
        voiceID = defaults.string(forKey: Keys.voiceID) ?? ElevenLabsTTS.defaultVoiceID
        model = defaults.string(forKey: Keys.model).flatMap(ElevenLabsTTS.Model.init) ?? .multilingualV2
        speed = defaults.object(forKey: Keys.speed) as? Float ?? 0.88
    }

    // MARK: - Keys

    /// The key that ships with the app (Secrets.swift).
    var builtInKey: String {
        Secrets.elevenLabsAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when someone pasted their own key in the app.
    var hasOwnKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when the app is running on the built-in key.
    var usesBuiltInKey: Bool {
        !hasOwnKey && !builtInKey.isEmpty
    }

    /// The key actually sent to ElevenLabs.
    var effectiveKey: String {
        hasOwnKey ? apiKey.trimmingCharacters(in: .whitespacesAndNewlines) : builtInKey
    }

    var hasAPIKey: Bool {
        !effectiveKey.isEmpty
    }

    /// The ElevenLabs client to use, or nil when the Apple voice is selected or no key is set.
    var elevenLabs: ElevenLabsTTS? {
        guard engine == .elevenLabs, hasAPIKey else { return nil }
        return ElevenLabsTTS(apiKey: effectiveKey, voiceID: voiceID, model: model, speed: speed)
    }

    /// A client for any voice (e.g. to preview it), or nil without a key.
    func client(voiceID: String) -> ElevenLabsTTS? {
        guard hasAPIKey else { return nil }
        return ElevenLabsTTS(apiKey: effectiveKey, voiceID: voiceID, model: model, speed: speed)
    }

    /// The account's voices once loaded; ElevenLabs' default voices until then (or if listing isn't allowed).
    var availableVoices: [ElevenLabsTTS.Voice] {
        voices.isEmpty ? ElevenLabsTTS.premadeVoices : voices
    }

    var selectedVoiceName: String {
        availableVoices.first { $0.voiceID == voiceID }?.name ?? tr("Custom voice", "Własny głos")
    }

    /// A word or two for the Settings row, e.g. "George" or "Apple".
    var shortSummary: String {
        engine == .apple || !hasAPIKey ? "Apple" : selectedVoiceName
    }

    /// One-line summary, e.g. "ElevenLabs · George · Lifelike".
    var summary: String {
        switch engine {
        case .apple: tr("Apple voice (offline)", "Głos Apple (offline)")
        case .elevenLabs where !hasAPIKey: tr("ElevenLabs (add an API key)", "ElevenLabs (dodaj klucz API)")
        case .elevenLabs: "ElevenLabs · \(selectedVoiceName) · \(model.title)"
        }
    }

    /// Loads the account's voices. This is also how we check that the key works.
    func loadVoices() async {
        guard hasAPIKey, !isLoadingVoices else { return }
        isLoadingVoices = true
        defer { isLoadingVoices = false }
        do {
            let loaded = try await ElevenLabsTTS.fetchVoices(apiKey: effectiveKey)
            voices = loaded
            voicesError = nil
            voicesNote = nil
            isKeyVerified = true
            // Until you choose a voice yourself, use the preferred one (Makłowicz) when the account has it.
            let wanted = Self.fold(Self.preferredVoiceName)
            let preferred = loaded.first { Self.fold($0.name).contains(wanted) }
            preferredVoiceMissing = preferred == nil
            if !defaults.bool(forKey: Keys.userPicked), let preferred {
                voiceID = preferred.voiceID
            } else if !loaded.contains(where: { $0.voiceID == voiceID }), let first = loaded.first {
                // The saved voice isn't on this account: pick the first one that is.
                voiceID = first.voiceID
            }
        } catch let error as ElevenLabsError where error.isMissingPermission {
            // The key is valid, it just can't list voices. Speech still works with the default voice.
            voices = []
            voicesError = nil
            isKeyVerified = true
            preferredVoiceMissing = true
            voicesNote = tr("Your key works but can't list your own voices, so ElevenLabs' default voices are shown. To see all of yours (and Makłowicz), edit the key on elevenlabs.io and turn on Voices (Read).",
                            "Klucz działa, ale nie może pobrać listy Twoich głosów, więc pokazuję domyślne głosy ElevenLabs. Żeby zobaczyć swoje (i Makłowicza), w ustawieniach klucza na elevenlabs.io włącz Voices (Read).")
        } catch {
            isKeyVerified = false
            voicesError = error.localizedDescription
        }
    }

    /// Forgets the last check and asks ElevenLabs again.
    func recheck() async {
        resetConnection()
        await loadVoices()
    }

    private func resetConnection() {
        voices = []
        voicesError = nil
        voicesNote = nil
        isKeyVerified = false
    }
}

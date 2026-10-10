import AVFoundation
import Foundation
import Observation
import Speech

/// Listens for a phrase you choose (default "Hej przewodniku" / "Hey guide") and then hands over to the normal
/// voice commands, so you can talk to the guide without touching the phone.
///
/// - Apple speech recognition on the iPhone's microphone (on the device itself when the language supports it).
/// - Off by default: while it's on, the microphone stays on (orange dot) and it uses some battery.
/// - Only one thing can use the microphone: the guide calls `suspend()` before recording a command and
///   `resume()` afterwards.
/// - Apple stops a recognition after about a minute, so it starts a fresh one every 50 seconds.
@Observable
final class WakeWordListener {
    enum Status: Equatable {
        case off
        case listening
        case paused
        case unavailable(String)
    }

    /// The setting (Settings › Wake phrase).
    var isEnabled: Bool = UserDefaults.standard.bool(forKey: Keys.enabled) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if isEnabled {
                if wanted { scheduleBegin(after: 0.1) }
            } else {
                endRecognition()
                status = .off
            }
        }
    }

    /// The phrase you set. Empty = the default for the app language.
    var phrase: String = UserDefaults.standard.string(forKey: Keys.phrase) ?? "" {
        didSet {
            UserDefaults.standard.set(phrase, forKey: Keys.phrase)
            // Use the new phrase straight away.
            if status == .listening { restartSoon() }
        }
    }

    /// The phrase actually listened for.
    var effectivePhrase: String {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultPhrase : trimmed
    }

    static var defaultPhrase: String { tr("Hey guide", "Hej przewodniku") }

    private(set) var status: Status = .off
    /// Bumped each time the phrase is heard (screens react by listening for a command).
    private(set) var heardEvent = 0

    var statusText: String {
        switch status {
        case .off: tr("Off", "Wyłączone")
        case .listening: tr("Listening for \u{201C}\(effectivePhrase)\u{201D}", "Czekam na „\(effectivePhrase)”")
        case .paused: tr("Paused while you talk", "Wstrzymane, gdy mówisz")
        case .unavailable(let reason): reason
        }
    }

    private enum Keys {
        static let enabled = "voice.wakeWord.enabled"
        static let phrase = "voice.wakeWord.phrase"
    }

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var tapInstalled = false
    /// The guide is running (museum screens, app in front).
    @ObservationIgnored private var wanted = false
    /// A spoken command is being recorded, or the phrase was just heard.
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var handoff = 0
    @ObservationIgnored private var cycleTask: Task<Void, Never>?
    @ObservationIgnored private var beginTask: Task<Void, Never>?

    // MARK: - Control (the guide calls these)

    /// The guide started: listen for the phrase if it's switched on.
    func start() {
        wanted = true
        if isEnabled, !suspended { scheduleBegin(after: 0.3) }
    }

    /// The guide stopped (background, left the museum): microphone off.
    func stop() {
        wanted = false
        suspended = false
        endRecognition()
        status = isEnabled ? .paused : .off
    }

    /// A command is about to be recorded: let go of the microphone.
    func suspend() {
        suspended = true
        handoff += 1
        endRecognition()
        if isEnabled { status = .paused }
    }

    /// The command is done: listen for the phrase again.
    func resume() {
        suspended = false
        if wanted, isEnabled { scheduleBegin(after: 0.4) }
    }

    // MARK: - Recognition

    private func scheduleBegin(after seconds: Double) {
        beginTask?.cancel()
        beginTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.begin()
        }
    }

    private func begin() async {
        guard wanted, isEnabled, !suspended, task == nil else { return }

        guard await Self.speechPermission() else {
            status = .unavailable(tr("Speech recognition is off. Turn it on in Settings › Privacy › Speech Recognition.",
                                     "Rozpoznawanie mowy jest wyłączone. Włącz je w Ustawieniach › Prywatność › Rozpoznawanie mowy."))
            return
        }
        let micAllowed: Bool
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micAllowed = true
        case .denied: micAllowed = false
        default: micAllowed = await AVAudioApplication.requestRecordPermission()
        }
        guard micAllowed else {
            status = .unavailable(tr("Microphone access is off. Turn it on in Settings › Privacy › Microphone.",
                                     "Dostęp do mikrofonu jest wyłączony. Włącz go w Ustawieniach › Prywatność › Mikrofon."))
            return
        }
        // Things may have changed while we waited for permission.
        guard wanted, isEnabled, !suspended, task == nil else { return }

        let locale = Locale(identifier: LanguageSettings.shared.current == .polish ? "pl-PL" : "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            status = .unavailable(tr("Speech recognition isn't available right now.", "Rozpoznawanie mowy jest teraz niedostępne."))
            cycleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                await self?.begin()
            }
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.contextualStrings = [effectivePhrase]
        request.taskHint = .search

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = .unavailable(tr("No microphone found.", "Nie znaleziono mikrofonu."))
            return
        }
        if tapInstalled { input.removeTap(onBus: 0) }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(appendingTo: request))
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            status = .unavailable(tr("The microphone is busy.", "Mikrofon jest zajęty."))
            restartSoon(after: 5)
            return
        }

        session += 1
        let id = session
        let target = VoiceCommands.normalize(effectivePhrase)
        self.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, finished in
            self?.handle(text: text, finished: finished, session: id, target: target)
        })
        status = .listening

        // Start a fresh recognition before Apple's one-minute limit.
        cycleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard !Task.isCancelled else { return }
            self?.restartSoon(session: id)
        }
    }

    private func handle(text: String?, finished: Bool, session id: Int, target: [String]) {
        guard id == session, task != nil else { return }
        if let text, Self.contains(target, in: VoiceCommands.normalize(text)) {
            // Heard it: let go of the microphone and let the screen listen for the command.
            suspended = true
            handoff += 1
            let ticket = handoff
            endRecognition()
            status = .paused
            heardEvent += 1
            // If nothing takes over (e.g. the guide is already listening), go back to waiting for the phrase.
            beginTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled, self.handoff == ticket, self.suspended else { return }
                self.resume()
            }
            return
        }
        if finished { restartSoon(session: id) }
    }

    /// Ends this recognition and starts a new one shortly (only if `session` is still the current one).
    private func restartSoon(session id: Int? = nil, after seconds: Double = 0.2) {
        if let id, id != session { return }
        endRecognition()
        if wanted, isEnabled, !suspended { scheduleBegin(after: seconds) }
    }

    private func endRecognition() {
        cycleTask?.cancel()
        cycleTask = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        session += 1
    }

    // MARK: - Helpers (not on the main actor: Speech and AVAudioEngine call these from their own threads)

    nonisolated private static func tap(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func resultHandler(
        _ deliver: @escaping @MainActor @Sendable (String?, Bool) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in deliver(text, finished) }
        }
    }

    nonisolated private static func speechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    /// True when the phrase's words appear in what was heard, allowing a small slip
    /// ("hej przewodnik" still matches "hej przewodniku").
    nonisolated static func contains(_ phrase: [String], in words: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        let target = Array(phrase.joined(separator: " "))
        let allowed = max(1, target.count / 5)
        for start in 0...(words.count - phrase.count) {
            let window = Array(words[start..<(start + phrase.count)].joined(separator: " "))
            if editDistance(window, target) <= allowed { return true }
        }
        return false
    }

    nonisolated private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

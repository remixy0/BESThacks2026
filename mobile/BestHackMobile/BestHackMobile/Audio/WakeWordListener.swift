import AVFoundation
import Foundation
import Observation
import Speech

/// Listens in the background for the wake phrase (e.g. "Hej Bloop") and calls `onWake` when it hears it.
///
/// Uses Apple's speech recognizer, on the device when the language supports it (no network, no cost), so it can
/// run all the time while you're in the museum. The command that follows is recorded and recognized separately
/// (ElevenLabs), so this only has to spot the phrase. Matching is forgiving: each word may be off by a letter or two
/// ("blup", "blob", "hey" for "hej").
@Observable
final class WakeWordListener {
    private(set) var isListening = false
    private(set) var problem: String?

    /// Called on the main actor when the phrase was heard. Listening is paused until `resume()`.
    @ObservationIgnored var onWake: (() -> Void)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var restartTask: Task<Void, Never>?
    @ObservationIgnored private var phrase = ""
    @ObservationIgnored private var phraseWords: [String] = []
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var tapInstalled = false

    /// Starts (or restarts with a new phrase or language).
    func start(phrase: String, language: AppLanguage) async {
        let words = VoiceCommands.normalize(phrase)
        guard !words.isEmpty else {
            stop()
            return
        }
        wanted = true
        self.phrase = phrase
        phraseWords = words
        guard await Self.authorize() else {
            problem = tr("Speech recognition is off, so the wake phrase can't be heard. Turn it on in Settings › Privacy › Speech Recognition.",
                         "Rozpoznawanie mowy jest wyłączone, więc hasło nie zadziała. Włącz je w Ustawieniach › Prywatność › Rozpoznawanie mowy.")
            wanted = false
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            problem = tr("Microphone access is off.", "Dostęp do mikrofonu jest wyłączony.")
            wanted = false
            return
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language == .polish ? "pl-PL" : "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            problem = tr("Speech recognition isn't available right now.", "Rozpoznawanie mowy jest teraz niedostępne.")
            return
        }
        self.recognizer = recognizer
        problem = nil
        guard wanted, !paused else { return }
        beginSession()
    }

    func stop() {
        wanted = false
        paused = false
        endSession()
    }

    /// Frees the microphone for a moment (while a command is recorded). `resume()` picks up again.
    func pause() {
        paused = true
        endSession()
    }

    func resume() {
        paused = false
        guard wanted, recognizer != nil, !isListening else { return }
        beginSession()
    }

    // MARK: - Sessions

    private func beginSession() {
        endSession()
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = [phrase]

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            problem = tr("No microphone found.", "Nie znaleziono mikrofonu.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(request))
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            problem = tr("Couldn't start listening: ", "Nie udało się zacząć słuchać: ") + error.localizedDescription
            return
        }

        generation += 1
        let current = generation
        self.request = request
        // The phrase is looked for on the recognizer's own queue; the main thread only hears about a match or the
        // end of a session (partial results come many times a second and would compete with the map).
        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler(phrase: phraseWords) { [weak self] matched, text, done in
            Task { @MainActor in self?.handle(matched: matched, text: text, done: done, generation: current) }
        })
        isListening = true

        // Recognition sessions don't last forever (about a minute on the server): start fresh every 50 s.
        restartTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard !Task.isCancelled else { return }
            self?.restart(generation: current)
        }
    }

    private func handle(matched: Bool, text: String?, done: Bool, generation: Int) {
        guard generation == self.generation, isListening else { return }
        if matched {
            print("[Wake] heard the phrase in: \(text ?? "")")
            paused = true
            endSession()
            onWake?()
            return
        }
        if done { restart(generation: generation) }
    }

    private func restart(generation: Int) {
        guard generation == self.generation, wanted, !paused else { return }
        beginSession()
    }

    private func endSession() {
        restartTask?.cancel()
        restartTask = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        isListening = false
    }

    // MARK: - Matching

    /// True when the phrase's words appear in order, each allowed to differ by a letter or two.
    nonisolated static func contains(_ phrase: [String], in words: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        for start in 0...(words.count - phrase.count) {
            var all = true
            for (offset, wanted) in phrase.enumerated() where !similar(words[start + offset], wanted) {
                all = false
                break
            }
            if all { return true }
        }
        return false
    }

    nonisolated private static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let allowed = max(1, b.count / 3)
        return abs(a.count - b.count) <= allowed && editDistance(Array(a), Array(b)) <= allowed
    }

    nonisolated private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Callbacks that run off the main thread
    // Made in nonisolated functions so they don't inherit the main actor (they're called on audio/speech queues).

    nonisolated private static func makeTap(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    /// Looks for the phrase right here (off the main thread) and only calls `deliver(matched, text, done)` when it
    /// was heard or the session ended.
    nonisolated private static func makeResultHandler(
        phrase: [String],
        _ deliver: @escaping @Sendable (Bool, String?, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            // Only the last few words matter: the phrase is what was said just now.
            let words = text.map { Array(VoiceCommands.normalize($0).suffix(phrase.count + 4)) } ?? []
            let matched = Self.contains(phrase, in: words)
            if matched || done { deliver(matched, text, done) }
        }
    }

    nonisolated private static func authorize() async -> Bool {
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return status == .authorized
    }
}

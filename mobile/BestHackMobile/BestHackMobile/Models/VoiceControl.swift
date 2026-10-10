import Foundation
import Observation

/// Talking to the guide: listen once (iPhone microphone), turn the speech into text with ElevenLabs,
/// and work out which command it was.
@Observable
final class VoiceControl {
    enum State: Equatable {
        case idle, listening, thinking
    }

    struct Result: Sendable {
        let text: String
        let heard: VoiceCommands.Heard
    }

    private(set) var state: State = .idle
    /// The last thing that was heard, word for word.
    private(set) var lastHeard: String?
    /// Why the last attempt failed (no key, no microphone access, network…), for the UI.
    private(set) var problem: String?

    let recorder = VoiceRecorder()

    var isBusy: Bool { state != .idle }

    /// Each `listen()` gets a number; `cancel()` bumps it so an older one gives up and returns nil.
    @ObservationIgnored private var session = 0

    /// Listens once. `cue` plays the "speak now" beep. Returns nil when nothing was said or it failed.
    func listen(apiKey: String, language: AppLanguage, cue: () -> Void) async -> Result? {
        guard state == .idle else { return nil }
        guard !apiKey.isEmpty else {
            problem = tr("Voice commands need an ElevenLabs API key (with Speech to Text).",
                         "Polecenia głosowe potrzebują klucza ElevenLabs (z uprawnieniem Speech to Text).")
            return nil
        }
        guard await recorder.requestPermission() else {
            problem = tr("Microphone access is off. Turn it on in Settings › Privacy › Microphone.",
                         "Dostęp do mikrofonu jest wyłączony. Włącz go w Ustawieniach › Prywatność › Mikrofon.")
            return nil
        }
        session += 1
        let id = session
        state = .listening
        problem = nil
        cue()
        // Let the beep finish so it isn't recorded.
        try? await Task.sleep(for: .milliseconds(280))
        guard id == session else { return nil }
        let recording = await recorder.record()
        guard id == session else {
            if let recording { try? FileManager.default.removeItem(at: recording) }
            return nil
        }
        guard let url = recording else {
            state = .idle
            return nil
        }
        state = .thinking
        defer {
            if id == session { state = .idle }
            try? FileManager.default.removeItem(at: url)
        }
        do {
            let text = try await ElevenLabsSTT(apiKey: apiKey).transcribe(fileURL: url, languageCode: language.speechCode)
            // Cancelled while it was being recognized (a tap, another screen): too late to act on it.
            guard id == session else { return nil }
            lastHeard = text
            guard !text.isEmpty else { return nil }
            return Result(text: text, heard: VoiceCommands.parse(text))
        } catch {
            guard id == session else { return nil }
            problem = tr("Couldn't understand that: ", "Nie udało się rozpoznać mowy: ") + error.localizedDescription
            return nil
        }
    }

    /// Drops the command being recorded or recognized: `listen()` returns nil, nothing is acted on.
    /// (A tap on another control, or a different screen, wins over what you were saying.)
    func cancel() {
        guard state != .idle else { return }
        session += 1
        state = .idle
        recorder.stop()
    }

    /// Stops listening now (what was said so far still gets recognized).
    func finishListening() {
        recorder.stop()
    }
}

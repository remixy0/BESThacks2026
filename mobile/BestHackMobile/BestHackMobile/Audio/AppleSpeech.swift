import AVFoundation
import NaturalLanguage

/// The built-in, offline iOS voice. Rendered to buffers (instead of played directly) so it can be placed in 3D.
nonisolated final class AppleSpeech: @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()

    /// `rate` 0.7…1.2, where 1 = the system's normal speaking rate.
    func speak(_ text: String, rate: Float = 1, into output: SpeechOutput, token: Int, onFinish: @escaping @Sendable () -> Void) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: text)
        utterance.rate = min(max(AVSpeechUtteranceDefaultSpeechRate * rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)

        synthesizer.write(utterance) { buffer in
            if let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 {
                output.enqueue(pcm, token: token)
            } else {
                // An empty buffer marks the end of the utterance.
                output.finish(token: token, onFinish: onFinish)
            }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Picks a voice matching the message's language (e.g. Polish or English), preferring the
    /// best-quality voice installed. Falls back to the system default when unsure.
    /// Listing the installed voices is slow, so it happens once, and each language's pick is remembered.
    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence > 0.6 else { return nil }
        return cache.voice(for: language.rawValue)
    }

    private static let cache = VoiceCache()

    /// Lists the installed voices ahead of time (it's slow the first time), off the main thread.
    static func prewarm() {
        Task.detached(priority: .utility) {
            _ = cache.voice(for: "pl")
            _ = cache.voice(for: "en")
        }
    }
}

/// Remembers the best installed voice per language. Speech can be requested from any thread, hence the lock.
nonisolated private final class VoiceCache: @unchecked Sendable {
    private let lock = NSLock()
    private var installed: [AVSpeechSynthesisVoice]?
    private var picks: [String: AVSpeechSynthesisVoice?] = [:]

    func voice(for language: String) -> AVSpeechSynthesisVoice? {
        lock.lock()
        defer { lock.unlock() }
        if let pick = picks[language] { return pick }
        if installed == nil { installed = AVSpeechSynthesisVoice.speechVoices() }
        let preferredRegion = Locale.current.region?.identifier
        let candidates = (installed ?? []).filter { $0.language.hasPrefix(language) }
        let best = candidates.max { a, b in
            if a.quality != b.quality { return a.quality.rawValue < b.quality.rawValue }
            // Same quality: prefer the user's region (e.g. en-GB over en-US in the UK).
            return !a.language.hasSuffix(preferredRegion ?? "-") && b.language.hasSuffix(preferredRegion ?? "-")
        }
        picks[language] = best
        return best
    }
}

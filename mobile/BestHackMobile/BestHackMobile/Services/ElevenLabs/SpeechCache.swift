import CryptoKit
import Foundation

/// Keeps ElevenLabs speech on the phone, so the same sentence in the same voice is only ever requested once.
///
/// - **Key:** voice + model + speed + text (SHA-256). Changing the voice, quality or speed records fresh audio.
/// - **Files:** raw 16-bit 24 kHz mono PCM (exactly what ElevenLabs streams) in Library/Caches/ElevenLabsSpeech.
///   About 2.9 MB per minute of speech. iOS may empty the folder when the phone runs out of space.
/// - **Shared downloads:** asking for a clip that is still downloading joins that download instead of sending a
///   second request (e.g. you tap "tell me" while Settings is fetching the stories).
/// - **No pile-ups:** a download nobody is listening to any more (you tapped on, the screen changed) is cancelled
///   straight away, so quick taps never queue up old requests in front of the one you're waiting for.
///   Downloads started ahead of time (`prepare`, `load`) always finish and are saved.
/// - Above `limit`, the clips heard longest ago are removed.
nonisolated final class SpeechCache: @unchecked Sendable {
    static let shared = SpeechCache()

    /// ~1.5 hours of speech.
    private let limit: Int64 = 250 * 1024 * 1024
    private let folder: URL
    private let lock = NSLock()
    private var downloads: [String: SpeechClip] = [:]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        folder = caches.appending(path: "ElevenLabsSpeech", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    // MARK: - Using it

    /// The clip for `text`: from the phone when it was heard before, otherwise a download from ElevenLabs
    /// (started now, or joined if it's already on its way).
    func clip(for text: String, using tts: ElevenLabsTTS) -> SpeechClip {
        let key = Self.key(for: text, using: tts)
        // (A download that was just dropped because nobody listened isn't joined: it's about to fail.)
        if let running = lock.withLock({ downloads[key] }), !running.isAbandoned { return running }

        let file = url(for: key)
        if let saved = try? Data(contentsOf: file), saved.count >= 2 {
            touch(file)
            return SpeechClip(saved: saved)
        }

        let (clip, isNew) = lock.withLock { () -> (SpeechClip, Bool) in
            if let running = downloads[key], !running.isAbandoned { return (running, false) }
            let clip = SpeechClip()
            downloads[key] = clip
            return (clip, true)
        }
        guard isNew else { return clip }

        print("[ElevenLabs] not saved yet, requesting: \(text.prefix(40))…")
        // Detached: it belongs to the clip, not to whoever asked first (others may join it).
        let download = Task.detached(priority: .userInitiated) { [self] in
            do {
                try await tts.download(text, into: clip)
                self.save(clip.bytes, as: file)
                clip.finish()
            } catch {
                clip.finish(error: error)
            }
            self.lock.withLock {
                // Only if it's still this clip (a fresh one may have replaced a dropped one).
                if self.downloads[key] === clip { self.downloads[key] = nil }
            }
        }
        clip.whenAbandoned {
            print("[ElevenLabs] nobody is listening any more, cancelled: \(text.prefix(40))…")
            download.cancel()
        }
        return clip
    }

    /// Makes sure `text` is saved, downloading it if needed. Returns once it's on the phone.
    @concurrent
    func load(_ text: String, using tts: ElevenLabsTTS) async throws {
        let clip = clip(for: text, using: tts)
        clip.keepDownloading()
        for try await _ in clip.audio() {}
    }

    /// Starts downloading `text` in the background if it isn't saved yet (e.g. the next sentence in the queue),
    /// so it's ready by the time it's needed.
    func prepare(_ text: String, using tts: ElevenLabsTTS) {
        guard !contains(text, using: tts) else { return }
        clip(for: text, using: tts).keepDownloading()
    }

    func contains(_ text: String, using tts: ElevenLabsTTS) -> Bool {
        FileManager.default.fileExists(atPath: url(for: Self.key(for: text, using: tts)).path(percentEncoded: false))
    }

    // MARK: - Settings

    struct Usage: Equatable, Sendable {
        var clips = 0
        var bytes: Int64 = 0
    }

    func usage() -> Usage {
        savedFiles().reduce(into: Usage()) { usage, file in
            usage.clips += 1
            usage.bytes += Int64(file.size)
        }
    }

    /// Forgets every saved clip (they'll be requested again when needed).
    func removeAll() {
        for file in savedFiles() {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    // MARK: - Files

    private static func key(for text: String, using tts: ElevenLabsTTS) -> String {
        let speed = Int((min(max(tts.speed, 0.7), 1.2) * 100).rounded())
        let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // "v1": bump when the request changes in a way that changes the audio (format, voice settings).
        let id = "v1|pcm_24000|\(tts.voiceID)|\(tts.model.rawValue)|\(speed)|\(spoken)"
        return SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func url(for key: String) -> URL {
        folder.appending(path: key + ".pcm", directoryHint: .notDirectory)
    }

    private func save(_ audio: Data, as file: URL) {
        guard audio.count >= 2 else { return }
        do {
            try audio.write(to: file, options: .atomic)
        } catch {
            print("[ElevenLabs] couldn't save speech: \(error.localizedDescription)")
            return
        }
        trimIfNeeded()
    }

    /// Marks a clip as just heard (the oldest-heard go first when trimming).
    private func touch(_ file: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path(percentEncoded: false))
    }

    private func trimIfNeeded() {
        var files = savedFiles()
        var total = files.reduce(Int64(0)) { $0 + Int64($1.size) }
        guard total > limit else { return }
        files.sort { $0.date < $1.date }
        for file in files where total > limit * 8 / 10 {
            try? FileManager.default.removeItem(at: file.url)
            total -= Int64(file.size)
        }
    }

    private func savedFiles() -> [(url: URL, size: Int, date: Date)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? []
        return urls.filter { $0.pathExtension == "pcm" }.map { url in
            let values = try? url.resourceValues(forKeys: keys)
            return (url: url, size: values?.fileSize ?? 0, date: values?.contentModificationDate ?? Date.distantPast)
        }
    }
}

/// One spoken clip: already on the phone, or still arriving from ElevenLabs.
/// Any number of listeners can read it at the same time; each gets all of it from the start.
nonisolated final class SpeechClip: @unchecked Sendable {
    typealias Listener = AsyncThrowingStream<Data, any Error>.Continuation

    private let lock = NSLock()
    private var data: Data
    private var isDone: Bool
    private var failure: (any Error)?
    private var listeners: [UUID: Listener] = [:]
    /// Finish the download even if nobody listens (fetched ahead of time).
    private var keep = false
    private var abandoned = false
    private var onAbandoned: (@Sendable () -> Void)?

    /// A clip that was saved on the phone.
    init(saved: Data) {
        data = saved
        isDone = true
    }

    /// A clip that is about to be downloaded.
    init() {
        data = Data()
        isDone = false
    }

    /// True when all the audio is here (saved, or the download has finished).
    var isComplete: Bool {
        lock.withLock { isDone && failure == nil }
    }

    /// The download was dropped because nobody was listening any more.
    var isAbandoned: Bool {
        lock.withLock { abandoned }
    }

    /// Everything received so far.
    var bytes: Data {
        lock.withLock { data }
    }

    /// The audio from the start: what's already here at once, then the rest as it arrives.
    /// Ends when the clip is complete; throws if the download failed. Stops early when the reading task is cancelled.
    func audio() -> AsyncThrowingStream<Data, any Error> {
        let (stream, listener) = AsyncThrowingStream<Data, any Error>.makeStream()
        let id = UUID()
        let waiting = lock.withLock { () -> Bool in
            if !data.isEmpty { listener.yield(data) }
            if isDone {
                if let failure { listener.finish(throwing: failure) } else { listener.finish() }
                return false
            }
            listeners[id] = listener
            return true
        }
        // Set outside the lock: termination can call back into `removeListener` straight away.
        if waiting {
            listener.onTermination = { [weak self] _ in self?.removeListener(id) }
        }
        return stream
    }

    /// The download received more audio.
    func append(_ piece: Data) {
        guard !piece.isEmpty else { return }
        let targets = lock.withLock { () -> [Listener] in
            data.append(piece)
            return Array(listeners.values)
        }
        for listener in targets { listener.yield(piece) }
    }

    /// Download to the end even when nobody is listening (it was asked for ahead of time).
    func keepDownloading() {
        lock.withLock { keep = true }
    }

    /// Called once when the last listener leaves before the download has finished (and it isn't kept).
    func whenAbandoned(_ handler: @escaping @Sendable () -> Void) {
        lock.withLock { onAbandoned = handler }
    }

    /// The download ended (with `error` if it failed).
    func finish(error: (any Error)? = nil) {
        let targets = lock.withLock { () -> [Listener] in
            isDone = true
            failure = error
            let all = Array(listeners.values)
            listeners = [:]
            return all
        }
        for listener in targets {
            if let error { listener.finish(throwing: error) } else { listener.finish() }
        }
    }

    private func removeListener(_ id: UUID) {
        let abandoned = lock.withLock { () -> (@Sendable () -> Void)? in
            listeners.removeValue(forKey: id)
            guard listeners.isEmpty, !isDone, !keep, let handler = onAbandoned else { return nil }
            onAbandoned = nil
            abandoned = true
            return handler
        }
        abandoned?()
    }
}

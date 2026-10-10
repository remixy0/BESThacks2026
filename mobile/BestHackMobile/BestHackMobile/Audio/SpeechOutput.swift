import AVFoundation

/// Feeds speech audio from any source (Apple TTS, ElevenLabs, …) into the 3D speech player.
///
/// Every message gets a new "generation" number; audio that arrives for an older message
/// (e.g. after you tapped Speak again) is dropped. Audio arrives on background queues,
/// so this class is not tied to the main actor.
nonisolated final class SpeechOutput: @unchecked Sendable {
    private let player: AVAudioPlayerNode
    private let outputFormat: AVAudioFormat

    private let lock = NSLock()
    private var generation = 0
    private var converter: AVAudioConverter?

    init(player: AVAudioPlayerNode, outputFormat: AVAudioFormat) {
        self.player = player
        self.outputFormat = outputFormat
    }

    /// Starts a new message and returns its generation token.
    func begin() -> Int {
        lock.withLock {
            generation += 1
            converter = nil
            return generation
        }
    }

    /// Drops any audio still arriving for the current message.
    func cancel() {
        lock.withLock { generation += 1 }
    }

    func isCurrent(_ token: Int) -> Bool {
        lock.withLock { generation == token }
    }

    /// Queues audio in any PCM format; it is converted to the 3D mixer's 48 kHz mono float format.
    func enqueue(_ buffer: AVAudioPCMBuffer, token: Int) {
        guard buffer.frameLength > 0, isCurrent(token), let converted = convert(buffer) else { return }
        player.scheduleBuffer(converted, completionHandler: nil)
    }

    /// Queues raw 16-bit little-endian mono PCM (what ElevenLabs sends with `pcm_*` formats).
    func enqueuePCM16(_ data: Data, sampleRate: Double, token: Int) {
        let frames = data.count / 2
        guard frames > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            let channel = buffer.int16ChannelData![0]
            for i in 0..<frames {
                channel[i] = Int16(littleEndian: samples[i])
            }
        }
        enqueue(buffer, token: token)
    }

    /// Marks the end of the message. `onFinish` runs (on a background queue) once everything has been heard.
    func finish(token: Int, onFinish: @escaping @Sendable () -> Void) {
        guard isCurrent(token),
              let marker = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1) else { return }
        // A tiny silent buffer queued behind the speech tells us when playback has caught up.
        marker.frameLength = 1
        marker.floatChannelData?[0][0] = 0
        player.scheduleBuffer(marker, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            if self?.isCurrent(token) == true { onFinish() }
        }
    }

    private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }

        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: outputFormat)
        }
        guard let converter else { return nil }

        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        return error == nil && output.frameLength > 0 ? output : nil
    }
}

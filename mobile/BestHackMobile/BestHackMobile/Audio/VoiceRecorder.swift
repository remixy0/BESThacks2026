import AVFoundation
import Foundation
import Observation

/// Records one short voice command from the iPhone's microphone and stops by itself when you stop talking.
@Observable
final class VoiceRecorder {
    private(set) var isRecording = false
    /// Microphone level 0…1 while recording (for the "listening" indicator).
    private(set) var level: Float = 0

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var stopRequested = false

    /// Asks for microphone access the first time.
    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    /// Records until about a second of quiet after you've spoken (or `maxSeconds`).
    /// Returns the recording, or nil when nothing was said or recording failed.
    func record(maxSeconds: Double = 7, quietAfter: Double = 1.1, giveUpAfter: Double = 5) async -> URL? {
        guard !isRecording, await requestPermission() else { return nil }
        let url = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return nil }
        recorder.isMeteringEnabled = true
        guard recorder.record() else { return nil }
        self.recorder = recorder
        stopRequested = false
        isRecording = true
        defer {
            recorder.stop()
            self.recorder = nil
            isRecording = false
            level = 0
        }

        let start = Date()
        var noiseFloor: Float = -50
        var samples = 0
        var heardSpeech = false
        var quietSince: Date?
        while !Task.isCancelled, !stopRequested {
            try? await Task.sleep(for: .milliseconds(80))
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)   // dBFS, about -60 (quiet) … 0 (loud)
            level = min(max((power + 50) / 45, 0), 1)
            let elapsed = Date().timeIntervalSince(start)

            // The first few readings tell us how loud the room is; speech is clearly louder than that.
            if samples < 4 {
                noiseFloor = samples == 0 ? power : max(noiseFloor, power)
                samples += 1
                continue
            }
            let threshold = max(noiseFloor + 9, -38)
            if power > threshold {
                heardSpeech = true
                quietSince = nil
            } else if heardSpeech {
                if quietSince == nil { quietSince = Date() }
                if let quietSince, Date().timeIntervalSince(quietSince) > quietAfter { break }
            }
            if elapsed > maxSeconds { break }
            if !heardSpeech, elapsed > giveUpAfter { return nil }
        }
        return heardSpeech || stopRequested ? url : nil
    }

    /// Stops the current recording early (it still gets transcribed).
    func stop() {
        stopRequested = true
    }
}

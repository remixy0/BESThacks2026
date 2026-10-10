import AVFoundation

/// The guide's sounds, synthesized as mono (3D placement only works on mono sources).
///
/// - `buffer`: the navigation "bloop": a rising tone with harmonics plus a tiny click at the start. The click and the
///   harmonics carry the high frequencies your ears use to tell front from back and up from down, so the bloop is
///   much easier to place in space than a pure tone.
/// - `drop`: the calm style's sound: a soft wooden "tok" (like a marimba), with just enough brightness to place it.
/// - `softTone`: the chill style's sound: a round, slowly fading tone with a faint shimmer.
/// - `chime`: two bright bell notes: "you're facing the right way".
/// - `listenCue`: a short rising beep: "I'm listening, speak now".
enum Bloop {
    static let sampleRate: Double = 48_000

    /// The navigation sound for a bloop style.
    static func buffer(for style: BloopStyle, format: AVAudioFormat) -> AVAudioPCMBuffer {
        switch style {
        case .guiding: buffer(format: format)
        case .calm: drop(format: format)
        case .chill: softTone(format: format)
        }
    }

    static func buffer(format: AVAudioFormat) -> AVAudioPCMBuffer {
        render(format: format, duration: 0.17) { t, noise in
            let progress = t / 0.17
            // Exponential glide 380 Hz -> 1150 Hz.
            let frequency = 380 * pow(3.0, min(progress * 1.5, 1))
            let phase = 2 * Double.pi * frequency * t
            let tone = sin(phase) + 0.35 * sin(2 * phase) + 0.18 * sin(3 * phase) + 0.08 * sin(5 * phase)
            let envelope = min(t / 0.003, 1) * exp(-t * 19)
            // A 5 ms click of bright noise on the attack.
            let click = noise * exp(-t * 600) * 0.55
            return tone * envelope * 0.62 + click
        }
    }

    /// A soft wooden "tok": a marimba-like note that slides up a touch at the start, like a water drop.
    static func drop(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let duration = 0.34
        return render(format: format, duration: duration) { t, noise in
            // 520 Hz, starting 8 % lower and settling within ~30 ms (phase = integral of the frequency).
            let base = 520.0
            let phase = 2 * Double.pi * base * (t - 0.08 * (1 - exp(-t * 60)) / 60)
            let body = sin(phase) * exp(-t * 9)
            // Marimba-like partials: short, they give the "wood" and the high frequencies for placing it.
            let wood = 0.22 * sin(3.93 * phase) * exp(-t * 38) + 0.06 * sin(9.2 * phase) * exp(-t * 80)
            let attack = min(t / 0.004, 1)
            let fadeOut = min((duration - t) / 0.03, 1)
            let tick = noise * exp(-t * 900) * 0.12
            return ((body + wood) * attack * 0.55 + tick) * fadeOut
        }
    }

    /// A round, gentle tone (G4) with a slow fade and a faint bell shimmer, so it can still be placed.
    static func softTone(format: AVAudioFormat) -> AVAudioPCMBuffer {
        let duration = 0.9
        return render(format: format, duration: duration) { t, _ in
            let phase = 2 * Double.pi * 392 * t
            let tone = sin(phase) + 0.18 * sin(2 * phase) * exp(-t * 6) + 0.05 * sin(5.4 * phase) * exp(-t * 18)
            let envelope = min(t / 0.012, 1) * exp(-t * 4.2)
            let fadeOut = min((duration - t) / 0.06, 1)
            return tone * envelope * fadeOut * 0.42
        }
    }

    static func chime(format: AVAudioFormat) -> AVAudioPCMBuffer {
        render(format: format, duration: 0.55) { t, _ in
            func bell(_ start: Double, _ frequency: Double) -> Double {
                let local = t - start
                guard local >= 0 else { return 0 }
                let envelope = min(local / 0.004, 1) * exp(-local * 7)
                let phase = 2 * Double.pi * frequency * local
                // A bell: the fundamental plus an inharmonic partial.
                return (sin(phase) + 0.45 * sin(2.76 * phase) + 0.2 * sin(5.4 * phase)) * envelope
            }
            return (bell(0, 1047) + bell(0.11, 1568)) * 0.32
        }
    }

    static func listenCue(format: AVAudioFormat) -> AVAudioPCMBuffer {
        render(format: format, duration: 0.24) { t, _ in
            let frequency = t < 0.1 ? 660.0 : 990.0
            let local = t < 0.1 ? t : t - 0.1
            let envelope = min(local / 0.005, 1) * exp(-local * 18)
            return sin(2 * Double.pi * frequency * t) * envelope * 0.5
        }
    }

    /// Renders a mono buffer sample by sample. `noise` is white noise in -1...1 (same every time).
    private static func render(format: AVAudioFormat, duration: Double,
                               sample: (_ t: Double, _ noise: Double) -> Double) -> AVAudioPCMBuffer {
        let rate = format.sampleRate > 0 ? format.sampleRate : sampleRate
        let count = Int(duration * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))!
        buffer.frameLength = AVAudioFrameCount(count)
        let channel = buffer.floatChannelData![0]
        var seed: UInt32 = 0x2545F491
        var previous = 0.0
        for i in 0..<count {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let white = Double(seed >> 8) / Double(1 << 24) * 2 - 1
            // Differencing tilts the noise toward high frequencies (a crude high-pass).
            let bright = (white - previous) * 0.5
            previous = white
            channel[i] = Float(max(min(sample(Double(i) / rate, bright), 1), -1))
        }
        return buffer
    }
}

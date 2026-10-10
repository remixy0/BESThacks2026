import Foundation

#if os(iOS)
import CoreHaptics
import UIKit
#endif

/// Strong, easy-to-feel vibrations for listening mode, built with Core Haptics
/// (falls back to the heaviest UIKit impact on phones without a Taptic Engine).
///
/// Each pattern feels different, so you can tell them apart without looking:
/// - `attention`: three hard knocks: "choose something now".
/// - `selected`: one long buzz: "you picked this one".
/// - `confirmed`: long, short, long: "done, we're going".
/// - `warning`: two quick knocks.
final class Haptics {
    static let shared = Haptics()

    #if os(iOS)
    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private let fallback = UIImpactFeedbackGenerator(style: .heavy)
    #endif

    private init() {
        #if os(iOS)
        makeEngine()
        #endif
    }

    func attention() {
        play([Pulse(at: 0, length: 0.11), Pulse(at: 0.2, length: 0.11), Pulse(at: 0.4, length: 0.11)], sharpness: 0.9)
    }

    func selected() {
        play([Pulse(at: 0, length: 0.38)], sharpness: 0.45)
    }

    func confirmed() {
        play([Pulse(at: 0, length: 0.3), Pulse(at: 0.42, length: 0.1), Pulse(at: 0.64, length: 0.3)], sharpness: 0.6)
    }

    func warning() {
        play([Pulse(at: 0, length: 0.08), Pulse(at: 0.14, length: 0.08)], sharpness: 1)
    }

    // MARK: - Playing

    private struct Pulse {
        var at: TimeInterval
        var length: TimeInterval
    }

    private func play(_ pulses: [Pulse], sharpness: Float) {
        #if os(iOS)
        guard supportsHaptics, let engine else {
            playFallback(pulses)
            return
        }
        do {
            try engine.start()
            var events: [CHHapticEvent] = []
            for pulse in pulses {
                // A sharp knock at the start of every pulse, then a strong buzz for its length.
                events.append(CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1),
                ], relativeTime: pulse.at))
                events.append(CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
                ], relativeTime: pulse.at, duration: pulse.length))
            }
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: 0)
        } catch {
            playFallback(pulses)
        }
        #endif
    }

    #if os(iOS)
    private func makeEngine() {
        guard supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.isAutoShutdownEnabled = true
            // The engine stops when the app goes to the background; `start()` before each pattern brings it back.
            engine.resetHandler = { @Sendable in
                Task { @MainActor in try? Haptics.shared.engine?.start() }
            }
            self.engine = engine
        } catch {
            print("[Haptics] \(error.localizedDescription)")
        }
    }

    private func playFallback(_ pulses: [Pulse]) {
        fallback.prepare()
        for pulse in pulses {
            let delay = Int(pulse.at * 1000)
            Task {
                try? await Task.sleep(for: .milliseconds(delay))
                self.fallback.impactOccurred(intensity: 1)
            }
        }
    }
    #endif
}

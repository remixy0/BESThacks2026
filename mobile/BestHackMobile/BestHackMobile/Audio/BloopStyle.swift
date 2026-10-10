import Foundation

/// How the guide bloops (Settings › Guide › Bloop rhythm). The direction cues are the same in all three
/// (where the sound comes from, higher pitch as you turn toward the way, muffled when it's behind you);
/// only how often, how loud and which sound change.
enum BloopStyle: String, CaseIterable, Identifiable {
    /// Quick, bright bloops while you're off course: the clearest guidance.
    case guiding
    /// Fewer, softer wooden "tok" sounds.
    case calm
    /// A soft round tone every few seconds: guides you without getting on your nerves.
    case chill

    var id: Self { self }

    var title: String {
        switch self {
        case .guiding: tr("Guiding", "Prowadzący")
        case .calm: tr("Calm", "Spokojny")
        case .chill: "Chill"
        }
    }

    var detail: String {
        switch self {
        case .guiding: tr("Quick bloops until you face the right way. The clearest, but busy.",
                          "Szybkie bloopy, dopóki nie ustawisz się w dobrą stronę. Najdokładniejszy, ale intensywny.")
        case .calm: tr("About one soft sound a second, quieter. Still easy to follow.",
                       "Mniej więcej jeden miękki dźwięk na sekundę, ciszej. Dalej łatwo za nim iść.")
        case .chill: tr("A gentle tone every 2–3 seconds, very quiet when you're on course.",
                        "Delikatny ton co 2–3 sekundy, bardzo cicho, gdy idziesz dobrze.")
        }
    }

    /// One bloop: how it sounds and how long until the next one.
    struct Beat {
        var interval: Double
        var pitch: Float = 1
        var volume: Float = 1
        var muffled = false
    }

    /// The next bloop.
    /// - Parameters:
    ///   - degrees: how far the way is from where you face, 0…180 (nil = no heading, e.g. no AirPods).
    ///   - onTrack: you're facing the right way.
    ///   - metersLeft: distance still to walk.
    func beat(degrees: Double?, onTrack: Bool, metersLeft: Float) -> Beat {
        let closeToEnd = metersLeft < 6
        guard let degrees else {
            // No heading: steady bloops; their direction still tells you where to go.
            let left = Double(metersLeft)
            return switch self {
            case .guiding: Beat(interval: min(max(0.35 + left / 40, 0.35), 0.9))
            case .calm: Beat(interval: min(max(1.0 + left / 30, 1.0), 2.0), volume: 0.75)
            case .chill: Beat(interval: min(max(2.5 + left / 20, 2.5), 4.5), volume: 0.55)
            }
        }
        // 0 when the way is right behind you, 1 when it's straight ahead.
        let alignment = max(0, 1 - degrees / 180)
        let rising = Float(pow(alignment, 1.4))
        let behind = degrees > 110

        if onTrack {
            // On course: just a quiet reminder now and then (a little more often in the last metres).
            return switch self {
            case .guiding: Beat(interval: closeToEnd ? 2.0 : 3.5, pitch: 1.6, volume: 0.35)
            case .calm: Beat(interval: closeToEnd ? 3.5 : 6, pitch: 1.25, volume: 0.3)
            case .chill: Beat(interval: closeToEnd ? 6 : 12, pitch: 1.12, volume: 0.22)
            }
        }
        // Off course: the more you face away, the sooner the next one (and the lower it sounds).
        return switch self {
        case .guiding: Beat(interval: 0.3, pitch: 0.6 + 0.85 * rising, volume: 1, muffled: behind)
        case .calm: Beat(interval: 0.8 + 0.5 * alignment, pitch: 0.8 + 0.4 * rising, volume: 0.75, muffled: behind)
        case .chill: Beat(interval: 2.0 + 1.5 * alignment, pitch: 0.88 + 0.24 * rising, volume: 0.55, muffled: behind)
        }
    }

    /// Quiet time after the "right way" chime before the first on-course reminder.
    var onTrackPause: Double {
        switch self {
        case .guiding: 2
        case .calm: 3
        case .chill: 4
        }
    }

    /// Bloops never come closer together than this, even when you turn away right after one.
    var minimumGap: Double {
        switch self {
        case .guiding: 0
        case .calm: 0.5
        case .chill: 1.2
        }
    }

    /// How loud the "right way" chime is, and how often it may play (head wobbling at the edge would repeat it).
    var chimeVolume: Float {
        switch self {
        case .guiding: 1
        case .calm: 0.6
        case .chill: 0.35
        }
    }

    var chimeCooldown: Double {
        switch self {
        case .guiding: 0
        case .calm: 3
        case .chill: 8
        }
    }
}

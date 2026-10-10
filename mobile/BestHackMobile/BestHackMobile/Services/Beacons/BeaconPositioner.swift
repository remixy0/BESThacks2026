import Foundation
import simd

/// Turns beacon signal strengths into a position on the floor plan. Pure maths, no Core Location.
///
/// 1. Each beacon's RSSI is smoothed (they jump by several dB from one second to the next).
/// 2. RSSI → distance with the log-distance path-loss model: d = 10^((txPower + offset − rssi) / (10·n)).
///    `offset` is that beacon's correction from calibration.
/// 3. With 2+ beacons: weighted least squares (Gauss–Newton with a little damping) for the point whose distances to
///    the beacons best match; nearer beacons count more because their distances are more reliable.
///    With 1 beacon: keep the previous guess but pull it onto the circle around that beacon.
nonisolated struct BeaconPositioner: Sendable {
    struct Anchor: Sendable, Equatable {
        let id: String
        let point: SIMD2<Float>
        /// RSSI at 1 m, in dBm.
        let txPower: Float
    }

    struct Fix: Sendable, Equatable {
        let point: SIMD2<Float>
        /// Rough error in metres.
        let accuracy: Float
        let beaconCount: Int
    }

    /// One beacon as the positioner currently sees it (for the debug screen).
    struct Sighting: Sendable, Identifiable {
        let id: String
        let rssi: Float
        let distance: Float?
        let secondsAgo: Double
    }

    /// How fast signal fades with distance: 2 = open space, 2.5–3 = rooms with people and walls.
    var pathLossExponent: Float = 2.3
    /// Per-beacon correction in dB (positive = the beacon reads stronger than the model expects).
    private(set) var offsets: [String: Float] = [:]

    private var smoothed: [String: (rssi: Float, seen: TimeInterval)] = [:]

    /// A beacon not heard for this long is ignored.
    static let staleAfter: TimeInterval = 4
    /// How much a new reading moves the smoothed RSSI (0…1).
    static let smoothing: Float = 0.35

    init(offsets: [String: Float] = [:]) {
        self.offsets = offsets
    }

    // MARK: - Readings

    mutating func add(id: String, rssi: Float, at time: TimeInterval) {
        guard rssi < 0, rssi > -110 else { return }
        if let previous = smoothed[id], time - previous.seen < Self.staleAfter {
            smoothed[id] = (previous.rssi + (rssi - previous.rssi) * Self.smoothing, time)
        } else {
            smoothed[id] = (rssi, time)
        }
    }

    mutating func forget(before time: TimeInterval) {
        smoothed = smoothed.filter { $0.value.seen >= time }
    }

    func liveCount(at time: TimeInterval) -> Int {
        smoothed.values.filter { time - $0.seen < Self.staleAfter }.count
    }

    func sightings(at time: TimeInterval, anchors: [String: Anchor]) -> [Sighting] {
        smoothed.map { id, value in
            Sighting(id: id, rssi: value.rssi, distance: anchors[id].map { distance(rssi: value.rssi, anchor: $0) },
                     secondsAgo: time - value.seen)
        }
        .sorted { $0.rssi > $1.rssi }
    }

    // MARK: - Position

    func distance(rssi: Float, anchor: Anchor) -> Float {
        let tx = anchor.txPower + (offsets[anchor.id] ?? 0)
        let metres = pow(10, (tx - rssi) / (10 * pathLossExponent))
        return min(max(metres, 0.3), 40)
    }

    /// The best position for the beacons heard in the last few seconds, or nil when none of them is known.
    func fix(anchors: [String: Anchor], near guess: SIMD2<Float>, at time: TimeInterval) -> Fix? {
        var ranges: [(point: SIMD2<Float>, distance: Float)] = []
        for (id, value) in smoothed where time - value.seen < Self.staleAfter {
            guard let anchor = anchors[id] else { continue }
            ranges.append((anchor.point, distance(rssi: value.rssi, anchor: anchor)))
        }
        guard !ranges.isEmpty else { return nil }
        // The six nearest are plenty; far ones mostly add noise.
        ranges.sort { $0.distance < $1.distance }
        if ranges.count > 6 { ranges.removeLast(ranges.count - 6) }

        if ranges.count == 1 {
            let only = ranges[0]
            let away = guess - only.point
            let length = simd_length(away)
            let point = length > 0.01 && length > only.distance ? only.point + away / length * only.distance : guess
            return Fix(point: point, accuracy: max(only.distance, 2), beaconCount: 1)
        }

        // Start from the weighted centre (weights 1/d²), then refine.
        var weightSum: Float = 0
        var start = SIMD2<Float>.zero
        for range in ranges {
            let w = 1 / max(range.distance * range.distance, 0.25)
            start += range.point * w
            weightSum += w
        }
        var p = start / weightSum

        for _ in 0..<12 {
            var a00: Float = 0, a01: Float = 0, a11: Float = 0
            var g = SIMD2<Float>.zero
            for range in ranges {
                let diff = p - range.point
                let r = max(simd_length(diff), 0.05)
                let j = diff / r
                let residual = r - range.distance
                let w = 1 / max(range.distance, 1)
                a00 += w * j.x * j.x
                a01 += w * j.x * j.y
                a11 += w * j.y * j.y
                g += w * j * residual
            }
            // Damping keeps two-beacon cases (an underdetermined direction) near the start point.
            let damping = 0.05 * (a00 + a11) + 1e-3
            a00 += damping
            a11 += damping
            let det = a00 * a11 - a01 * a01
            guard abs(det) > 1e-6 else { break }
            let step = SIMD2(a11 * g.x - a01 * g.y, -a01 * g.x + a00 * g.y) / det
            p -= step
            if simd_length(step) < 0.01 { break }
        }

        var squared: Float = 0
        weightSum = 0
        for range in ranges {
            let w = 1 / max(range.distance, 1)
            let residual = simd_distance(p, range.point) - range.distance
            squared += w * residual * residual
            weightSum += w
        }
        let rms = sqrt(squared / max(weightSum, 1e-3))
        let accuracy = rms + (ranges.count == 2 ? 3 : 1)
        return Fix(point: p, accuracy: accuracy, beaconCount: ranges.count)
    }

    // MARK: - Calibration

    /// You're standing at `point`: work out each beacon's correction so its signal matches its true distance.
    /// Half of each correction is shared (the phone's own antenna and case affect every beacon alike), half is
    /// per beacon (walls, height, a weak battery). Returns how many beacons were used.
    @discardableResult
    mutating func calibrate(at point: SIMD2<Float>, anchors: [String: Anchor], at time: TimeInterval) -> Int {
        var own: [String: Float] = [:]
        for (id, value) in smoothed where time - value.seen < Self.staleAfter {
            guard let anchor = anchors[id] else { continue }
            let trueDistance = max(simd_distance(point, anchor.point), 0.5)
            let expected = anchor.txPower - 10 * pathLossExponent * log10(trueDistance)
            own[id] = value.rssi - expected
        }
        guard !own.isEmpty else { return 0 }
        let sorted = own.values.sorted()
        let shared = sorted[sorted.count / 2]
        var result: [String: Float] = [:]
        for (id, offset) in own {
            result[id] = min(max(0.5 * offset + 0.5 * shared, -15), 15)
        }
        // Beacons not heard right now still get the shared part.
        for id in anchors.keys where result[id] == nil {
            result[id] = min(max(shared * 0.5, -10), 10)
        }
        offsets = result
        return own.count
    }

    mutating func resetCalibration() {
        offsets = [:]
    }
}

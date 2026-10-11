import Foundation
import simd

/// Where you are on the floor, as a best guess plus how unsure it is: a small Kalman filter. Pure maths.
///
/// - **Steps move the guess** (`step`): one step length along your heading. Each step adds a little doubt along
///   the way you walk (step length) and across it (heading error × length).
/// - **Time adds doubt** (`predict`): a lot while you might be moving with no step seen, almost none when standing still.
/// - **Each beacon pulls the guess** onto the circle at its measured distance (`range`), more when the guess is
///   unsure and the beacon is close (near distances are more reliable). A reading far outside what's plausible
///   is mostly ignored, so one bad reflection can't throw you across the room.
///
/// Coordinates are metres in a `FloorFrame`; the covariance is kept as three numbers (it's symmetric).
nonisolated struct PositionFilter: Sendable {
    private(set) var point = SIMD2<Float>.zero
    private(set) var p00: Float = 100
    private(set) var p01: Float = 0
    private(set) var p11: Float = 100
    private(set) var isInitialized = false

    /// Rough error in metres (one standard deviation along the most unsure direction).
    var accuracy: Float {
        let mean = (p00 + p11) / 2
        let spread = sqrt(max(((p00 - p11) / 2) * ((p00 - p11) / 2) + p01 * p01, 0))
        return sqrt(max(mean + spread, 0))
    }

    mutating func reset(to point: SIMD2<Float>, sigma: Float) {
        self.point = point
        p00 = sigma * sigma
        p11 = sigma * sigma
        p01 = 0
        isInitialized = true
    }

    /// Time passes: doubt grows by `rate` m² per second in every direction.
    mutating func predict(seconds: Float, rate: Float) {
        guard seconds > 0 else { return }
        let added = rate * seconds
        p00 += added
        p11 += added
        limit()
    }

    /// One step of `length` metres along `direction` (unit vector). `sigmaLength` in metres, `sigmaAngle` in radians.
    mutating func step(length: Float, direction: SIMD2<Float>, sigmaLength: Float, sigmaAngle: Float) {
        point += direction * length
        let along = sigmaLength * sigmaLength
        let across = (length * sigmaAngle) * (length * sigmaAngle)
        // R · diag(along, across) · Rᵀ with R = [direction, perpendicular].
        let d = direction, n = SIMD2(-direction.y, direction.x)
        p00 += along * d.x * d.x + across * n.x * n.x
        p01 += along * d.x * d.y + across * n.x * n.y
        p11 += along * d.y * d.y + across * n.y * n.y
        limit()
    }

    /// Moved about `metres` in an unknown direction.
    mutating func inflate(metres: Float) {
        p00 += metres * metres
        p11 += metres * metres
        limit()
    }

    /// A beacon at `anchor` says it is `distance` metres away (± `sigma`). Returns false when the reading was
    /// so far off that it was mostly ignored.
    @discardableResult
    mutating func range(to anchor: SIMD2<Float>, distance: Float, sigma: Float) -> Bool {
        let diff = point - anchor
        let predicted = max(simd_length(diff), 0.1)
        let h = predicted > 0.1 ? diff / predicted : SIMD2<Float>(1, 0)
        let ph = SIMD2(p00 * h.x + p01 * h.y, p01 * h.x + p11 * h.y)
        let innovation = distance - predicted
        var noise = sigma * sigma
        var s = h.x * ph.x + h.y * ph.y + noise
        // Further than 3 standard deviations: count it, but only as much as a 3-sigma reading.
        let mahalanobis = innovation * innovation / s
        let accepted = mahalanobis <= 9
        if !accepted {
            noise *= mahalanobis / 9
            s = h.x * ph.x + h.y * ph.y + noise
        }
        let k = ph / s
        point += k * innovation
        p00 -= k.x * ph.x
        p01 -= k.x * ph.y
        p11 -= k.y * ph.y
        limit()
        return accepted
    }

    /// Keeps the guess inside a box (e.g. the room, with a margin).
    mutating func clamp(min low: SIMD2<Float>, max high: SIMD2<Float>) {
        point = simd_clamp(point, low, high)
    }

    /// Keeps the numbers sane: never more sure than 10 cm, never less sure than 50 m.
    private mutating func limit() {
        p00 = min(max(p00, 0.01), 2500)
        p11 = min(max(p11, 0.01), 2500)
        let bound = sqrt(p00 * p11) * 0.99
        p01 = min(max(p01, -bound), bound)
    }
}

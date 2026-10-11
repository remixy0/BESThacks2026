import CoreMotion
import Foundation
import Observation
import simd

/// Steps and turning from the phone's motion sensors (accelerometer + gyroscope, 50 times a second).
///
/// - **Steps:** the up-and-down bounce of walking, measured along gravity (so it works in the hand, flat or upright,
///   and in a pocket). Each bounce is one step; its length comes from how hard you bounce (Weinberg's rule).
/// - **Turning:** the gyroscope's spin around the vertical, added up. That's the same whether the phone is flat
///   or upright, and needs no compass (compasses are unreliable indoors). It only measures *changes*, so the
///   position service lines it up with the museum at calibration.
///
/// The 50 samples a second are handled on a background queue (`MotionProcessor`); the main thread only hears about
/// steps (about two a second), so the AirPods' head tracking and the map never wait behind it.
/// No permission is needed for this (unlike the step counter).
@Observable
final class MotionTracker {
    nonisolated struct Step: Sendable {
        /// Seconds since the phone started (same clock as `ProcessInfo.systemUptime`).
        let time: TimeInterval
        /// Metres, before the user's step-length factor.
        let length: Float
        /// The phone's turning at that moment (radians, positive = left; only differences mean anything).
        let yaw: Float
        /// The phone is held in front of you, screen up-ish (not in a pocket), so its heading is your walking direction.
        let heldInFront: Bool
    }

    private(set) var isRunning = false
    let isAvailable: Bool

    /// Steps since the app started. Not observed (changes twice a second while walking); screens poll it.
    @ObservationIgnored private(set) var stepCount = 0
    @ObservationIgnored private(set) var lastStepLength: Float = 0
    /// Bumped on every start: a heading lined up before a restart no longer applies.
    @ObservationIgnored private(set) var session = 0

    /// The phone's turning since start (radians, positive = left), right now.
    var yaw: Float { processor.snapshot.yaw }
    /// The phone is held in front of you right now.
    var heldInFront: Bool { processor.snapshot.heldInFront }

    /// Called on the main actor for every step.
    @ObservationIgnored var onStep: ((Step) -> Void)?

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private let processor = MotionProcessor()
    @ObservationIgnored private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init() {
        isAvailable = manager.isDeviceMotionAvailable
    }

    func start() {
        guard !isRunning, manager.isDeviceMotionAvailable else { return }
        processor.reset()
        session += 1
        manager.deviceMotionUpdateInterval = 1.0 / 50
        manager.startDeviceMotionUpdates(to: queue, withHandler: Self.makeHandler(processor) { [weak self] steps in
            Task { @MainActor in self?.deliver(steps) }
        })
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    private func deliver(_ steps: [Step]) {
        guard isRunning else { return }
        for step in steps {
            stepCount += 1
            lastStepLength = step.length
            onStep?(step)
        }
    }

    /// Made in a nonisolated function so it doesn't inherit the main actor: it runs on the motion queue.
    nonisolated private static func makeHandler(_ processor: MotionProcessor,
                                                deliver: @escaping @Sendable ([Step]) -> Void) -> CMDeviceMotionHandler {
        { motion, _ in
            guard let motion else { return }
            let steps = processor.process(motion)
            if !steps.isEmpty { deliver(steps) }
        }
    }
}

/// The per-sample work of `MotionTracker`, on its background queue: turning (gyro) and steps (accelerometer).
/// The latest turning can be read from any thread (`snapshot`).
nonisolated final class MotionProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var detector = StepDetector()
    private var lastTimestamp: TimeInterval?
    private var yaw: Float = 0
    private var heldInFront = false

    var snapshot: (yaw: Float, heldInFront: Bool) {
        lock.withLock { (yaw, heldInFront) }
    }

    func reset() {
        lock.withLock {
            detector = StepDetector()
            lastTimestamp = nil
        }
    }

    /// One sample: updates the turning and returns the steps it completes.
    func process(_ motion: CMDeviceMotion) -> [MotionTracker.Step] {
        // Gravity points down, in the phone's own axes.
        let gravity = SIMD3<Float>(Float(motion.gravity.x), Float(motion.gravity.y), Float(motion.gravity.z))
        let length = simd_length(gravity)
        guard length > 0.5 else { return [] }
        let up = -gravity / length
        let rate = SIMD3<Float>(Float(motion.rotationRate.x), Float(motion.rotationRate.y), Float(motion.rotationRate.z))
        let user = SIMD3<Float>(Float(motion.userAcceleration.x), Float(motion.userAcceleration.y), Float(motion.userAcceleration.z))
        let time = motion.timestamp

        return lock.withLock {
            let dt = lastTimestamp.map { Float(min(max(time - $0, 0), 0.1)) } ?? 0
            lastTimestamp = time
            // Spin around "up" (right-hand rule) = counter-clockwise seen from above = turning left.
            yaw = MuseumGeometry.wrap(yaw + simd_dot(rate, up) * dt)
            // Screen facing up-ish (z axis comes out of the screen): you're holding it in front of you.
            heldInFront = up.z > 0.35
            let bounce = simd_dot(user, up) * 9.81
            return detector.update(time: time, upAcceleration: bounce).map {
                MotionTracker.Step(time: time, length: $0, yaw: yaw, heldInFront: heldInFront)
            }
        }
    }
}

/// Finds steps in the vertical acceleration (m/s², up positive, gravity removed). Pure maths.
///
/// Low-pass at 3 Hz (walking is ~2 steps a second), then a step = a peak above `peakThreshold` that rises at least
/// `minSwing` above the dip before it, at least `minInterval` after the previous step.
/// A lone bounce (picking the phone up, a gesture) isn't walking: a step after a pause is held back until the next
/// one follows within `confirmWithin`, then both count.
/// Step length (Weinberg): K · (peak − dip)^¼, kept between 0.3 and 0.95 m.
/// (Thresholds tuned on simulated walking: catches gentle in-hand walking, no false steps from normal fidgeting.)
nonisolated struct StepDetector: Sendable {
    var weinbergK: Float = 0.48

    static let peakThreshold: Float = 0.5
    static let minSwing: Float = 1.0
    static let maxPeak: Float = 15
    static let minInterval: TimeInterval = 0.28
    static let cutoffHz: Double = 3
    static let confirmWithin: TimeInterval = 1.2

    private var filtered: Float = 0
    private var previous: Float = 0
    private var beforePrevious: Float = 0
    private var dip: Float = 0
    private var lastTime: TimeInterval?
    private var lastStep: TimeInterval = -10
    private var pending: Float?

    init(weinbergK: Float = 0.48) {
        self.weinbergK = weinbergK
    }

    /// Feed one sample; returns the lengths of the steps it completes (usually none, sometimes one, two when a
    /// held-back first step is confirmed).
    mutating func update(time: TimeInterval, upAcceleration: Float) -> [Float] {
        let dt = lastTime.map { min(max(time - $0, 0.001), 0.1) } ?? 0.02
        lastTime = time
        let rc = 1 / (2 * Double.pi * Self.cutoffHz)
        let alpha = Float(dt / (rc + dt))

        beforePrevious = previous
        previous = filtered
        filtered += (upAcceleration - filtered) * alpha
        dip = min(dip, filtered)

        // `previous` was a peak if it is higher than both neighbours.
        let isPeak = previous > filtered && previous >= beforePrevious
        guard isPeak, previous > Self.peakThreshold, previous < Self.maxPeak,
              time - lastStep > Self.minInterval else { return [] }
        let swing = previous - dip
        guard swing > Self.minSwing else { return [] }
        let gap = time - lastStep
        lastStep = time
        dip = previous
        let length = min(max(weinbergK * pow(swing, 0.25), 0.3), 0.95)
        guard gap <= Self.confirmWithin else {
            pending = length
            return []
        }
        defer { pending = nil }
        return pending.map { [$0, length] } ?? [length]
    }
}

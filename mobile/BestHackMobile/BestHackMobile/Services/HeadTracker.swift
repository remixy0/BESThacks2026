import CoreMotion
import Foundation
import Observation

/// Reads head orientation from AirPods (Pro / Max / 3rd gen and later) and reports
/// yaw relative to a "front" set by `calibrate()`.
///
/// AirPods have no compass, so their yaw only means something relative to a moment you chose:
/// calibration says "right now you face the museum's front". After AirPods reconnect that reference is gone,
/// which `session` tells the guide (it changes on every reconnect).
@Observable
final class HeadTracker: NSObject {
    enum Status: Equatable {
        case unsupported
        case denied
        case waitingForHeadphones
        case tracking
    }

    /// Head yaw in radians relative to the calibration. Positive = turned left.
    /// Not observed: it changes ~25 times a second, and the guide polls it.
    @ObservationIgnored private(set) var yaw: Double = 0
    /// Head pitch in radians relative to the calibration. Positive = looking up.
    @ObservationIgnored private(set) var pitch: Double = 0
    /// Called on every motion update with (yaw, pitch), so the 3D sound can turn with your head without waiting
    /// for the guide's next tick.
    @ObservationIgnored var onMotion: ((Double, Double) -> Void)?

    /// Flip to -1 if looking up moves the Look view down (AirPods report pitch with "up" positive).
    static let pitchSign: Double = 1
    private(set) var status: Status = .waitingForHeadphones
    /// Goes up every time AirPods (re)connect and a new reference is taken.
    private(set) var session = 0

    #if !os(visionOS)
    @ObservationIgnored private let manager = CMHeadphoneMotionManager()
    @ObservationIgnored private var reference: CMAttitude?
    @ObservationIgnored private var latest: CMAttitude?
    #endif

    func start() {
        #if os(visionOS)
        status = .unsupported
        #else
        guard manager.isDeviceMotionAvailable else {
            status = .unsupported
            return
        }
        if CMHeadphoneMotionManager.authorizationStatus() == .denied {
            status = .denied
            return
        }
        manager.delegate = self
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let error = error as NSError?, error.domain == CMErrorDomain, error.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                    self.setStatus(.denied)
                    return
                }
                guard let motion else { return }
                self.handle(motion.attitude)
            }
        }
        #endif
    }

    /// Makes the current head direction the new "front". Returns false when AirPods aren't sending motion.
    @discardableResult
    func calibrate() -> Bool {
        #if os(visionOS)
        return false
        #else
        guard status == .tracking, let latest else { return false }
        reference = latest.copy() as? CMAttitude
        yaw = 0
        pitch = 0
        return true
        #endif
    }

    private func setStatus(_ new: Status) {
        if status != new { status = new }
    }

    #if !os(visionOS)
    private func handle(_ attitude: CMAttitude) {
        setStatus(.tracking)
        latest = attitude
        // First sample after connecting becomes a temporary "front" until you calibrate.
        if reference == nil {
            reference = attitude.copy() as? CMAttitude
            session += 1
        }
        guard let reference, let relative = attitude.copy() as? CMAttitude else { return }
        relative.multiply(byInverseOf: reference)
        yaw = relative.yaw
        pitch = relative.pitch * Self.pitchSign
        onMotion?(yaw, pitch)
    }
    #endif
}

#if !os(visionOS)
extension HeadTracker: CMHeadphoneMotionManagerDelegate {
    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            // A new connection has a new reference frame: the old "front" no longer applies.
            self.reference = nil
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            self.setStatus(.waitingForHeadphones)
            self.reference = nil
            self.yaw = 0
            self.pitch = 0
        }
    }
}
#endif

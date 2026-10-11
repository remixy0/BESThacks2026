import CoreGraphics
import Foundation
import simd

/// How the map is shown.
enum MapStyle: String, CaseIterable, Identifiable {
    /// Tilted 3D view from above, like Apple Maps.
    case overview
    /// First person: standing where you are, looking where you face.
    case eyeLevel
    /// Flat floor plan, north up.
    case plan

    var id: Self { self }

    /// Label in the map's style switch.
    var shortTitle: String {
        switch self {
        case .overview: "3D"
        case .eyeLevel: tr("Look", "Widok")
        case .plan: "2D"
        }
    }

    var accessibilityName: String {
        switch self {
        case .overview: tr("3D map", "Mapa 3D")
        case .eyeLevel: tr("Look around at eye level", "Widok z oczu")
        case .plan: tr("Floor plan", "Plan piętra")
        }
    }
}

/// Where the 3D camera should be. Overview orbits a floor point; eye level stands on one.
struct CameraGoal: Equatable {
    /// Overview: the floor point in the middle of the view. Eye level: where you stand.
    var focus: SIMD2<Float>
    /// Overview only: metres from the focus.
    var distance: Float
    /// Radians below the horizon.
    var pitch: Float
    /// Which way the camera looks: 0 = north, positive = turned left.
    var bearing: Float
    /// 0 = overview, 1 = eye level.
    var eyeLevel: Float
}

/// Smoothly follows a `CameraGoal`, frame by frame, and does the 3D <-> screen maths for the map's overlays.
///
/// Not observable on purpose: it is advanced from inside a TimelineView while the view is drawing.
final class MapCameraRig {
    static let eyeHeight: Float = 1.65
    /// Vertical field of view. 75° (was 60°): on a portrait phone that's about 40° across, so you see more around you.
    static let fieldOfView: Float = 75 * .pi / 180

    private(set) var current: CameraGoal
    private var lastTime: Date?

    init(_ goal: CameraGoal) {
        current = goal
    }

    /// True when the camera has (almost) reached the goal.
    func isSettled(at goal: CameraGoal) -> Bool {
        simd_distance(current.focus, goal.focus) < 0.02
            && abs(current.distance - goal.distance) < 0.05
            && abs(current.pitch - goal.pitch) < 0.002
            && abs(MuseumGeometry.wrap(current.bearing - goal.bearing)) < 0.005
            && abs(current.eyeLevel - goal.eyeLevel) < 0.002
    }

    /// Moves part of the way toward the goal. Call once per frame.
    func advance(toward goal: CameraGoal, at time: Date) {
        let dt = Float(min(max(time.timeIntervalSince(lastTime ?? time), 0), 0.1))
        lastTime = time
        guard dt > 0 else { return }
        func ease(_ rate: Float) -> Float { 1 - exp(-rate * dt) }

        // The blend into first person is a little slower, so the swoop down reads well.
        let blend = ease(4.5)
        current.eyeLevel += (goal.eyeLevel - current.eyeLevel) * blend
        current.focus += (goal.focus - current.focus) * ease(current.eyeLevel > 0.5 ? 12 : 7)
        let logDistance = log(max(current.distance, 1)) + (log(max(goal.distance, 1)) - log(max(current.distance, 1))) * ease(8)
        current.distance = exp(logDistance)
        // Turning and tilting follow the AirPods closely (their data is already smooth): a short ease only hides
        // the gaps between their ~25 updates a second.
        current.pitch += (goal.pitch - current.pitch) * ease(current.eyeLevel > 0.5 ? 18 : 9)
        current.bearing = MuseumGeometry.wrap(current.bearing + MuseumGeometry.wrap(goal.bearing - current.bearing) * ease(current.eyeLevel > 0.5 ? 24 : 16))
        if isSettled(at: goal) {
            current = goal
        }
    }

    /// Jumps straight to the goal (first frame).
    func reset(to goal: CameraGoal) {
        current = goal
        lastTime = nil
    }

    // MARK: - Pose

    struct Pose {
        var eye: SIMD3<Float>
        var forward: SIMD3<Float>
        var right: SIMD3<Float>
        var up: SIMD3<Float>
        var target: SIMD3<Float> { eye + forward * 10 }
    }

    /// Camera position and axes for the current state (overview and eye level blended).
    var pose: Pose {
        let c = current
        let flat = MuseumGeometry.forward(yaw: c.bearing)
        let horizontal = SIMD3<Float>(flat.x, 0, flat.y)

        // Overview: orbit around the focus.
        let overPitch = c.pitch
        let overDirection = simd_normalize(horizontal * cos(overPitch) - SIMD3<Float>(0, sin(overPitch), 0))
        let focus3 = SIMD3<Float>(c.focus.x, 0, c.focus.y)
        let overEye = focus3 - overDirection * c.distance

        // Eye level: standing at the focus.
        let eyePitch = c.pitch
        let eyeDirection = simd_normalize(horizontal * cos(eyePitch) - SIMD3<Float>(0, sin(eyePitch), 0))
        let eyeEye = focus3 + SIMD3<Float>(0, Self.eyeHeight, 0)

        let t = smoothstep(c.eyeLevel)
        let eye = overEye + (eyeEye - overEye) * t
        let forward = simd_normalize(overDirection + (eyeDirection - overDirection) * t)
        var right = simd_cross(forward, SIMD3<Float>(0, 1, 0))
        if simd_length(right) < 1e-4 { right = SIMD3<Float>(1, 0, 0) }
        right = simd_normalize(right)
        let up = simd_cross(right, forward)
        return Pose(eye: eye, forward: forward, right: right, up: up)
    }

    private func smoothstep(_ x: Float) -> Float {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    // MARK: - Screen maths

    /// Screen point (in a view of `size`) for a world point, or nil when it's behind the camera.
    /// Also returns the depth in metres.
    func project(_ point: SIMD3<Float>, in size: CGSize) -> (point: CGPoint, depth: Float)? {
        projector(in: size)(point)
    }

    /// Projects many points with one camera pose (work out the pose once per frame, not once per pin).
    func projector(in size: CGSize) -> Projector {
        Projector(pose: pose, size: size, scale: Float(max(size.height, 1) / 2) / tan(Self.fieldOfView / 2))
    }

    struct Projector {
        let pose: Pose
        let size: CGSize
        let scale: Float

        func callAsFunction(_ point: SIMD3<Float>) -> (point: CGPoint, depth: Float)? {
            let d = point - pose.eye
            let z = simd_dot(d, pose.forward)
            guard z > 0.3, size.height > 0 else { return nil }
            let x = simd_dot(d, pose.right)
            let y = simd_dot(d, pose.up)
            return (CGPoint(x: size.width / 2 + CGFloat(x / z * scale), y: size.height / 2 - CGFloat(y / z * scale)), z)
        }
    }
}

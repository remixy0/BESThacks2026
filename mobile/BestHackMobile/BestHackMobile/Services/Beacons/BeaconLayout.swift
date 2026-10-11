import Foundation
import simd

/// Your own beacon layout, typed in on the phone (Settings → Beacon layout and steps).
///
/// For trying the app in any room: hang 4 beacons, measure where they are with a tape measure, type that in, and
/// walk around the room to walk through the virtual museum.
///
/// **Room coordinates** are metres from one corner of the room: stand in that corner facing into the room;
/// `x` = metres to your right, `y` = metres straight ahead.
///
/// **Room → museum:** the calibration point in the room *is* the museum's calibration spot (South Entrance by
/// default), and facing `facing` there means facing the spot's front. `walkScale` stretches the room:
/// at 3×, one metre walked is three metres in the museum.
nonisolated struct BeaconLayout: Codable, Sendable, Equatable {
    struct Beacon: Codable, Sendable, Equatable, Identifiable {
        var id = UUID()
        var name: String
        var major: Int
        var minor: Int
        /// Room metres.
        var x: Float
        var y: Float
        /// RSSI 1 m away from the beacon, in dBm.
        var txPower: Float = BeaconDirectory.Beacon.defaultTxPower

        /// "major:minor", the same id the server's beacons use.
        var key: String { "\(major):\(minor)" }
        var point: SIMD2<Float> { SIMD2(x, y) }
    }

    /// Which way you face at the calibration point, in room terms.
    enum Facing: String, Codable, Sendable, CaseIterable, Identifiable {
        case forward, right, back, left

        var id: String { rawValue }

        /// Counter-clockwise from +y (seen from above), radians.
        var angle: Float {
            switch self {
            case .forward: 0
            case .left: .pi / 2
            case .back: .pi
            case .right: -.pi / 2
            }
        }

        var title: String {
            switch self {
            case .forward: trNow("Forward (+y)", "Do przodu (+y)")
            case .right: trNow("Right (+x)", "W prawo (+x)")
            case .back: trNow("Back (−y)", "Do tyłu (−y)")
            case .left: trNow("Left (−x)", "W lewo (−x)")
            }
        }
    }

    /// Use this layout instead of the server's beacon list.
    var enabled = false
    var beacons: [Beacon] = []
    /// Where you stand to calibrate, in room metres.
    var calibrationX: Float = 2.5
    var calibrationY: Float = 2.5
    var facing: Facing = .forward
    /// Museum metres per metre walked.
    var walkScale: Float = 1
    /// How much higher the beacons hang than the phone (metres). Takes the height out of the distances.
    var beaconHeight: Float = 1

    var calibrationPoint: SIMD2<Float> { SIMD2(calibrationX, calibrationY) }

    /// Room → museum for a calibration spot.
    func frame(spot: CalibrationSpot) -> FloorFrame {
        FloorFrame(spotPaper: FloorFrame.paper(spot.point), spotFrame: calibrationPoint,
                   rotation: MuseumGeometry.wrap(spot.yaw - facing.angle), scale: min(max(walkScale, 0.2), 20))
    }

    func beacon(major: Int, minor: Int) -> Beacon? {
        beacons.first { $0.major == major && $0.minor == minor }
    }

    // MARK: - Saving

    private static let key = "beacons.layout"

    static func load() -> BeaconLayout {
        guard let data = UserDefaults.standard.data(forKey: key),
              let layout = try? JSONDecoder().decode(BeaconLayout.self, from: data) else { return BeaconLayout() }
        return layout
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

/// The floor the position filter works on, and how it maps onto the museum.
///
/// The filter works in "paper" coordinates: metres, x to the right, y up the page (counter-clockwise angles).
/// The museum's own floor points are (x = east, z = south), so museum → paper is (x, −z).
/// - Server beacons: the frame is the museum itself (`.museum`).
/// - Your own layout: the frame is your room (see `BeaconLayout`).
nonisolated struct FloorFrame: Sendable, Equatable {
    /// The calibration spot in museum paper coordinates (east, north).
    var spotPaper: SIMD2<Float>
    /// The same spot in this frame.
    var spotFrame: SIMD2<Float>
    /// Frame → museum rotation, radians, counter-clockwise seen from above.
    var rotation: Float
    /// Museum metres per frame metre.
    var scale: Float

    static let museum = FloorFrame(spotPaper: .zero, spotFrame: .zero, rotation: 0, scale: 1)

    /// Museum floor point (x, z) ↔ paper (east, north). Its own inverse.
    static func paper(_ point: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(point.x, -point.y)
    }

    static func rotate(_ v: SIMD2<Float>, by angle: Float) -> SIMD2<Float> {
        let c = cos(angle), s = sin(angle)
        return SIMD2(v.x * c - v.y * s, v.x * s + v.y * c)
    }

    /// Frame point → museum floor point (x, z).
    func toMuseum(_ point: SIMD2<Float>) -> SIMD2<Float> {
        Self.paper(spotPaper + Self.rotate(point - spotFrame, by: rotation) * scale)
    }

    /// Museum floor point (x, z) → frame point.
    func toFrame(_ point: SIMD2<Float>) -> SIMD2<Float> {
        spotFrame + Self.rotate(Self.paper(point) - spotPaper, by: -rotation) / scale
    }

    /// Unit direction in this frame for a museum yaw (0 = north, positive = turned left).
    func direction(museumYaw yaw: Float) -> SIMD2<Float> {
        let angle = yaw - rotation
        return SIMD2(-sin(angle), cos(angle))
    }
}

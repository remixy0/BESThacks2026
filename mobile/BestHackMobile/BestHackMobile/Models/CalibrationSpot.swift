import Foundation
import simd

/// The known spot you stand on to calibrate, and which way "front" is there.
///
/// Calibrating there tells the app three things at once: where you are (resets the beacon position),
/// which way you face (zeroes the AirPods heading), and how strong each beacon is at that spot
/// (corrects each beacon's signal model).
nonisolated struct CalibrationSpot: Codable, Sendable, Equatable {
    /// Where to stand, said the way you'd tell a visitor, e.g. "the start marker just inside the South Entrance".
    var name: String
    /// Floor-plan point (x, z) in museum metres.
    var point: SIMD2<Float>
    /// Which way "front" is, in degrees: 0 = north (into the museum from the South Entrance), 90 = west, -90 = east.
    var facingDegrees: Float
    /// What you should face, e.g. "into the big hall, toward the Totem Poles".
    var facing: String

    /// Facing as a model yaw (radians, 0 = north, positive = turned left).
    var yaw: Float { MuseumGeometry.wrap(facingDegrees * .pi / 180) }

    static let southEntrance = CalibrationSpot(
        name: "the start marker just inside the South Entrance",
        point: SIMD2(0.2, 56),
        facingDegrees: 0,
        facing: "into the big hall, toward the Totem Poles"
    )

    /// From Secrets.plist (CALIBRATION_POINT = "x, y, facingDegrees"), else the South Entrance.
    static var configured: CalibrationSpot {
        let parts = Secrets.calibrationPoint
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " })
            .compactMap { Float($0) }
        guard parts.count >= 2 else { return .southEntrance }
        let flip: Float = Secrets.routeYAxis == "north" ? -1 : 1
        var spot = CalibrationSpot.southEntrance
        spot.point = SIMD2(parts[0], parts[1] * flip)
        if parts.count >= 3 { spot.facingDegrees = parts[2] }
        if spot.point != CalibrationSpot.southEntrance.point {
            spot.name = "the calibration marker"
            spot.facing = "the way the arrow on the marker points"
        }
        return spot
    }
}

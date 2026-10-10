import Foundation
import simd

/// Where each BLE beacon hangs, as sent by the backend (`GET <BACKEND_URL>/beacons`).
///
/// Accepted shapes (numbers or numeric strings, keys in snake_case or camelCase):
///
///     [{"major": 1, "minor": 3, "x": 4.5, "y": 50.0, "tx_power": -59}, ...]
///     {"beacons": [...], "calibration": {"x": 0.2, "y": 56, "facing_degrees": 0}}
///     {"id": "1:3", "position": [4.5, 0, 50.0]}      // id = "major:minor", position = [x, height, z]
///     {"id": 3, "x": 4.5, "z": 50.0}                  // a plain number id = the beacon's minor
///
/// Coordinates are museum metres like everything else: x = east, y = the model's z (south),
/// unless ROUTE_Y_AXIS = "north". `tx_power` is the RSSI measured 1 m from the beacon (default -59 dBm).
nonisolated struct BeaconDirectory: Codable, Sendable, Equatable {
    struct Beacon: Codable, Sendable, Equatable, Identifiable {
        /// "major:minor" (or "*:minor" when the backend only gives a minor).
        var id: String { "\(major.map(String.init) ?? "*"):\(minor)" }
        var major: Int?
        var minor: Int
        var name: String?
        var point: SIMD2<Float>
        /// RSSI at 1 m, in dBm.
        var txPower: Float

        static let defaultTxPower: Float = -59
    }

    var beacons: [Beacon]
    /// The backend may also say where to calibrate.
    var calibration: CalibrationSpot?

    static let empty = BeaconDirectory(beacons: [], calibration: nil)

    /// The beacon a ranging reading came from.
    func beacon(major: Int, minor: Int) -> Beacon? {
        beacons.first { $0.major == major && $0.minor == minor }
            ?? beacons.first { $0.major == nil && $0.minor == minor }
    }

    // MARK: - Decoding

    enum DecodeError: LocalizedError {
        case noBeacons
        var errorDescription: String? { "The server's beacon list has no beacons with a position and an id." }
    }

    static func decode(_ data: Data, northUp: Bool = Secrets.routeYAxis == "north") throws -> BeaconDirectory {
        let json = try JSONSerialization.jsonObject(with: data)
        let flip: Float = northUp ? -1 : 1
        var list: [Any] = []
        var calibration: CalibrationSpot?

        if let array = json as? [Any] {
            list = array
        } else if let object = json as? [String: Any] {
            for key in ["beacons", "items", "data", "results", "anchors"] {
                if let array = object[key] as? [Any] { list = array; break }
            }
            for key in ["calibration", "calibration_point", "calibrationPoint", "start"] {
                if let spot = object[key] as? [String: Any], let point = point(in: spot, flip: flip) {
                    calibration = CalibrationSpot(
                        name: (spot["name"] as? String) ?? "the calibration marker",
                        point: point,
                        facingDegrees: number(spot, ["facing_degrees", "facingDegrees", "yaw_degrees", "yawDegrees", "yaw", "heading"]) ?? 0,
                        facing: (spot["facing"] as? String) ?? "the way the arrow on the marker points"
                    )
                    break
                }
            }
        }

        let beacons = list.compactMap { ($0 as? [String: Any]).flatMap { beacon(from: $0, flip: flip) } }
        guard !beacons.isEmpty else { throw DecodeError.noBeacons }
        return BeaconDirectory(beacons: beacons, calibration: calibration)
    }

    private static func beacon(from object: [String: Any], flip: Float) -> Beacon? {
        guard let point = point(in: object, flip: flip) else { return nil }
        var major = number(object, ["major"]).map { Int($0) }
        var minor = number(object, ["minor"]).map { Int($0) }

        if minor == nil {
            let rawID = object["id"] ?? object["beacon_id"] ?? object["beaconId"]
            if let text = rawID as? String {
                let parts = text.split(whereSeparator: { ":-_/.".contains($0) }).compactMap { Int($0) }
                if parts.count >= 2 {
                    major = parts[parts.count - 2]
                    minor = parts[parts.count - 1]
                } else if let only = parts.first {
                    minor = only
                }
            } else if let value = rawID as? NSNumber {
                minor = value.intValue
            }
        }
        guard let minor else { return nil }

        let tx = number(object, ["tx_power", "txPower", "measured_power", "measuredPower", "rssi_1m", "rssi_at_1m", "rssiAt1m"])
        return Beacon(
            major: major,
            minor: minor,
            name: (object["name"] as? String) ?? (object["label"] as? String),
            point: point,
            txPower: tx.map { $0 > 0 ? -$0 : $0 } ?? Beacon.defaultTxPower
        )
    }

    /// (x, z) from "x"/"y" (or "z"), or "position"/"coordinates" as [x, z] or [x, height, z].
    private static func point(in object: [String: Any], flip: Float) -> SIMD2<Float>? {
        if let x = number(object, ["x"]), let y = number(object, ["y", "z"]) {
            return SIMD2(x, y * flip)
        }
        for key in ["position", "coordinates", "pos", "location"] {
            if let list = object[key] as? [Any] {
                let values = list.compactMap { number($0) }
                if values.count >= 3 { return SIMD2(values[0], values[2] * flip) }
                if values.count == 2 { return SIMD2(values[0], values[1] * flip) }
            }
            if let nested = object[key] as? [String: Any], let x = number(nested, ["x"]), let y = number(nested, ["y", "z"]) {
                return SIMD2(x, y * flip)
            }
        }
        return nil
    }

    private static func number(_ object: [String: Any], _ keys: [String]) -> Float? {
        for key in keys {
            if let value = number(object[key]) { return value }
        }
        return nil
    }

    private static func number(_ value: Any?) -> Float? {
        if let number = value as? NSNumber { return number.floatValue }
        if let text = value as? String { return Float(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}

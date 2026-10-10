import CoreLocation
import Foundation
import Observation

/// Listens for the museum's BLE beacons and reports how strong each one is, about once a second.
///
/// The beacons are iBeacons that all share one UUID (set in the ESP32 firmware) and differ by major/minor.
/// iPhones only let apps read iBeacon adverts through Core Location "ranging" (Core Bluetooth never sees them),
/// which is why the app asks for location access. GPS itself is not used.
@Observable
final class BeaconScanner: NSObject, CLLocationManagerDelegate {
    /// Must match `BEACON_UUID` in the beacon firmware.
    static let uuid = UUID(uuidString: "DFB76639-2B31-46CB-AAD1-63470563632E")!

    nonisolated struct Reading: Sendable {
        let major: Int
        let minor: Int
        /// dBm, e.g. -67.
        let rssi: Int
    }

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isRanging = false
    private(set) var problem: String?

    /// Called with each ranging round (about 1 per second), on the main actor.
    @ObservationIgnored var onReadings: (([Reading]) -> Void)?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var wantsRanging = false

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        manager.delegate = self
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// Shows the system "Allow location?" prompt if it hasn't been answered yet.
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        wantsRanging = true
        #if os(iOS)
        guard CLLocationManager.isRangingAvailable() else {
            problem = tr("This device can't read Bluetooth beacons.", "To urządzenie nie odczytuje beaconów Bluetooth.")
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()   // ranging starts when the answer comes back
        case .authorizedWhenInUse, .authorizedAlways:
            if !isRanging {
                manager.startRangingBeacons(satisfying: constraint)
                isRanging = true
                problem = nil
            }
        default:
            problem = tr("Location access is off, so the beacons can't be read. Turn it on in the Settings app.", "Dostęp do lokalizacji jest wyłączony, więc beacony nie działają. Włącz go w Ustawieniach.")
        }
        #else
        problem = tr("Beacons only work on iPhone.", "Beacony działają tylko na iPhonie.")
        #endif
    }

    func stop() {
        wantsRanging = false
        #if os(iOS)
        if isRanging { manager.stopRangingBeacons(satisfying: constraint) }
        #endif
        isRanging = false
    }

    #if os(iOS)
    @ObservationIgnored private lazy var constraint = CLBeaconIdentityConstraint(uuid: Self.uuid)

    // Core Location calls these on the main thread (the manager was made there).

    nonisolated func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon],
                                     satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        // rssi 0 = listed but not heard this round.
        let readings = beacons.compactMap { beacon -> Reading? in
            guard beacon.rssi != 0 else { return nil }
            return Reading(major: beacon.major.intValue, minor: beacon.minor.intValue, rssi: beacon.rssi)
        }
        MainActor.assumeIsolated {
            self.onReadings?(readings)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint,
                                     error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            self.problem = tr("Beacon scanning stopped: ", "Skanowanie beaconów zatrzymane: ") + message
            self.isRanging = false
        }
    }
    #endif

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard status != self.authorization || !self.isRanging else { return }
            self.authorization = status
            if self.wantsRanging { self.start() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Beacons] \(error.localizedDescription)")
    }
}

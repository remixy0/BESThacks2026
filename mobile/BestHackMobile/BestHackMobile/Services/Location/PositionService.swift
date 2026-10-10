import Foundation
import Observation
import simd

/// Where you are in the museum, from the BLE beacons. (No GPS.)
///
/// - Beacon positions come from the backend (and are saved on the device for next time).
/// - `BeaconScanner` hears the beacons about once a second, `BeaconPositioner` turns their signal strengths into
///   a point, and a light filter here takes out the jumps (BLE positions wobble by a few metres).
/// - Until a beacon is heard you stay where you calibrated (or wherever you were last seen).
/// - Demo: the guide can walk you along the route by itself (Settings → Demo walk).
@Observable
final class PositionService {
    enum Source: Equatable {
        case beacons, lastKnown, demo
    }

    let scanner = BeaconScanner()

    /// Your filtered position on the floor plan (x, z). With beacons it moves about once a second;
    /// the guide smooths it further for the map.
    private(set) var position: SIMD2<Float>
    private(set) var source: Source = .lastKnown
    /// Rough error in metres, when known.
    private(set) var accuracy: Float?
    /// Known beacons heard in the last few seconds.
    private(set) var beaconsHeard = 0
    /// Beacons with our UUID that aren't in the server's list ("major:minor").
    private(set) var unknownBeacons: [String] = []
    private(set) var directory: BeaconDirectory
    private(set) var directoryError: String?
    private(set) var isLoadingDirectory = false
    /// How many beacons the last calibration could use.
    private(set) var calibratedBeacons = 0

    /// Where to stand to calibrate: from the server if it says, else Secrets.plist, else the South Entrance.
    var spot: CalibrationSpot { directory.calibration ?? .configured }

    @ObservationIgnored private var positioner: BeaconPositioner
    @ObservationIgnored private var anchors: [String: BeaconPositioner.Anchor] = [:]
    @ObservationIgnored private var lastFixTime: TimeInterval?
    @ObservationIgnored private var demoActive = false
    @ObservationIgnored private var unknownSet: Set<String> = []

    private enum Keys {
        static let directory = "beacons.directory"
        static let offsets = "beacons.offsets"
    }

    init() {
        let cached = Self.loadCachedDirectory()
        directory = cached
        positioner = BeaconPositioner(offsets: Self.loadOffsets())
        position = (cached.calibration ?? .configured).point
        rebuildAnchors()
        scanner.onReadings = { [weak self] readings in
            self?.handle(readings)
        }
    }

    // MARK: - Control

    func start() {
        scanner.start()
    }

    func stop() {
        scanner.stop()
    }

    func requestPermission() {
        scanner.requestPermission()
    }

    /// Fetches the beacon positions from the backend. Keeps the saved list if that fails.
    func loadDirectory(using backend: BackendClient?) async {
        guard let backend else {
            directoryError = directory.beacons.isEmpty ? tr("No server is set, so the app doesn't know where the beacons are.", "Nie ustawiono serwera, więc aplikacja nie zna pozycji beaconów.") : nil
            return
        }
        guard !isLoadingDirectory else { return }
        isLoadingDirectory = true
        defer { isLoadingDirectory = false }
        do {
            let loaded = try await backend.beacons()
            directory = loaded
            directoryError = nil
            rebuildAnchors()
            if let data = try? JSONEncoder().encode(loaded) {
                UserDefaults.standard.set(data, forKey: Keys.directory)
            }
            print("[Beacons] \(loaded.beacons.count) beacon positions from the server")
        } catch {
            let saved = directory.beacons.isEmpty ? "" : tr(" Using the \(directory.beacons.count) saved beacon positions.", " Używam zapisanych pozycji (\(directory.beacons.count)).")
            directoryError = tr("Couldn't load the beacon positions: ", "Nie udało się wczytać pozycji beaconów: ") + error.localizedDescription + saved
        }
    }

    /// You're standing on the calibration spot: put you there and correct each beacon's signal model.
    /// Returns how many beacons were used.
    @discardableResult
    func calibrate() -> Int {
        let now = Self.now
        let used = positioner.calibrate(at: spot.point, anchors: anchors, at: now)
        UserDefaults.standard.set(positioner.offsets.mapValues { Double($0) }, forKey: Keys.offsets)
        demoActive = false
        position = spot.point
        accuracy = used > 0 ? 1.5 : nil
        lastFixTime = now
        calibratedBeacons = used
        source = used > 0 ? .beacons : .lastKnown
        return used
    }

    // MARK: - Demo

    /// Demo walk: the guide moves you itself.
    func setDemo(position newPosition: SIMD2<Float>) {
        demoActive = true
        if source != .demo { source = .demo }
        position = Self.clamped(newPosition)
    }

    func endDemo() {
        guard demoActive else { return }
        demoActive = false
        source = .lastKnown
    }

    // MARK: - Status

    var isHealthy: Bool { source != .lastKnown }

    var statusText: String {
        switch source {
        case .beacons:
            let count = tr("\(beaconsHeard) beacon\(beaconsHeard == 1 ? "" : "s")",
                           "beacony: \(beaconsHeard)")
            return accuracy.map { "\(count) · ±\(Int($0.rounded())) m" } ?? count
        case .demo:
            return tr("Demo walk", "Spacer demo")
        case .lastKnown:
            if let problem = scanner.problem { return problem }
            if directory.beacons.isEmpty { return tr("The beacon positions haven't loaded yet", "Pozycje beaconów jeszcze się nie wczytały") }
            if !unknownBeacons.isEmpty { return tr("Beacons heard, but they aren't in the server's list", "Słychać beacony, ale nie ma ich na liście z serwera") }
            return tr("Looking for beacons…", "Szukam beaconów…")
        }
    }

    /// Points of beacons that read very close right now (within `metres`). A beacon hanging at an exhibit then
    /// means "you're at that exhibit", even if the position estimate wobbles.
    func closeBeaconPoints(within metres: Float = 2) -> [SIMD2<Float>] {
        positioner.sightings(at: Self.now, anchors: anchors).compactMap { sighting in
            guard sighting.secondsAgo < 3, let distance = sighting.distance, distance <= metres else { return nil }
            return anchors[sighting.id]?.point
        }
    }

    /// What each beacon looks like right now (for Settings → Beacons).
    func sightings() -> [BeaconPositioner.Sighting] {
        positioner.sightings(at: Self.now, anchors: anchors)
    }

    var pathLossExponent: Float {
        get { positioner.pathLossExponent }
        set { positioner.pathLossExponent = min(max(newValue, 1.6), 4) }
    }

    // MARK: - Readings

    private func handle(_ readings: [BeaconScanner.Reading]) {
        let now = Self.now
        var unknown = Set<String>()
        for reading in readings {
            guard let beacon = directory.beacon(major: reading.major, minor: reading.minor) else {
                unknown.insert("\(reading.major):\(reading.minor)")
                continue
            }
            positioner.add(id: beacon.id, rssi: Float(reading.rssi), at: now)
        }
        positioner.forget(before: now - 30)
        if unknown != unknownSet {
            unknownSet = unknown
            unknownBeacons = unknown.sorted()
        }
        let live = positioner.liveCount(at: now)
        if live != beaconsHeard { beaconsHeard = live }

        guard !demoActive else { return }
        guard let fix = positioner.fix(anchors: anchors, near: position, at: now) else {
            if source == .beacons, now - (lastFixTime ?? 0) > 6 { source = .lastKnown }
            return
        }

        // Don't let one noisy second throw you across the room: at most a brisk walk plus a little noise.
        let dt = Float(min(max(now - (lastFixTime ?? (now - 1)), 0.2), 5))
        lastFixTime = now
        var delta = fix.point - position
        let maxStep = 1.8 * dt + 1.5
        let length = simd_length(delta)
        if length > maxStep { delta *= maxStep / length }
        // Trust good fixes more.
        let gain = min(max(0.65 / (1 + fix.accuracy / 4), 0.15), 0.65)
        position = Self.clamped(position + delta * gain)
        if accuracy.map({ abs($0 - fix.accuracy) > 0.5 }) ?? true { accuracy = fix.accuracy }
        if source != .beacons { source = .beacons }
    }

    private func rebuildAnchors() {
        var result: [String: BeaconPositioner.Anchor] = [:]
        for beacon in directory.beacons {
            result[beacon.id] = BeaconPositioner.Anchor(id: beacon.id, point: beacon.point, txPower: beacon.txPower)
        }
        anchors = result
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private static func clamped(_ point: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(min(max(point.x, MuseumInfo.bounds.x.lowerBound), MuseumInfo.bounds.x.upperBound),
              min(max(point.y, MuseumInfo.bounds.z.lowerBound), MuseumInfo.bounds.z.upperBound))
    }

    private static func loadCachedDirectory() -> BeaconDirectory {
        guard let data = UserDefaults.standard.data(forKey: Keys.directory),
              let directory = try? JSONDecoder().decode(BeaconDirectory.self, from: data) else { return .empty }
        return directory
    }

    private static func loadOffsets() -> [String: Float] {
        let raw = UserDefaults.standard.dictionary(forKey: Keys.offsets) as? [String: Double] ?? [:]
        return raw.mapValues { Float($0) }
    }
}

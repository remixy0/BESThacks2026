import Foundation
import Observation
import simd

/// Where you are in the museum: BLE beacons + your steps. (No GPS.)
///
/// - **Beacons:** from the backend (saved on the device for next time), or your own layout typed in on the phone
///   (`layout`, Settings → Beacon layout and steps). `BeaconScanner` hears them about once a second.
/// - **Steps:** `MotionTracker` spots each step and how the phone turned; the heading comes from the phone (held in
///   front of you) or your AirPods, both lined up with the museum at calibration.
/// - **Fusion:** `PositionFilter` (a Kalman filter) moves you one step at a time and lets every beacon distance pull
///   you toward the right place. Steps make walking smooth and immediate; beacons stop the steps from drifting.
/// - The filter works in a `FloorFrame`: the museum for server beacons, your room for your own layout.
/// - Demo: the guide can walk you along the route by itself (Settings → Demo walk).
@Observable
final class PositionService {
    enum Source: Equatable {
        case beacons, steps, lastKnown, demo
    }

    /// Where the walking direction comes from.
    enum HeadingSource: String, CaseIterable, Identifiable {
        /// The phone while you hold it in front of you, else AirPods.
        case auto
        case phone
        case airPods

        var id: String { rawValue }

        var title: String {
            switch self {
            case .auto: tr("Automatic", "Automatycznie")
            case .phone: tr("Phone", "Telefon")
            case .airPods: tr("AirPods", "AirPodsy")
            }
        }
    }

    /// A beacon heard recently, known or not (for picking beacons in the layout editor).
    nonisolated struct Heard: Sendable, Identifiable {
        let major: Int
        let minor: Int
        let rssi: Int
        let time: TimeInterval
        var id: String { "\(major):\(minor)" }
    }

    let scanner = BeaconScanner()
    let motion = MotionTracker()

    /// Your position on the floor plan (x, z). Moves with every step and every beacon round;
    /// the guide smooths it further for the map.
    private(set) var position: SIMD2<Float>
    private(set) var source: Source = .lastKnown
    /// Rough error in museum metres, when known.
    private(set) var accuracy: Float?
    /// Known beacons heard in the last few seconds.
    private(set) var beaconsHeard = 0
    /// Beacons with our UUID that aren't in the list in use ("major:minor").
    private(set) var unknownBeacons: [String] = []
    private(set) var directory: BeaconDirectory
    private(set) var directoryError: String?
    private(set) var isLoadingDirectory = false
    /// How many beacons the last calibration could use.
    private(set) var calibratedBeacons = 0
    /// The phone's heading is lined up with the museum (calibrated while the motion sensors ran, not restarted since).
    private(set) var phoneHeadingCalibrated = false

    /// Your own beacon layout. When it's on, it's used instead of the server's list.
    var layout: BeaconLayout {
        didSet {
            guard layout != oldValue else { return }
            layout.save()
            rebuildAnchors()
            if layout.enabled != oldValue.enabled {
                // Same place, new frame: start the filter again from where you are.
                filter.reset(to: frame.toFrame(position), sigma: 3)
                lastPredict = Self.now
            }
            publish()
        }
    }

    /// Use steps from the motion sensors.
    var useMotion = UserDefaults.standard.object(forKey: "position.motion") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(useMotion, forKey: "position.motion")
            updateMotion()
        }
    }

    var headingSource = HeadingSource(rawValue: UserDefaults.standard.string(forKey: "position.headingSource") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(headingSource.rawValue, forKey: "position.headingSource") }
    }

    /// Multiplies the estimated step length (0.7…1.3). Raise it if you move too little on the map.
    var stepLengthFactor = UserDefaults.standard.object(forKey: "position.stepFactor") as? Float ?? 1 {
        didSet { UserDefaults.standard.set(stepLengthFactor, forKey: "position.stepFactor") }
    }

    /// Your AirPods heading (museum yaw), when they're calibrated. Set by the guide.
    @ObservationIgnored var headHeading: (() -> Float?)?

    /// Where to stand to calibrate: from the server if it says, else Secrets.plist, else the South Entrance.
    var spot: CalibrationSpot { directory.calibration ?? .configured }

    var usesLayout: Bool { layout.enabled }

    /// How many beacons the list in use has.
    var activeBeaconCount: Int { usesLayout ? layout.beacons.count : directory.beacons.count }

    /// The floor the filter works on: your room with your own layout, else the museum.
    var frame: FloorFrame { usesLayout ? layout.frame(spot: spot) : .museum }

    /// Your position in the frame (room metres with your own layout). Not observed; screens poll it.
    var framePosition: SIMD2<Float> { filter.isInitialized ? filter.point : frame.toFrame(position) }

    /// Rough error in frame metres.
    var frameAccuracy: Float? { filter.isInitialized ? filter.accuracy : nil }

    /// Which heading the last step used ("phone", "AirPods") or nil when it had none. Not observed.
    @ObservationIgnored private(set) var lastStepHeading: HeadingSource?

    @ObservationIgnored private var positioner: BeaconPositioner
    /// Beacon positions in frame coordinates, by "major:minor".
    @ObservationIgnored private var anchors: [String: BeaconPositioner.Anchor] = [:]
    @ObservationIgnored private var filter = PositionFilter()
    @ObservationIgnored private var lastPredict: TimeInterval?
    @ObservationIgnored private var lastBeaconFix: TimeInterval?
    @ObservationIgnored private var lastStepTime: TimeInterval = -100
    @ObservationIgnored private var rejectedRounds = 0
    @ObservationIgnored private var phoneYawOffset: Float?
    @ObservationIgnored private var phoneSession = -1
    @ObservationIgnored private var demoActive = false
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var unknownSet: Set<String> = []
    @ObservationIgnored private var heard: [String: Heard] = [:]
    @ObservationIgnored private var measuring: (key: String, samples: [Int])?

    private enum Keys {
        static let directory = "beacons.directory"
        static let offsets = "beacons.offsets"
    }

    init() {
        let cached = Self.loadCachedDirectory()
        directory = cached
        layout = BeaconLayout.load()
        positioner = BeaconPositioner(offsets: Self.loadOffsets())
        position = (cached.calibration ?? .configured).point
        rebuildAnchors()
        filter.reset(to: frame.toFrame(position), sigma: 4)
        scanner.onReadings = { [weak self] readings in
            self?.handle(readings)
        }
        motion.onStep = { [weak self] step in
            self?.handle(step)
        }
    }

    // MARK: - Control

    func start() {
        isStarted = true
        scanner.start()
        updateMotion()
    }

    func stop() {
        isStarted = false
        scanner.stop()
        updateMotion()
    }

    func requestPermission() {
        scanner.requestPermission()
    }

    private func updateMotion() {
        if isStarted, useMotion {
            motion.start()
        } else {
            motion.stop()
        }
    }

    /// Fetches the beacon positions from the backend. Keeps the saved list if that fails.
    func loadDirectory(using backend: BackendClient?) async {
        guard let backend else {
            directoryError = directory.beacons.isEmpty && !usesLayout ? tr("No server is set, so the app doesn't know where the beacons are.", "Nie ustawiono serwera, więc aplikacja nie zna pozycji beaconów.") : nil
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
            // With your own layout the server's list doesn't matter.
            guard !usesLayout else { return }
            let saved = directory.beacons.isEmpty ? "" : tr(" Using the \(directory.beacons.count) saved beacon positions.", " Używam zapisanych pozycji (\(directory.beacons.count)).")
            directoryError = tr("Couldn't load the beacon positions: ", "Nie udało się wczytać pozycji beaconów: ") + error.localizedDescription + saved
        }
    }

    /// You're standing on the calibration spot, facing its front: put you there, correct each beacon's signal model
    /// and line the phone's heading up with the museum. Returns how many beacons were used.
    @discardableResult
    func calibrate() -> Int {
        let now = Self.now
        let spotPoint = frame.toFrame(spot.point)
        let used = positioner.calibrate(at: spotPoint, anchors: anchors, at: now)
        UserDefaults.standard.set(positioner.offsets.mapValues { Double($0) }, forKey: Keys.offsets)
        demoActive = false
        filter.reset(to: spotPoint, sigma: 0.5)
        lastPredict = now
        rejectedRounds = 0
        if motion.isRunning {
            phoneYawOffset = MuseumGeometry.wrap(spot.yaw - motion.yaw)
            phoneSession = motion.session
            phoneHeadingCalibrated = true
        } else {
            phoneYawOffset = nil
            phoneHeadingCalibrated = false
        }
        position = Self.clamped(spot.point)
        accuracy = 0.5 * frame.scale
        lastBeaconFix = now
        calibratedBeacons = used
        source = used > 0 ? .beacons : (useMotion ? .steps : .lastKnown)
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
        filter.reset(to: frame.toFrame(position), sigma: 2)
        lastPredict = Self.now
        source = .lastKnown
    }

    // MARK: - Your own layout

    /// Adds a beacon (placed a little away from the others) and returns its id.
    @discardableResult
    func addLayoutBeacon(major: Int = 1, minor: Int? = nil) -> UUID {
        let used = Set(layout.beacons.map(\.minor))
        let nextMinor = minor ?? ((1...99).first { !used.contains($0) } ?? 1)
        let corners: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(5, 0), SIMD2(5, 5), SIMD2(0, 5)]
        let place = layout.beacons.count < corners.count ? corners[layout.beacons.count] : SIMD2(2.5, 2.5)
        let beacon = BeaconLayout.Beacon(name: tr("Beacon \(layout.beacons.count + 1)", "Beacon \(layout.beacons.count + 1)"),
                                         major: major, minor: nextMinor, x: place.x, y: place.y)
        layout.beacons.append(beacon)
        return beacon.id
    }

    /// Quick start: the beacons heard right now (strongest first, up to 4), at the corners of a 5 × 5 m square.
    /// Without any heard, four placeholders (major 1, minor 1–4). Then fix the positions to match your room.
    func addHeardBeacons() {
        let known = Set(layout.beacons.map(\.key))
        let candidates = heardBeacons().filter { !known.contains($0.id) }.prefix(4)
        if candidates.isEmpty {
            for _ in 0..<max(0, 4 - layout.beacons.count) { addLayoutBeacon() }
        } else {
            for beacon in candidates where layout.beacons.count < 8 {
                addLayoutBeacon(major: beacon.major, minor: beacon.minor)
            }
        }
    }

    func updateLayoutBeacon(_ beacon: BeaconLayout.Beacon) {
        guard let index = layout.beacons.firstIndex(where: { $0.id == beacon.id }) else { return }
        if layout.beacons[index] != beacon { layout.beacons[index] = beacon }
    }

    func removeLayoutBeacon(id: UUID) {
        layout.beacons.removeAll { $0.id == id }
    }

    /// Every beacon with our UUID heard in the last 10 seconds, strongest first.
    func heardBeacons() -> [Heard] {
        let now = Self.now
        return heard.values.filter { now - $0.time < 10 }.sorted { $0.rssi > $1.rssi }
    }

    /// Stand 1 m from the beacon: averages its signal for a few seconds. Returns the median RSSI (dBm), or nil when
    /// it wasn't heard enough.
    func measurePower(major: Int, minor: Int, seconds: Double = 5) async -> Float? {
        let key = "\(major):\(minor)"
        measuring = (key, [])
        try? await Task.sleep(for: .seconds(seconds))
        let samples = measuring?.key == key ? measuring?.samples ?? [] : []
        measuring = nil
        guard samples.count >= 2 else { return nil }
        let sorted = samples.sorted()
        return Float(sorted[sorted.count / 2])
    }

    // MARK: - Status

    var isHealthy: Bool { source != .lastKnown }

    var statusText: String {
        switch source {
        case .beacons:
            let count = tr("\(beaconsHeard) beacon\(beaconsHeard == 1 ? "" : "s")",
                           "beacony: \(beaconsHeard)")
            let steps = motion.isRunning ? tr(" + steps", " + kroki") : ""
            return (accuracy.map { "\(count)\(steps) · ±\(Int($0.rounded())) m" } ?? count + steps)
        case .steps:
            return tr("Steps only (no beacons heard)", "Tylko kroki (nie słychać beaconów)")
        case .demo:
            return tr("Demo walk", "Spacer demo")
        case .lastKnown:
            if let problem = scanner.problem { return problem }
            if usesLayout, layout.beacons.isEmpty { return tr("Add your beacons in Settings › Beacon layout", "Dodaj beacony w Ustawieniach › Układ beaconów") }
            if !usesLayout, directory.beacons.isEmpty { return tr("The beacon positions haven't loaded yet", "Pozycje beaconów jeszcze się nie wczytały") }
            if !unknownBeacons.isEmpty {
                return usesLayout ? tr("Beacons heard, but they aren't in your layout", "Słychać beacony, ale nie ma ich w Twoim układzie")
                                  : tr("Beacons heard, but they aren't in the server's list", "Słychać beacony, ale nie ma ich na liście z serwera")
            }
            return tr("Looking for beacons…", "Szukam beaconów…")
        }
    }

    /// Points of beacons that read very close right now (within `metres`). A beacon hanging at an exhibit then
    /// means "you're at that exhibit", even if the position estimate wobbles. (Not for your own room layout:
    /// those beacons hang in your room, not at the exhibits.)
    func closeBeaconPoints(within metres: Float = 2) -> [SIMD2<Float>] {
        guard !usesLayout else { return [] }
        let frame = self.frame
        return positioner.sightings(at: Self.now, anchors: anchors).compactMap { sighting in
            guard sighting.secondsAgo < 3, let distance = sighting.distance, distance <= metres,
                  let anchor = anchors[sighting.id] else { return nil }
            return frame.toMuseum(anchor.point)
        }
    }

    /// What each beacon looks like right now (for the beacon screens).
    func sightings() -> [BeaconPositioner.Sighting] {
        positioner.sightings(at: Self.now, anchors: anchors)
    }

    /// A beacon's position in the frame, by "major:minor".
    func anchorPoint(id: String) -> SIMD2<Float>? {
        anchors[id]?.point
    }

    /// Distance along the floor from a measured straight-line distance (the beacon hangs higher than the phone).
    func floorDistance(_ distance: Float) -> Float {
        let height = max(layout.beaconHeight, 0)
        return sqrt(max(distance * distance - height * height, 0.09))
    }

    var pathLossExponent: Float {
        get { positioner.pathLossExponent }
        set { positioner.pathLossExponent = min(max(newValue, 1.6), 4) }
    }

    /// The walking direction right now (museum yaw), as the next step would use it.
    func currentHeading() -> StepHeading? {
        heading(heldInFront: motion.heldInFront, phoneYaw: motion.yaw)
    }

    // MARK: - Beacons

    private func handle(_ readings: [BeaconScanner.Reading]) {
        let now = Self.now
        var unknown = Set<String>()
        var fresh = Set<String>()
        for reading in readings {
            let key = "\(reading.major):\(reading.minor)"
            heard[key] = Heard(major: reading.major, minor: reading.minor, rssi: reading.rssi, time: now)
            if measuring?.key == key { measuring?.samples.append(reading.rssi) }
            guard let id = anchorID(major: reading.major, minor: reading.minor) else {
                unknown.insert(key)
                continue
            }
            positioner.add(id: id, rssi: Float(reading.rssi), at: now)
            fresh.insert(id)
        }
        heard = heard.filter { now - $0.value.time < 30 }
        positioner.forget(before: now - 30)
        if unknown != unknownSet {
            unknownSet = unknown
            unknownBeacons = unknown.sorted()
        }
        let live = positioner.liveCount(at: now)
        if live != beaconsHeard { beaconsHeard = live }

        guard !demoActive else { return }

        // This round's distances, nearest first (the six nearest are plenty; far ones mostly add noise).
        var ranges: [(point: SIMD2<Float>, distance: Float)] = []
        for sighting in positioner.sightings(at: now, anchors: anchors) where fresh.contains(sighting.id) {
            guard let anchor = anchors[sighting.id], let distance = sighting.distance else { continue }
            ranges.append((anchor.point, floorDistance(distance)))
        }
        ranges.sort { $0.distance < $1.distance }
        if ranges.count > 6 { ranges.removeLast(ranges.count - 6) }

        guard !ranges.isEmpty else {
            if source == .beacons, now - (lastBeaconFix ?? 0) > 6 {
                source = motion.isRunning && phoneOrHeadHeadingAvailable ? .steps : .lastKnown
            }
            return
        }

        predict(to: now)
        var accepted = 0
        for range in ranges {
            // Signal-strength distances get worse the further away the beacon is.
            let sigma = 0.6 + 0.35 * range.distance
            if filter.range(to: range.point, distance: range.distance, sigma: sigma) { accepted += 1 }
        }
        // Several rounds in a row where the beacons all disagree with the guess: the guess is lost. Start over
        // from the beacons alone.
        if ranges.count >= 2 {
            rejectedRounds = accepted == 0 ? rejectedRounds + 1 : 0
            if rejectedRounds >= 4, let fix = positioner.fix(anchors: anchors, near: filter.point, at: now) {
                filter.reset(to: fix.point, sigma: max(fix.accuracy, 2))
                rejectedRounds = 0
                print("[Position] beacons disagreed for a while: restarted from the beacons")
            }
        }
        keepInsideRoom()
        lastBeaconFix = now
        publish()
        if source != .beacons { source = .beacons }
    }

    /// "major:minor" of a heard beacon in the list in use, or nil when it isn't in it.
    private func anchorID(major: Int, minor: Int) -> String? {
        if usesLayout {
            return layout.beacon(major: major, minor: minor)?.key
        }
        return directory.beacon(major: major, minor: minor)?.id
    }

    private func rebuildAnchors() {
        var result: [String: BeaconPositioner.Anchor] = [:]
        if usesLayout {
            for beacon in layout.beacons where result[beacon.key] == nil {
                result[beacon.key] = BeaconPositioner.Anchor(id: beacon.key, point: beacon.point, txPower: beacon.txPower)
            }
        } else {
            for beacon in directory.beacons {
                result[beacon.id] = BeaconPositioner.Anchor(id: beacon.id, point: FloorFrame.museum.toFrame(beacon.point), txPower: beacon.txPower)
            }
        }
        anchors = result
    }

    // MARK: - Steps

    private func handle(_ step: MotionTracker.Step) {
        let now = Self.now
        lastStepTime = now
        guard useMotion, !demoActive else { return }
        predict(to: now)
        let length = step.length * min(max(stepLengthFactor, 0.5), 1.6)
        if let walk = heading(heldInFront: step.heldInFront, phoneYaw: step.yaw) {
            filter.step(length: length, direction: frame.direction(museumYaw: walk.yaw),
                        sigmaLength: 0.15 * length + 0.05, sigmaAngle: walk.sigma)
            lastStepHeading = walk.source
        } else {
            // Walking, but which way is unknown: just less sure (the beacons decide).
            filter.inflate(metres: length)
            lastStepHeading = nil
        }
        keepInsideRoom()
        publish()
        if source == .lastKnown, lastStepHeading != nil { source = .steps }
    }

    private var phoneOrHeadHeadingAvailable: Bool {
        heading(heldInFront: motion.heldInFront, phoneYaw: motion.yaw) != nil
    }

    /// A walking direction (museum yaw) with its uncertainty (radians) and where it came from.
    struct StepHeading {
        let yaw: Float
        let sigma: Float
        let source: HeadingSource
    }

    /// Walking direction from the phone or the AirPods, following `headingSource`.
    private func heading(heldInFront: Bool, phoneYaw: Float) -> StepHeading? {
        if phoneHeadingCalibrated, motion.session != phoneSession {
            // The motion sensors restarted (app was in the background): the phone's heading is no longer lined up.
            phoneYawOffset = nil
            phoneHeadingCalibrated = false
        }
        var phone: StepHeading?
        if let offset = phoneYawOffset {
            phone = StepHeading(yaw: MuseumGeometry.wrap(phoneYaw + offset), sigma: heldInFront ? 0.15 : 0.3, source: .phone)
        }
        var head: StepHeading?
        if let yaw = headHeading?() {
            head = StepHeading(yaw: yaw, sigma: 0.3, source: .airPods)
        }
        switch headingSource {
        case .phone:
            return phone
        case .airPods:
            return head
        case .auto:
            if let phone, heldInFront { return phone }
            return head ?? phone
        }
    }

    // MARK: - Filter helpers

    /// Lets the doubt grow for the time since the last update: a lot when you might be walking unseen,
    /// little when the steps say you're standing still.
    private func predict(to now: TimeInterval) {
        let seconds = Float(min(max(now - (lastPredict ?? now), 0), 5))
        lastPredict = now
        let counting = useMotion && motion.isRunning
        let standing = counting && now - lastStepTime > 2
        let rate: Float = standing ? 0.02 : (counting ? 0.25 : 0.8)
        filter.predict(seconds: seconds, rate: rate)
    }

    /// With your own layout: stay within the room (the beacons' box plus a margin).
    private func keepInsideRoom() {
        guard usesLayout, layout.beacons.count >= 2 else { return }
        let points = layout.beacons.map(\.point) + [layout.calibrationPoint]
        var low = points[0], high = points[0]
        for point in points {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        let margin: Float = 1.5
        filter.clamp(min: low - margin, max: high + margin)
    }

    /// Copies the filter's guess to `position` / `accuracy` (only when they really changed).
    private func publish() {
        guard !demoActive else { return }
        let frame = self.frame
        let museum = Self.clamped(frame.toMuseum(filter.point))
        if simd_distance(museum, position) > 0.02 { position = museum }
        let error = filter.accuracy * frame.scale
        if accuracy.map({ abs($0 - error) > 0.25 }) ?? true { accuracy = error }
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

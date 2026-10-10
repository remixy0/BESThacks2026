import Foundation
import Observation
import simd

/// The audio guide.
///
/// - Where you are comes from the BLE beacons (`PositionService`); which way you face comes only from AirPods,
///   lined up with the museum at calibration.
/// - Guidance = bloops placed a few metres ahead of you along the route (see `updateGuidance` for how they speed up,
///   rise in pitch and chime when you face the right way).
/// - Everything it says follows the app language (`tr`), and you can talk back (`listen()`).
///
/// Performance: views only see changes that matter to them. `position`/`facingYaw`/`headPitch` (smooth, for the maps)
/// change often; `here`/`heading` (for distances and "ahead/left/right" text) only every metre or ten degrees.
@Observable
final class GuideModel {
    let audio = SpatialAudioEngine()
    let head = HeadTracker()
    let voice = VoiceSettings()
    let positioning = PositionService()
    let voiceInput = VoiceControl()
    /// Say your phrase ("Hej przewodniku") to start a voice command without touching the phone.
    let wakeWord = WakeWordListener()
    let info: MuseumInfo?
    let loadError: String?

    var mode: UserMode = .standard

    // MARK: Settings

    /// Map mode: read the closest exhibits aloud when you arrive somewhere new.
    var autoAnnounce = UserDefaults.standard.object(forKey: "guide.autoAnnounce") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoAnnounce, forKey: "guide.autoAnnounce") }
    }
    /// Map mode: choose an exhibit by facing it for a moment. Off by default (it surprised people).
    var selectByLooking = UserDefaults.standard.object(forKey: "guide.selectByLooking.v2") as? Bool ?? false {
        didSet { UserDefaults.standard.set(selectByLooking, forKey: "guide.selectByLooking.v2") }
    }
    /// After arriving somewhere, listen for a spoken command ("opowiedz", "dalej"…).
    var listenOnArrival = UserDefaults.standard.object(forKey: "guide.listenOnArrival") as? Bool ?? true {
        didSet { UserDefaults.standard.set(listenOnArrival, forKey: "guide.listenOnArrival") }
    }
    /// Demo: walk along the route by itself (for showing the app without walking).
    var demoWalk = false {
        didSet { if !demoWalk { positioning.endDemo() } }
    }

    // MARK: Calibration

    /// True once you've calibrated in this session.
    private(set) var isCalibrated = false
    /// True when the AirPods heading is lined up with the museum (calibrated with AirPods in, not reconnected since).
    private(set) var headingCalibrated = false

    // MARK: State (fine: for the maps)

    private(set) var position: SIMD2<Float>
    /// Which way you face (radians, 0 = north, positive = turned left), or nil without calibrated AirPods.
    private(set) var facingYaw: Float?
    /// Head tilt (radians, positive = looking up), for the Look view.
    private(set) var headPitch: Float = 0
    /// The map's rotation: follows `facingYaw` but ignores small head wobbles.
    private(set) var mapHeading: Float?

    // MARK: State (coarse: for text and lists)

    /// Where you are, updated every metre or so.
    private(set) var here: SIMD2<Float>
    /// Which way you face, updated every ten degrees or so.
    private(set) var heading: Float?
    /// The place you're in, as named in the museum data (English); `placeName` translates it.
    private(set) var placeKey = ""
    /// The 4 closest exhibits, nearest first.
    private(set) var nearby: [MuseumInfo.Exhibit] = []
    /// The exhibit you're standing at (close to it, or its beacon reads very close), if any.
    private(set) var atExhibit: MuseumInfo.Exhibit?

    /// The place you're in, in the app's language ("Ptaki", "Hala Stanleya Fielda").
    var placeName: String { placeKey.isEmpty ? "" : placeText(placeKey) }

    // MARK: State (guidance)

    /// The exhibit you're facing right now (only tracked with "choose by facing" on).
    private(set) var faced: MuseumInfo.Exhibit?
    /// 0...1 while you hold still facing an exhibit; it's chosen at 1.
    private(set) var dwellProgress: Double = 0
    /// An exhibit tapped on the map, shown in the panel.
    var preview: MuseumInfo.Exhibit?
    /// Where the guide is taking you.
    private(set) var target: MuseumInfo.Exhibit?
    private(set) var route: [SIMD2<Float>] = []
    /// Changes whenever `route` changes (cheap for views to compare).
    private(set) var routeVersion = 0
    private(set) var routeFromService = false
    /// Metres left to walk.
    private(set) var remaining: Float?
    private(set) var arrived: MuseumInfo.Exhibit?
    private(set) var statusMessage: String?
    /// Which way to go next, relative to where you face (for the guidance card).
    private(set) var turn: Turn = .unknown
    /// True while you face the route (within ~15°, let go at ~28°): the "right way" state.
    private(set) var onTrack = false
    /// Length of the route when guidance started (for the progress bar).
    private(set) var routeLength: Float = 0

    enum Turn: Equatable {
        case ahead, left, right, around, unknown
    }

    /// 0...1 progress toward the current target.
    var progress: Double {
        guard let remaining, routeLength > 0 else { return 0 }
        return Double(min(max(1 - remaining / max(routeLength, remaining), 0), 1))
    }

    // MARK: Events (small views react when one changes: haptics, auto-listening)

    private(set) var facedEvent = 0
    private(set) var selectionEvent = 0
    private(set) var waypointEvent = 0
    private(set) var arrivalEvent = 0
    /// You just turned to face the right way.
    private(set) var onTrackEvent = 0
    private(set) var offRouteEvent = 0
    /// Everything queued has been said (not when it was interrupted).
    private(set) var speechFinishedEvent = 0
    /// Set when the guide wants to hear you once it has finished talking (after arriving).
    var listenAfterSpeech = false

    /// Downloading every exhibit's story ahead of time (Settings › Voice), or nil when that isn't running.
    private(set) var storyDownload: StoryDownload?

    struct StoryDownload: Equatable {
        var done = 0
        var total = 0
        var isRunning = true
        var error: String?
    }

    // MARK: Private

    struct Utterance {
        let text: String
        /// Speak from this floor point's direction; nil = in front of you.
        var toward: SIMD2<Float>?
        /// Who it belongs to. `.screen` (default): stops when you leave the screen it was said on.
        /// `.guidance`: news about the walk (guiding you to…, you've arrived, calibrated) that carries on into the next screen.
        var scope: Scope = .screen
    }

    enum Scope {
        case screen, guidance
    }

    // MARK: Screens (keeps sound in step with what's on screen)

    /// The app's screens, for sound. Every message belongs to the screen it was said on: when another screen comes
    /// to the front, that screen's talking stops, anything queued for it is dropped, and a spoken command still being
    /// recorded or recognized is thrown away (so nothing old plays or happens on the new screen).
    enum Screen: Equatable {
        case login, welcome, calibration, map, listen
        /// Sheets over the map / listening screen.
        case settings, exhibits, exhibitDetail

        var isOverlay: Bool {
            switch self {
            case .settings, .exhibits, .exhibitDetail: true
            default: false
            }
        }
    }

    /// The screen in front: the top sheet, else the main screen.
    private(set) var screen: Screen?
    /// Bumped whenever `screen` changes; work that started on an older screen checks it and gives up.
    @ObservationIgnored private(set) var screenGeneration = 0
    @ObservationIgnored private var baseScreen: Screen?
    @ObservationIgnored private var overlays: [Screen] = []

    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var lastTick = ContinuousClock.now
    @ObservationIgnored private var speechQueue: [Utterance] = []
    /// The scope of what's being said right now (nil = nothing).
    @ObservationIgnored private var currentScope: Scope?
    @ObservationIgnored private var lastSpoken: [Utterance] = []
    @ObservationIgnored private var lastAnnounced: Set<String> = []
    @ObservationIgnored private var lastAnnounceTime: ContinuousClock.Instant?
    @ObservationIgnored private var facedSince: ContinuousClock.Instant?
    @ObservationIgnored private var lookCooldownUntil: ContinuousClock.Instant?
    @ObservationIgnored private var nextBloop: ContinuousClock.Instant?
    @ObservationIgnored private var lastBloop: ContinuousClock.Instant?
    @ObservationIgnored private var lastChime: ContinuousClock.Instant?
    @ObservationIgnored private var arrivingSince: ContinuousClock.Instant?
    @ObservationIgnored private var routeSegment = 0
    @ObservationIgnored private var lastReroute: ContinuousClock.Instant?
    @ObservationIgnored private var headingOffset: Float?
    @ObservationIgnored private var calibratedHeadSession = -1
    @ObservationIgnored private var demoYaw: Float = 0
    @ObservationIgnored private var smoothPosition: SIMD2<Float>
    @ObservationIgnored private var lastLanguage = LanguageSettings.shared.current
    private let routeProvider: any RouteProvider = RouteProviders.configured()

    /// How long you face an exhibit before it's chosen.
    private static let dwell: Duration = .milliseconds(1500)
    /// Bloops sit this far ahead of you along the route.
    private static let lookahead: Float = 3
    /// You're "at" an exhibit within its footprint plus this much.
    private static let arrivalMargin: Float = 2.5

    init() {
        let start = CalibrationSpot.configured.point
        position = start
        here = start
        smoothPosition = start
        do {
            info = try MuseumInfo.load()
            loadError = nil
        } catch {
            info = nil
            loadError = "The museum data is missing from the app (FieldMuseum_MainLevel_info.json)."
            print("[Guide] \(error)")
        }
        let spotPoint = positioning.spot.point
        position = spotPoint
        here = spotPoint
        smoothPosition = spotPoint
        audio.onSpeechFinished = { [weak self] in self?.speakNext() }
        // Any app button stops the guide talking before it does its own thing.
        UserTap.onTap = { [weak self] in self?.userTapped() }
        // Turn the 3D sound with your head as fast as the AirPods report (not just on the guide's 20 Hz tick).
        head.onMotion = { [weak self] yaw, pitch in
            guard let self, let offset = self.headingOffset, self.head.session == self.calibratedHeadSession else { return }
            self.audio.setListenerOrientation(yaw: MuseumGeometry.wrap(Float(yaw) + offset), pitch: Float(pitch))
        }
        head.start()
        updateCoarseState(force: true)
    }

    // MARK: - Lifecycle

    func start(mode: UserMode) {
        self.mode = mode
        guard !isRunning else { return }
        isRunning = true
        audio.resume()
        positioning.start()
        lastTick = .now
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                self?.tick()
            }
        }
        if voice.engine == .elevenLabs, !voice.isKeyVerified {
            Task { await voice.loadVoices() }
        }
        wakeWord.start()
    }

    /// Stops everything that makes sound or uses sensors (app in the background).
    func stop() {
        guard isRunning else { return }
        isRunning = false
        loop?.cancel()
        loop = nil
        positioning.stop()
        speechQueue = []
        currentScope = nil
        listenAfterSpeech = false
        voiceInput.cancel()
        wakeWord.stop()
        audio.pause()
    }

    /// Leaving the museum screens (back to the welcome screen, logging out): end guidance quietly and go silent.
    func leaveMuseum() {
        endGuidance()
        preview = nil
        stop()
    }

    // MARK: - Calibration

    /// Starts calibrating: tells you to hold still. Call `finishCalibration()` about 3 seconds later
    /// (the beacons report once a second, so that gives each of them a few readings).
    func beginCalibration() {
        positioning.start()
        say([Utterance(text: tr("Hold still.", "Nie ruszaj się."), toward: nil)])
    }

    struct CalibrationResult {
        var beacons: Int
        var airPods: Bool
    }

    /// You're on the calibration spot, facing its front: line everything up with the museum.
    @discardableResult
    func finishCalibration() -> CalibrationResult {
        let spot = positioning.spot
        let beacons = positioning.calibrate()

        // AirPods: "now" is the spot's front.
        let airPods = head.calibrate()
        if airPods {
            headingOffset = spot.yaw
            calibratedHeadSession = head.session
            headingCalibrated = true
        } else {
            headingOffset = nil
            headingCalibrated = false
        }

        // Jump straight there (no gliding across the map).
        smoothPosition = spot.point
        position = spot.point
        positioning.endDemo()
        demoWalk = false
        isCalibrated = true
        statusMessage = nil
        updateCoarseState(force: true)
        audio.setListener(position: position, yaw: airPods ? spot.yaw : 0)

        // A chime straight ahead: you should hear it in front of you.
        audio.playChime(at: position + MuseumGeometry.forward(yaw: spot.yaw) * 3)
        var text = tr("Calibrated.", "Skalibrowano.")
        if beacons == 0 {
            text += tr(" No beacons heard yet, so your position is the calibration spot for now.",
                       " Nie słychać jeszcze beaconów, więc na razie twoja pozycja to punkt kalibracji.")
        }
        if !airPods {
            text += tr(" Put in your AirPods and calibrate again so the sound turns with your head.",
                       " Załóż AirPodsy i skalibruj ponownie, żeby dźwięk obracał się razem z głową.")
        }
        // Carries on into the museum screen (map mode moves on by itself a moment later).
        say([Utterance(text: text, toward: nil, scope: .guidance)])
        return CalibrationResult(beacons: beacons, airPods: airPods)
    }

    /// Continue without calibrating (position starts at the calibration spot, no heading).
    func skipCalibration() {
        isCalibrated = false
    }

    // MARK: - Actions

    /// Reads the closest exhibits, each spoken from its own direction.
    func announceNearby() {
        let items = Array(nearby.prefix(3))
        lastAnnounced = Set(items.map(\.key))
        lastAnnounceTime = .now
        guard !items.isEmpty else { return }
        let list = items.map { "\($0.name), \(spokenDirections(to: $0))" }.joined(separator: ". ")
        say([Utterance(text: tr("Nearby: ", "W pobliżu: ") + list + ".", toward: nil)])
    }

    /// "You are in Birds. The nearest exhibit is …"
    func announceLocation() {
        var text = placeName.isEmpty ? "" : tr("You are in: \(placeName). ", "Jesteś tutaj: \(placeName). ")
        if let target, let remaining {
            text += tr("Guiding you to \(target.name), \(metersText(Int(remaining.rounded()))) to go.",
                       "Prowadzę do: \(target.name). Zostało \(metersText(Int(remaining.rounded()))).")
        } else if let nearest = nearby.first {
            text += tr("The nearest exhibit is \(nearest.name), \(spokenDirections(to: nearest)).",
                       "Najbliżej jest: \(nearest.name), \(spokenDirections(to: nearest)).")
        }
        say([Utterance(text: text, toward: nil)])
    }

    /// Starts guidance to an exhibit.
    func navigate(to exhibit: MuseumInfo.Exhibit, byLooking: Bool = false) {
        guard let info else { return }
        preview = nil
        faced = nil
        dwellProgress = 0
        statusMessage = nil
        selectionEvent += 1

        // Already there: say so instead of guiding you nowhere.
        if isAt(exhibit, from: position) {
            endGuidance()
            arrived = exhibit
            arrivalEvent += 1
            lookCooldownUntil = .now + .seconds(10)
            var items = [Utterance(text: tr("You're already at \(exhibit.name).", "Już jesteś przy: \(exhibit.name)."),
                                       toward: exhibit.floorPoint, scope: .guidance)]
            if mode == .blind { items.append(Utterance(text: exhibit.story, toward: exhibit.floorPoint, scope: .guidance)) }
            say(items)
            return
        }

        target = exhibit
        arrived = nil
        arrivingSince = nil
        onTrack = false
        let destination = info.viewingSpot(for: exhibit, from: position)
        setRoute([position, destination], fromService: false)
        routeLength = simd_distance(position, destination)
        turn = .unknown
        nextBloop = .now + .seconds(1)

        let intro = byLooking ? tr("You chose \(exhibit.name).", "Wybrano: \(exhibit.name).")
                              : tr("Guiding you to \(exhibit.name).", "Prowadzę do: \(exhibit.name).")
        say([Utterance(text: intro + tr(" Follow the bloops.", " Idź za dźwiękiem."), toward: exhibit.floorPoint, scope: .guidance)])
        requestRoute(to: exhibit, destination: destination)
    }

    /// Follow a route that arrived from somewhere else (e.g. pushed by your server).
    /// Points are floor-plan (x, z); see `RouteDecoder` for parsing JSON.
    func follow(route points: [SIMD2<Float>], to exhibit: MuseumInfo.Exhibit? = nil) {
        guard !points.isEmpty else { return }
        if let exhibit { target = exhibit } else if target == nil { target = nearest(to: points[points.count - 1]) }
        arrived = nil
        var path = points
        if let first = path.first, simd_distance(first, position) > 2 { path.insert(position, at: 0) }
        setRoute(path, fromService: true)
        routeLength = Self.length(of: path)
        nextBloop = .now
    }

    /// Same as `follow(route:)`, straight from the route service's JSON.
    func follow(routeJSON data: Data, to exhibit: MuseumInfo.Exhibit? = nil) throws {
        let yAxis = RouteDecoder.YAxis(rawValue: Secrets.routeYAxis) ?? .modelZ
        follow(route: try RouteDecoder.decode(data, yAxis: yAxis), to: exhibit)
    }

    func stopGuidance() {
        guard target != nil else { return }
        endGuidance()
        lookCooldownUntil = .now + .seconds(6)
        say([Utterance(text: tr("Guidance stopped.", "Prowadzenie zatrzymane."), toward: nil, scope: .guidance)])
    }

    /// Reads the exhibit's story, from its direction.
    func tellStory(of exhibit: MuseumInfo.Exhibit) {
        say(storyUtterances(for: exhibit))
    }

    /// The name and the story as two sentences. The story is always the same text on its own, so its saved
    /// ElevenLabs recording is reused by "tell me", by arriving in listening mode, and by the download in Settings.
    private func storyUtterances(for exhibit: MuseumInfo.Exhibit) -> [Utterance] {
        [Utterance(text: "\(exhibit.name).", toward: exhibit.floorPoint),
         Utterance(text: exhibit.story, toward: exhibit.floorPoint)]
    }

    /// Downloads every exhibit's spoken name and story in the current ElevenLabs voice now, one request each and
    /// only for what isn't saved yet, so in the museum they play at once, even without internet.
    func downloadStories() {
        guard storyDownload?.isRunning != true, let client = voice.elevenLabs, let exhibits = info?.exhibits else { return }
        let texts = exhibits.flatMap { storyUtterances(for: $0).map(\.text) }
        let missing = texts.filter { !SpeechCache.shared.contains($0, using: client) }
        storyDownload = StoryDownload(total: missing.count, isRunning: !missing.isEmpty)
        guard !missing.isEmpty else { return }
        Task { [weak self] in
            // One at a time: gentle on ElevenLabs' limit of parallel requests.
            for text in missing {
                do {
                    try await SpeechCache.shared.load(text, using: client)
                } catch {
                    self?.storyDownload?.error = error.localizedDescription
                    break
                }
                self?.storyDownload?.done += 1
            }
            self?.storyDownload?.isRunning = false
        }
    }

    /// How many of the stories (names + stories) are saved on the phone in the current voice, out of how many.
    func savedStoryCount() -> (saved: Int, total: Int)? {
        guard let client = voice.elevenLabs, let exhibits = info?.exhibits else { return nil }
        let texts = exhibits.flatMap { storyUtterances(for: $0).map(\.text) }
        return (texts.filter { SpeechCache.shared.contains($0, using: client) }.count, texts.count)
    }

    func stopSpeaking() {
        speechQueue = []
        currentScope = nil
        audio.stopSpeaking()
    }

    /// A button was tapped: stop talking right away (the button's own action may then say something new), and drop
    /// a spoken command still being recorded or recognized, so it can't act after the tap.
    func userTapped() {
        listenAfterSpeech = false
        if voiceInput.isBusy { voiceInput.cancel() }
        if audio.isSpeaking || !speechQueue.isEmpty { stopSpeaking() }
    }

    /// A screen came into view (call from its `onAppear`, before it says anything; or use `.soundScreen`).
    func screenAppeared(_ new: Screen) {
        if new.isOverlay {
            overlays.removeAll { $0 == new }
            overlays.append(new)
        } else {
            baseScreen = new
        }
        updateFrontScreen()
    }

    /// A screen went away.
    func screenDisappeared(_ old: Screen) {
        if old.isOverlay {
            overlays.removeAll { $0 == old }
        } else if baseScreen == old {
            baseScreen = nil
        }
        updateFrontScreen()
    }

    private func updateFrontScreen() {
        let front = overlays.last ?? baseScreen
        guard front != screen else { return }
        screen = front
        screenGeneration += 1
        listenAfterSpeech = false
        voiceInput.cancel()
        // The old screen's words stop; news about the walk carries on.
        speechQueue.removeAll { $0.scope == .screen }
        if audio.isSpeaking, currentScope != .guidance {
            currentScope = nil
            audio.stopSpeaking()
            if !speechQueue.isEmpty { speakNext() }
        }
    }

    /// Says something now (replacing whatever is being said).
    func speak(_ items: [Utterance]) {
        say(items)
    }

    /// Says something after whatever is being said now.
    func speakAfterCurrent(_ items: [Utterance]) {
        guard !items.isEmpty else { return }
        if audio.isSpeaking || !speechQueue.isEmpty {
            speechQueue.append(contentsOf: items)
        } else {
            say(items)
        }
    }

    /// Says the last message again.
    func repeatLast() {
        guard !lastSpoken.isEmpty else { return }
        say(lastSpoken)
    }

    /// "Turn left. 24 meters to Totem Poles." For the walking card's Repeat button and listening mode.
    func announceDirection() {
        guard let target, let remaining else {
            announceLocation()
            return
        }
        let meters = metersText(Int(remaining.rounded()))
        let turnText = turnWords(turn)
        say([Utterance(text: tr("\(turnText). \(meters) to \(target.name).", "\(turnText). Do celu: \(meters), \(target.name)."), toward: nil)])
    }

    /// Spoken words for a turn.
    func turnWords(_ turn: Turn) -> String {
        switch turn {
        case .ahead: tr("Go straight ahead", "Idź prosto")
        case .left: tr("Turn left", "Skręć w lewo")
        case .right: tr("Turn right", "Skręć w prawo")
        case .around: tr("Turn around", "Zawróć")
        case .unknown: tr("Follow the bloops", "Idź za dźwiękiem")
        }
    }

    /// A short sample in a given ElevenLabs voice (Settings → Voice).
    func previewVoice(id: String, name: String) {
        speechQueue = []
        currentScope = .screen
        let client = voice.client(voiceID: id)
        audio.speak(tr("Hi, I'm \(name). I'll guide you around the museum.", "Cześć, tu \(name). Oprowadzę cię po muzeum."),
                    from: nil, using: client, rate: voice.speed)
    }

    /// A test bloop on your left or right (onboarding).
    func playTestBloop(onLeft: Bool) {
        audio.resume()
        audio.playBloop(towardAngle: onLeft ? .pi / 2 : -.pi / 2)
    }

    func requestLocationPermission() {
        positioning.requestPermission()
    }

    // MARK: - Talking to the guide

    /// Listens once (beep, then speak). Stops the guide talking first. Nil = nothing understood.
    func listen() async -> VoiceControl.Result? {
        guard !voiceInput.isBusy else { return nil }
        listenAfterSpeech = false
        stopSpeaking()
        // The wake phrase listener lets go of the microphone while the command is recorded.
        wakeWord.suspend()
        defer { wakeWord.resume() }
        let generation = screenGeneration
        let result = await voiceInput.listen(apiKey: voice.effectiveKey, language: LanguageSettings.shared.current) {
            audio.playListenCue()
        }
        // You changed screens while talking: the command was meant for the old one.
        guard generation == screenGeneration else { return nil }
        return result
    }

    /// Commands that mean the same everywhere: story, repeat, where am I, which way, stop.
    /// Returns false when the command needs the screen's own handling (choosing, "next").
    @discardableResult
    func perform(_ heard: VoiceCommands.Heard) -> Bool {
        if heard.stop {
            stopSpeaking()
            return true
        }
        if heard.story, let exhibit = atExhibit ?? arrived ?? target ?? nearby.first {
            tellStory(of: exhibit)
            return true
        }
        if heard.repeatIt {
            repeatLast()
            return true
        }
        if heard.whereAmI {
            announceLocation()
            return true
        }
        if heard.directions {
            announceDirection()
            return true
        }
        return false
    }

    /// "Didn't get that" with what you can say.
    func sayNotUnderstood(_ text: String, hint: String) {
        let heard = text.isEmpty ? "" : tr("I heard: \(text). ", "Usłyszałem: \(text). ")
        say([Utterance(text: heard + hint, toward: nil)])
    }

    // MARK: - Directions (coarse, for text: they don't change with every step or head wobble)

    func distance(to exhibit: MuseumInfo.Exhibit) -> Float {
        simd_distance(here, exhibit.floorPoint)
    }

    /// "12 m ahead", "30 m left" / "12 m prosto", "30 m w lewo".
    func directions(to exhibit: MuseumInfo.Exhibit) -> String {
        let meters = Int(distance(to: exhibit).rounded())
        guard let side = side(of: exhibit.floorPoint, from: here, facing: heading, short: true) else { return "\(meters) m" }
        return "\(meters) m \(side)"
    }

    /// "12 meters ahead" / "12 metrów prosto przed tobą". Uses the precise position: it's said once.
    func spokenDirections(to exhibit: MuseumInfo.Exhibit) -> String {
        let meters = metersText(Int(simd_distance(position, exhibit.floorPoint).rounded()))
        guard let side = side(of: exhibit.floorPoint, from: position, facing: facingYaw, short: false) else {
            return tr("\(meters) away", "\(meters) stąd")
        }
        return "\(meters) \(side)"
    }

    private func side(of point: SIMD2<Float>, from origin: SIMD2<Float>, facing: Float?, short: Bool) -> String? {
        guard let facing else { return nil }
        let degrees = MuseumGeometry.wrap(MuseumGeometry.yaw(from: origin, to: point) - facing) * 180 / .pi
        switch abs(degrees) {
        case ..<20:
            return short ? tr("ahead", "prosto") : tr("ahead", "prosto przed tobą")
        case 140...:
            return short ? tr("behind", "z tyłu") : tr("behind you", "za tobą")
        default:
            if degrees > 0 {
                if short { return tr("left", "w lewo") }
                return abs(degrees) < 60 ? tr("ahead, to your left", "przed tobą, lekko w lewo") : tr("to your left", "po lewej")
            }
            if short { return tr("right", "w prawo") }
            return abs(degrees) < 60 ? tr("ahead, to your right", "przed tobą, lekko w prawo") : tr("to your right", "po prawej")
        }
    }

    /// Angle from where you face to a point, positive = to your left. Nil when facing is unknown. (Precise.)
    private func relativeAngle(to point: SIMD2<Float>) -> Float? {
        guard let facingYaw else { return nil }
        return MuseumGeometry.wrap(MuseumGeometry.yaw(from: position, to: point) - facingYaw)
    }

    private func isAt(_ exhibit: MuseumInfo.Exhibit, from point: SIMD2<Float>) -> Bool {
        let size = max(exhibit.halfExtents.x, exhibit.halfExtents.y)
        return simd_distance(point, exhibit.floorPoint) < size + Self.arrivalMargin
    }

    /// True when a beacon near the exhibit reads very close: you're at it, whatever the position estimate says.
    private func beaconSaysAt(_ exhibit: MuseumInfo.Exhibit, close: [SIMD2<Float>]) -> Bool {
        let size = max(exhibit.halfExtents.x, exhibit.halfExtents.y)
        return close.contains { simd_distance($0, exhibit.floorPoint) < size + 4 }
    }

    // MARK: - Loop (20 times a second)

    private func tick() {
        guard info != nil else { return }
        let now = ContinuousClock.now
        let dt = min(Float((now - lastTick) / .seconds(1)), 0.2)
        lastTick = now

        if demoWalk, target != nil, !audio.isSpeaking {
            walkAlongRoute(dt)
        }

        // Glide toward the latest estimate (beacon fixes arrive once a second), but jump on big changes.
        let goal = positioning.position
        if simd_distance(goal, smoothPosition) > 15 {
            smoothPosition = goal
        } else {
            smoothPosition += (goal - smoothPosition) * (1 - exp(-dt * 4))
        }
        if simd_distance(smoothPosition, position) > 0.03 { position = smoothPosition }

        // Which way you face (and tilt your head): AirPods only.
        let newFacing = resolveFacing()
        switch (newFacing, facingYaw) {
        case (nil, nil): break
        case let (new?, old?): if abs(MuseumGeometry.wrap(new - old)) > 0.01 { facingYaw = new }
        default: facingYaw = newFacing
        }
        let pitch = headingOffset != nil && head.status == .tracking ? Float(head.pitch) : 0
        if abs(pitch - headPitch) > 0.01 { headPitch = pitch }
        updateMapHeading()
        audio.setListener(position: position, yaw: facingYaw ?? 0, pitch: headPitch)

        if LanguageSettings.shared.current != lastLanguage {
            lastLanguage = LanguageSettings.shared.current
            updateCoarseState(force: true)
        } else {
            updateCoarseState(force: false)
        }
        if mode == .standard {
            autoAnnounceIfNeeded(now)
            updateFacedExhibit(now)
        }
        if target != nil { updateGuidance(now) }
    }

    private func resolveFacing() -> Float? {
        if demoWalk, target != nil, head.status != .tracking || headingOffset == nil {
            return demoYaw
        }
        guard head.status == .tracking, let headingOffset else { return nil }
        if head.session != calibratedHeadSession {
            // AirPods reconnected: their "front" is gone until you calibrate again.
            self.headingOffset = nil
            headingCalibrated = false
            statusMessage = tr("Your AirPods reconnected. Calibrate again (Settings) so directions are right.",
                               "AirPodsy połączyły się ponownie. Skalibruj jeszcze raz (Ustawienia), żeby kierunki były dobre.")
            return nil
        }
        return MuseumGeometry.wrap(Float(head.yaw) + headingOffset)
    }

    /// Map rotation with a deadband, so tiny head movements don't keep the 3D camera moving.
    private func updateMapHeading() {
        switch (facingYaw, mapHeading) {
        case (nil, nil): break
        case (nil, _?): mapHeading = nil
        case let (facing?, nil): mapHeading = facing
        case let (facing?, current?):
            if abs(MuseumGeometry.wrap(facing - current)) > 4 * .pi / 180 { mapHeading = facing }
        }
    }

    /// Distances, place name, nearby exhibits: only when you've moved a metre or turned ten degrees.
    private func updateCoarseState(force: Bool) {
        guard let info else { return }
        let moved = simd_distance(position, here) > 1
        if moved || force {
            if moved { here = position }
            let place = info.placeName(at: here)
            if place != placeKey { placeKey = place }
            let closest = info.nearest(to: here, count: 4)
            if closest.map(\.key) != nearby.map(\.key) { nearby = closest }
        }
        // At an exhibit: close to it, or its beacon reads very close (checked every tick: beacons are quick).
        let close = positioning.closeBeaconPoints()
        let at = info.exhibits.first { isAt($0, from: here) } ?? info.exhibits.first { beaconSaysAt($0, close: close) }
        if at?.key != atExhibit?.key { atExhibit = at }

        switch (facingYaw, heading) {
        case (nil, nil): break
        case (nil, _?): heading = nil
        case let (facing?, nil): heading = facing
        case let (facing?, current?):
            if abs(MuseumGeometry.wrap(facing - current)) > 10 * .pi / 180 { heading = facing }
        }
    }

    private func autoAnnounceIfNeeded(_ now: ContinuousClock.Instant) {
        guard autoAnnounce, isCalibrated, target == nil, !audio.isSpeaking, speechQueue.isEmpty, !voiceInput.isBusy,
              !nearby.isEmpty, screen == .map || screen == .listen else { return }
        let keys = Set(nearby.prefix(3).map(\.key))
        guard keys != lastAnnounced else { return }
        if let last = lastAnnounceTime, now - last < .seconds(30) { return }
        announceNearby()
    }

    private func updateFacedExhibit(_ now: ContinuousClock.Instant) {
        guard selectByLooking, target == nil, let info, facingYaw != nil else {
            if faced != nil { faced = nil }
            if dwellProgress != 0 { dwellProgress = 0 }
            return
        }
        var best: (exhibit: MuseumInfo.Exhibit, angle: Float)?
        for exhibit in info.exhibits {
            // Not the one you're standing at: you'd "arrive" again straight away.
            guard exhibit.key != atExhibit?.key else { continue }
            let meters = simd_distance(position, exhibit.floorPoint)
            guard meters < 60, let angle = relativeAngle(to: exhibit.floorPoint).map(abs) else { continue }
            let size = max(exhibit.halfExtents.x, exhibit.halfExtents.y)
            let cone = max(atan2(size, max(meters, 0.1)), 10 * .pi / 180)
            if angle < cone, angle < (best?.angle ?? .infinity) {
                best = (exhibit, angle)
            }
        }

        let newFaced = best?.exhibit
        if newFaced?.key != faced?.key {
            faced = newFaced
            facedSince = now
            dwellProgress = 0
            if newFaced != nil { facedEvent += 1 }
        }

        guard let faced, let since = facedSince else {
            if dwellProgress != 0 { dwellProgress = 0 }
            return
        }
        if let cooldown = lookCooldownUntil, now < cooldown {
            if dwellProgress != 0 { dwellProgress = 0 }
            return
        }
        let held = now - since
        let progress = min(held / Self.dwell, 1)
        if abs(progress - dwellProgress) > 0.05 || progress == 1 { dwellProgress = progress }
        if held >= Self.dwell {
            navigate(to: faced, byLooking: true)
        }
    }

    /// The sound of guidance (rhythm and sound depend on `audio.bloopStyle`: guiding / calm / chill, see `BloopStyle`):
    /// - Facing the wrong way: regular bloops (guiding: about 3 a second), low and muffled when the way is behind you.
    /// - Turning toward the route: the pitch climbs the closer you get to the right direction.
    /// - Facing the right way: a chime and a tap, then only a quiet bloop every few seconds (no nagging).
    /// - Turning away again: straight back to the style's normal bloops.
    private func updateGuidance(_ now: ContinuousClock.Instant) {
        guard let target, !route.isEmpty else { return }
        let progress = RouteMath.progress(of: position, along: route, from: routeSegment)
        if progress.segment > routeSegment {
            routeSegment = progress.segment
            if route.count > 2 { waypointEvent += 1 }
        }
        let left = RouteMath.remainingLength(of: route, from: progress) + progress.offset
        if remaining == nil || abs((remaining ?? 0) - left) > 0.5 { remaining = left }

        // Arrived? Close for a moment (beacon positions wobble), or the exhibit's beacon reads very close.
        let close = positioning.closeBeaconPoints(within: 1.5)
        if simd_distance(position, route[route.count - 1]) < 2 || isAt(target, from: position) || beaconSaysAt(target, close: close) {
            if arrivingSince == nil { arrivingSince = now }
            if let since = arrivingSince, now - since > .milliseconds(700) {
                arrive(at: target)
                return
            }
        } else {
            arrivingSince = nil
        }

        // Wandered off the route: start again from here.
        if progress.offset > 8, lastReroute.map({ now - $0 > .seconds(8) }) ?? true {
            lastReroute = now
            offRouteEvent += 1
            setRoute([position, route[route.count - 1]], fromService: false)
            requestRoute(to: target, destination: route[route.count - 1])
            return
        }

        let ahead = RouteMath.point(on: route, from: progress, ahead: Self.lookahead)
        let angle = relativeAngle(to: ahead)
        let style = audio.bloopStyle
        let newTurn: Turn
        if let angle {
            let degrees = abs(angle) * 180 / .pi
            newTurn = degrees < 25 ? .ahead : degrees > 135 ? .around : (angle > 0 ? .left : .right)
            // "Right way" with hysteresis, so it doesn't flicker at the edge.
            if onTrack, degrees > 28 {
                onTrack = false
                // Wrong way again: back to the normal bloops right away (but not on top of the last one).
                let gap = Duration.milliseconds(Int(style.minimumGap * 1000))
                nextBloop = lastBloop.map { max(now, $0 + gap) } ?? now
            } else if !onTrack, degrees < 15 {
                onTrack = true
                onTrackEvent += 1
                let chimeAllowed = lastChime.map { now - $0 > .seconds(style.chimeCooldown) } ?? true
                if !audio.isSpeaking, chimeAllowed {
                    audio.playChime(at: ahead, volume: style.chimeVolume)
                    lastChime = now
                }
                nextBloop = now + .seconds(style.onTrackPause)
            }
        } else {
            newTurn = .unknown
            if onTrack { onTrack = false }
        }
        if newTurn != turn { turn = newTurn }

        // Bloops pause while the guide is talking.
        if audio.isSpeaking {
            nextBloop = now + .milliseconds(400)
            return
        }
        if let next = nextBloop, now < next { return }

        let degrees = angle.map { Double(abs($0) * 180 / .pi) }
        let beat = style.beat(degrees: degrees, onTrack: onTrack, metersLeft: left)
        audio.playBloop(at: ahead, pitch: beat.pitch, muffled: beat.muffled, volume: beat.volume)
        lastBloop = now
        nextBloop = now + .milliseconds(Int(beat.interval * 1000))
    }

    /// One bloop of the chosen style in front of you (Settings, when you pick a style).
    func previewBloopStyle() {
        audio.resume()
        let beat = audio.bloopStyle.beat(degrees: 40, onTrack: false, metersLeft: 20)
        audio.playBloop(towardAngle: 0.3, pitch: beat.pitch, volume: beat.volume)
    }

    private func arrive(at exhibit: MuseumInfo.Exhibit) {
        endGuidance()
        arrived = exhibit
        arrivalEvent += 1
        lookCooldownUntil = .now + .seconds(10)
        lastAnnounceTime = .now
        lastAnnounced = Set(nearby.prefix(3).map(\.key))
        audio.playChime(at: exhibit.floorPoint)
        var text = tr("You have arrived at \(exhibit.name).", "Jesteś na miejscu: \(exhibit.name).")
        var story: [Utterance] = []
        if mode == .blind {
            story = [Utterance(text: exhibit.story, toward: exhibit.floorPoint, scope: .guidance)]
        } else if listenOnArrival {
            text += tr(" Say \"tell me\" to hear its story, or \"next\".", " Powiedz „opowiedz”, żeby usłyszeć historię, albo „dalej”.")
            listenAfterSpeech = true
        }
        say([Utterance(text: text, toward: exhibit.floorPoint, scope: .guidance)] + story)
    }

    private func endGuidance() {
        target = nil
        remaining = nil
        nextBloop = nil
        arrivingSince = nil
        turn = .unknown
        onTrack = false
        if !route.isEmpty { setRoute([], fromService: false) }
        if demoWalk { positioning.endDemo() }
    }

    private func setRoute(_ points: [SIMD2<Float>], fromService: Bool) {
        route = points
        routeFromService = fromService
        routeSegment = 0
        routeVersion += 1
    }

    /// Asks the route service (if configured) for a real walking route and swaps it in.
    private func requestRoute(to exhibit: MuseumInfo.Exhibit, destination: SIMD2<Float>) {
        guard routeProvider.isRemote else { return }
        let provider = routeProvider
        let start = position
        let routeTarget = RouteTarget(key: exhibit.key, title: exhibit.title, point: destination)
        lastReroute = .now
        Task { [weak self] in
            do {
                let points = try await provider.route(from: start, to: routeTarget)
                guard let self, self.target?.key == exhibit.key, !points.isEmpty else { return }
                var path = points
                if let first = path.first, simd_distance(first, self.position) > 2 { path.insert(self.position, at: 0) }
                self.setRoute(path, fromService: true)
                self.routeLength = max(self.routeLength, Self.length(of: path))
            } catch {
                self?.statusMessage = tr("Route service: \(error.localizedDescription) Using a straight line.",
                                         "Serwis tras: \(error.localizedDescription) Prowadzę w linii prostej.")
            }
        }
    }

    /// Demo walk: 1.3 m/s along the route, facing where you're going.
    private func walkAlongRoute(_ dt: Float) {
        guard route.count >= 2 else { return }
        let from = positioning.position
        let progress = RouteMath.progress(of: from, along: route, from: routeSegment)
        let next = RouteMath.point(on: route, from: progress, ahead: 1.3 * dt)
        let ahead = RouteMath.point(on: route, from: progress, ahead: 2)
        if simd_distance(ahead, progress.point) > 0.1 { demoYaw = MuseumGeometry.yaw(from: progress.point, to: ahead) }
        positioning.setDemo(position: next)
    }

    private static func length(of path: [SIMD2<Float>]) -> Float {
        zip(path, path.dropFirst()).reduce(0) { $0 + simd_distance($1.0, $1.1) }
    }

    private func nearest(to point: SIMD2<Float>) -> MuseumInfo.Exhibit? {
        info?.exhibits.min { simd_distance($0.floorPoint, point) < simd_distance($1.floorPoint, point) }
    }

    // MARK: - Speech queue

    private func say(_ items: [Utterance]) {
        speechQueue = items
        lastSpoken = items
        audio.stopSpeaking()
        speakNext()
    }

    private func speakNext() {
        guard !speechQueue.isEmpty else {
            currentScope = nil
            speechFinishedEvent += 1
            return
        }
        let item = speechQueue.removeFirst()
        currentScope = item.scope
        let client = voice.elevenLabs
        audio.speak(item.text, from: item.toward.map(voicePoint(toward:)), using: client, rate: voice.speed)
        // Fetch the next sentence while this one plays, so there's no pause between them.
        if let client, let upcoming = speechQueue.first {
            SpeechCache.shared.prepare(upcoming.text, using: client)
        }
    }

    /// The voice comes from the exhibit's direction, 2 m away, so it's clear but still directional.
    private func voicePoint(toward point: SIMD2<Float>) -> SIMD2<Float> {
        let offset = point - position
        let length = simd_length(offset)
        guard length > 0.01 else { return position + MuseumGeometry.forward(yaw: facingYaw ?? 0) * 1.5 }
        return position + offset / length * min(length, 2)
    }
}

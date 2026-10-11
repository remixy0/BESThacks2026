import AVFoundation
import Observation
import simd

/// 3D audio for the guide: the navigation bloop, the "right way" chime and the spoken voice, all placed in the
/// museum with Apple's HRTF renderer, heard from where you stand and the way your head points.
///
/// Coordinates are the museum's floor plan: x = metres east, z = metres south. AVAudioEnvironmentNode is
/// right-handed with -z forward and +y up, which is exactly the model's frame, so points map 1:1.
///
/// What makes it feel 3D: the listener turns with your head (yaw and pitch, updated as fast as the AirPods report),
/// the sounds have high-frequency content the ears use for direction, sounds behind you are muffled, and a little
/// room reverb puts them "out there" instead of inside your head.
@Observable
final class SpatialAudioEngine {
    var bloopVolume: Float = UserDefaults.standard.object(forKey: "audio.bloopVolume") as? Float ?? 0.9 {
        didSet {
            bloopPlayer.volume = bloopVolume
            chimePlayer.volume = min(bloopVolume + 0.1, 1)
            UserDefaults.standard.set(bloopVolume, forKey: "audio.bloopVolume")
        }
    }

    /// How the guide bloops: guiding / calm / chill (Settings › Guide › Bloop rhythm). See `BloopStyle`.
    var bloopStyle: BloopStyle = UserDefaults.standard.string(forKey: "audio.bloopStyle").flatMap(BloopStyle.init) ?? .guiding {
        didSet { UserDefaults.standard.set(bloopStyle.rawValue, forKey: "audio.bloopStyle") }
    }

    private(set) var outputName = "No output"
    private(set) var isHeadphones = false
    private(set) var lastError: String?
    /// True while a spoken message is loading or playing.
    private(set) var isSpeaking = false
    /// Set when the online voice failed and the Apple voice was used instead.
    private(set) var speechNotice: String?

    /// Called when a message has been heard to the end (not when it was interrupted).
    @ObservationIgnored var onSpeechFinished: (() -> Void)?

    /// Ear height above the floor, metres.
    static let earHeight: Float = 1.6

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let environment = AVAudioEnvironmentNode()
    @ObservationIgnored private let bloopPlayer = AVAudioPlayerNode()
    @ObservationIgnored private let chimePlayer = AVAudioPlayerNode()
    @ObservationIgnored private let speechPlayer = AVAudioPlayerNode()
    @ObservationIgnored private let monoFormat = AVAudioFormat(standardFormatWithSampleRate: Bloop.sampleRate, channels: 1)!
    @ObservationIgnored private lazy var speechOutput = SpeechOutput(player: speechPlayer, outputFormat: monoFormat)
    /// Each style has its own sound (bloop, wooden "tok", soft tone).
    @ObservationIgnored private lazy var bloopBuffers: [BloopStyle: AVAudioPCMBuffer] =
        Dictionary(uniqueKeysWithValues: BloopStyle.allCases.map { ($0, Bloop.buffer(for: $0, format: self.monoFormat)) })
    @ObservationIgnored private lazy var chimeBuffer = Bloop.chime(format: monoFormat)
    @ObservationIgnored private lazy var listenBuffer = Bloop.listenCue(format: monoFormat)
    @ObservationIgnored private let appleSpeech = AppleSpeech()
    @ObservationIgnored private var speechTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var listenerPosition = SIMD2<Float>(0, 0)
    @ObservationIgnored private var listenerYaw: Float = 0
    @ObservationIgnored private var listenerPitch: Float = 0
    @ObservationIgnored private var isPaused = false

    init() {
        configureSession()
        buildGraph()
        observeChanges()
        updateRoute()
        start()
    }

    // MARK: - Listener

    /// You: where you stand (floor plan) and which way your head points (yaw: 0 = north, positive = turned left;
    /// pitch: positive = looking up).
    func setListener(position: SIMD2<Float>, yaw: Float, pitch: Float = 0) {
        listenerPosition = position
        environment.listenerPosition = point3D(position)
        setListenerOrientation(yaw: yaw, pitch: pitch)
    }

    /// Head turns only (called at the AirPods' own rate, ~25-60 times a second, for low latency).
    func setListenerOrientation(yaw: Float, pitch: Float) {
        listenerYaw = yaw
        listenerPitch = pitch
        let q = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: pitch, axis: [1, 0, 0])
        let forward = q.act(SIMD3<Float>(0, 0, -1))
        let up = q.act(SIMD3<Float>(0, 1, 0))
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up: AVAudio3DVector(x: up.x, y: up.y, z: up.z)
        )
    }

    // MARK: - Bloop and chime

    /// One bloop from a floor point. `pitch` 0.5...2 (higher = closer to the right direction), `muffled` for sounds
    /// behind you, `gain` 0…1 on top of the bloop volume (quieter while you're already going the right way).
    func playBloop(at point: SIMD2<Float>, pitch: Float = 1, muffled: Bool = false, gain: Float = 1) {
        guard let sound = bloopBuffers[bloopStyle], ensureRunning() else { return }
        bloopPlayer.volume = bloopVolume * min(max(gain, 0), 1)
        bloopPlayer.position = point3D(point)
        bloopPlayer.rate = min(max(pitch, 0.5), 2)
        bloopPlayer.occlusion = muffled ? -14 : 0
        bloopPlayer.scheduleBuffer(sound, at: nil, options: .interrupts)
        startIfNeeded(bloopPlayer)
    }

    /// One bloop at an angle from where you face (positive = left), e.g. a left/right test.
    func playBloop(towardAngle angle: Float, distance: Float = 2, pitch: Float = 1, gain: Float = 1) {
        playBloop(at: listenerPosition + MuseumGeometry.forward(yaw: listenerYaw + angle) * distance, pitch: pitch, gain: gain)
    }

    /// The bright two-note chime: "this is the right way". Plays from the direction of `point`.
    func playChime(at point: SIMD2<Float>, volume: Float = 1) {
        guard ensureRunning() else { return }
        chimePlayer.volume = min(bloopVolume + 0.1, 1) * min(max(volume, 0), 1)
        chimePlayer.position = point3D(point)
        chimePlayer.scheduleBuffer(chimeBuffer, at: nil, options: .interrupts)
        startIfNeeded(chimePlayer)
    }

    /// A short rising beep in front of you: "speak now".
    func playListenCue() {
        guard ensureRunning() else { return }
        chimePlayer.volume = min(bloopVolume + 0.1, 1)
        chimePlayer.position = point3D(listenerPosition + MuseumGeometry.forward(yaw: listenerYaw) * 1.2)
        chimePlayer.scheduleBuffer(listenBuffer, at: nil, options: .interrupts)
        startIfNeeded(chimePlayer)
    }

    // MARK: - Speech

    /// Speaks `text` from a floor point (nil = just in front of you), using ElevenLabs when given, else the Apple voice.
    /// Speaking again while a message is playing replaces it. `rate` is 0.7…1.2 (1 = normal).
    func speak(_ text: String, from point: SIMD2<Float>?, using elevenLabs: ElevenLabsTTS?, rate: Float = 1) {
        let forward = MuseumGeometry.forward(yaw: listenerYaw)
        speechPlayer.position = point3D(point ?? listenerPosition + forward * 1.5)
        guard ensureRunning() else { return }
        cancelSpeech()
        startIfNeeded(speechPlayer)
        isSpeaking = true
        speechNotice = nil

        let output = speechOutput
        let token = output.begin()
        let onFinish: @Sendable () -> Void = {
            Task { @MainActor in
                guard output.isCurrent(token) else { return }
                self.isSpeaking = false
                self.onSpeechFinished?()
            }
        }

        guard let elevenLabs else {
            appleSpeech.speak(text, rate: rate, into: output, token: token, onFinish: onFinish)
            return
        }

        speechTask = Task {
            do {
                try await elevenLabs.stream(text, into: output, token: token)
                output.finish(token: token, onFinish: onFinish)
            } catch is CancellationError {
                // Replaced by a newer message or stopped.
            } catch let error as URLError where error.code == .cancelled {
                // Same, from URLSession.
            } catch {
                guard output.isCurrent(token) else { return }
                // No internet, bad key, quota…: say it with the offline voice instead.
                speechNotice = "\(error.localizedDescription) " + tr("Used the Apple voice instead.", "Użyto głosu Apple.")
                appleSpeech.speak(text, rate: rate, into: output, token: token, onFinish: onFinish)
            }
        }
    }

    func stopSpeaking() {
        cancelSpeech()
        speechOutput.cancel()
        isSpeaking = false
    }

    private func cancelSpeech() {
        speechTask?.cancel()
        speechTask = nil
        appleSpeech.stop()
        speechPlayer.stop() // Drops whatever is left of the previous message.
    }

    // MARK: - Pause (app in the background)

    /// Silences everything and pauses the engine (the app went to the background or left the museum).
    func pause() {
        stopSpeaking()
        bloopPlayer.stop()
        chimePlayer.stop()
        engine.pause()
        isPaused = true
    }

    /// Picks up after `pause()`.
    func resume() {
        guard isPaused else { return }
        isPaused = false
        configureSession()
        start()
    }

    // MARK: - Setup

    private func point3D(_ point: SIMD2<Float>) -> AVAudio3DPoint {
        AVAudio3DPoint(x: point.x, y: Self.earHeight, z: point.y)
    }

    /// Restarts the engine if it stopped, e.g. after a phone call or another app took the audio session.
    private func ensureRunning() -> Bool {
        if isPaused { return false }
        if !engine.isRunning {
            configureSession()
            start()
        }
        return engine.isRunning
    }

    private func startIfNeeded(_ node: AVAudioPlayerNode) {
        guard !node.isPlaying else { return }
        do {
            try node.playAudio()
        } catch {
            lastError = "Playback: \(error.localizedDescription)"
        }
    }

    private func configureSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // Play and record, so voice commands can use the iPhone's microphone without switching modes.
            // A2DP only (no hands-free profile): AirPods keep full-quality stereo for the 3D sound, and the
            // microphone is the phone's own.
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
        }
        #elseif os(visionOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
        }
        #endif
    }

    private func buildGraph() {
        engine.attach(environment)
        engine.attach(bloopPlayer)
        engine.attach(chimePlayer)
        engine.attach(speechPlayer)
        connectNodes()

        // .auto = the best spatial renderer the current hardware supports (HRTF on headphones).
        for node in [bloopPlayer, chimePlayer, speechPlayer] {
            node.renderingAlgorithm = .auto
        }
        // More room sound on the bloop and chime: it pushes them out of your head and into the hall.
        bloopPlayer.reverbBlend = 0.32
        chimePlayer.reverbBlend = 0.25
        speechPlayer.reverbBlend = 0.08
        bloopPlayer.volume = bloopVolume
        chimePlayer.volume = min(bloopVolume + 0.1, 1)
        environment.outputType = .headphones

        let attenuation = environment.distanceAttenuationParameters
        attenuation.distanceAttenuationModel = .inverse
        attenuation.referenceDistance = 1.5
        attenuation.maximumDistance = 40
        attenuation.rolloffFactor = 1

        environment.reverbParameters.enable = true
        environment.reverbParameters.loadFactoryReverbPreset(.mediumHall)
        environment.reverbParameters.level = -12

        setListener(position: listenerPosition, yaw: 0)
    }

    private func connectNodes() {
        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let stereo = AVAudioFormat(standardFormatWithSampleRate: outputRate > 0 ? outputRate : 48_000, channels: 2)
        do {
            try engine.connectNode(bloopPlayer, to: environment, format: monoFormat)
            try engine.connectNode(chimePlayer, to: environment, format: monoFormat)
            try engine.connectNode(speechPlayer, to: environment, format: monoFormat)
            try engine.connectNode(environment, to: engine.mainMixerNode, format: stereo)
        } catch {
            lastError = "Audio graph: \(error.localizedDescription)"
        }
    }

    private func start() {
        guard !isPaused else { return }
        do {
            engine.prepare()
            try engine.start()
            lastError = nil
        } catch {
            lastError = "Audio engine: \(error.localizedDescription)"
        }
    }

    private func observeChanges() {
        let center = NotificationCenter.default

        // Fired when the output device changes (e.g. AirPods connect) and the engine stops.
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.connectNodes()
                self.start()
                self.updateRoute()
            }
        })

        #if os(iOS) || os(visionOS)
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateRoute() }
        })
        #endif
    }

    private func updateRoute() {
        #if os(iOS) || os(visionOS)
        let headphoneTypes: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones]
        let output = AVAudioSession.sharedInstance().currentRoute.outputs.first
        outputName = output?.portName ?? "No output"
        isHeadphones = output.map { headphoneTypes.contains($0.portType) } ?? false
        #else
        outputName = "System output"
        isHeadphones = true
        #endif
    }
}

import Foundation
import Observation
import simd

/// The backend's `/ws/position` WebSocket: tells the server where you are and where you want to go, and gets back
/// step-by-step guidance (`navigation`), the alarm and closed areas (`policy`) and errors.
///
/// - Plain WebSocket, one JSON object per text message, told apart by `type`. No STOMP, no request ids:
///   anything can arrive at any time, so there's one receive loop.
/// - Keeps what the server should know (your position, your destination) and sends it again after every reconnect,
///   as the contract asks; the server doesn't remember it across connections.
/// - Position: at most ~3 times a second, and at least every 2 s (the staff panel shows it).
/// - Connection trouble: tries again after 2, 4, 8 … 30 s. Meanwhile the guide works on local data (see GuideModel).
@Observable
final class PositionSocket {
    enum State: Equatable {
        /// Not wanted (app in the background, not in the museum).
        case off
        /// No server address set: local data only.
        case noServer
        case connecting
        case online
        /// Lost or refused; trying again soon (`problem` says why).
        case offline
    }

    enum SessionResult {
        case ready(BackendClient)
        case noServer
        case unavailable(String)
    }

    private(set) var state: State = .off {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    /// Why it's offline, for Settings.
    private(set) var problem: String?
    /// The latest alarm / closed-areas state from the server.
    private(set) var policy: Policy?

    // MARK: Messages

    nonisolated struct Point: Decodable, Sendable, Equatable {
        let x: Float
        let y: Float
        /// As a floor point (map y = model z).
        var point: SIMD2<Float> { SIMD2(x, y) }
    }

    /// `{"type":"navigation","status":"navigating","nextWaypoint":{"x":..,"y":..},"remainingDistanceM":..,…}`
    nonisolated struct Navigation: Decodable, Sendable {
        /// awaiting_position, navigating, escaping, arrived, blocked, cancelled, idle
        let status: String
        let routeId: String?
        let destination: Point?
        let nextWaypoint: Point?
        let waypointIndex: Int?
        let waypointCount: Int?
        let distanceToWaypointM: Float?
        let remainingDistanceM: Float?
        let recalculated: Bool?
        /// NO_ROUTE, DESTINATION_BLOCKED, POSITION_OUTSIDE_MAP, POSITION_BLOCKED, NO_REACHABLE_EXIT, NO_ESCAPE_ROUTE
        let reason: String?
        let alarmActive: Bool?
        let policyRevision: Int?
    }

    /// `{"type":"policy","revision":3,"alarmActive":true,"zones":[…],"exits":[…]}`
    nonisolated struct Policy: Decodable, Sendable, Equatable {
        let revision: Int?
        let alarmActive: Bool
        let zones: [Zone]
        let exits: [Point]

        enum CodingKeys: String, CodingKey { case revision, alarmActive, zones, exits }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            revision = try container.decodeIfPresent(Int.self, forKey: .revision)
            alarmActive = try container.decodeIfPresent(Bool.self, forKey: .alarmActive) ?? false
            zones = try container.decodeIfPresent([Zone].self, forKey: .zones) ?? []
            exits = try container.decodeIfPresent([Point].self, forKey: .exits) ?? []
        }
    }

    /// A rectangle the staff closed (metres, map coordinates).
    nonisolated struct Zone: Decodable, Sendable, Equatable {
        let id: String?
        let minX: Float
        let minY: Float
        let maxX: Float
        let maxY: Float

        var rect: MuseumGrid.Rect { MuseumGrid.Rect(minX: minX, minY: minY, maxX: maxX, maxY: maxY) }
    }

    // MARK: Hooks (set by the guide and the app)

    /// Gets a logged-in session (logging in again if needed).
    @ObservationIgnored var session: (@MainActor () async -> SessionResult)?
    /// The server refused our session (401/403 at the handshake, or closed with 1008).
    @ObservationIgnored var onSessionRejected: (@MainActor () -> Void)?
    @ObservationIgnored var onNavigation: (@MainActor (Navigation) -> Void)?
    @ObservationIgnored var onPolicy: (@MainActor (Policy) -> Void)?
    /// An `error` message's code (e.g. DESTINATION_BLOCKED).
    @ObservationIgnored var onError: (@MainActor (String) -> Void)?
    @ObservationIgnored var onStateChange: (@MainActor (State) -> Void)?

    // MARK: Private

    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var socket: URLSessionWebSocketTask?
    @ObservationIgnored private var position: SIMD2<Float>?
    @ObservationIgnored private var destination: SIMD2<Float>?
    @ObservationIgnored private var lastSentPosition: SIMD2<Float>?
    @ObservationIgnored private var lastSentAt: ContinuousClock.Instant?

    // MARK: - Control

    /// Connect (and keep reconnecting) until `stop()`.
    func start() {
        wanted = true
        guard loop == nil else { return }
        loop = Task { [weak self] in await self?.run() }
    }

    func stop() {
        wanted = false
        loop?.cancel()
        loop = nil
        closeSocket()
        state = .off
    }

    /// Drop the connection and start again now (e.g. the server address changed).
    func reconnect() {
        let wasWanted = wanted
        stop()
        if wasWanted { start() }
    }

    /// Where you are now. Sent when it's changed enough, or every 2 s.
    func update(position point: SIMD2<Float>) {
        guard point.x.isFinite, point.y.isFinite else { return }
        position = point
        guard state == .online else { return }
        let now = ContinuousClock.now
        let moved = lastSentPosition.map { simd_distance($0, point) } ?? .infinity
        let elapsed = lastSentAt.map { now - $0 } ?? .seconds(60)
        guard (moved >= 0.2 && elapsed >= .milliseconds(300)) || elapsed >= .seconds(2) else { return }
        sendPosition(point)
    }

    /// Where you want to go (the exhibit's `approach` point), or nil to cancel.
    func setDestination(_ point: SIMD2<Float>?) {
        let had = destination != nil
        destination = point
        guard state == .online else { return }
        if let point {
            send(["type": "destination", "x": Self.metres(point.x), "y": Self.metres(point.y)])
        } else if had {
            send(["type": "cancel"])
        }
    }

    /// Ask for the current guidance again (sends the destination once more).
    func resendDestination() {
        guard state == .online, let destination else { return }
        send(["type": "destination", "x": Self.metres(destination.x), "y": Self.metres(destination.y)])
    }

    // MARK: - Connection loop

    private func run() async {
        var pause: Double = 2
        while wanted, !Task.isCancelled {
            guard let session else { return }
            state = .connecting
            switch await session() {
            case .noServer:
                problem = nil
                state = .noServer
                await sleep(seconds: 20)
                continue
            case .unavailable(let reason):
                problem = reason
                state = .offline
                await sleep(seconds: pause)
                pause = min(pause * 2, 30)
                continue
            case .ready(let client):
                guard wanted, !Task.isCancelled else { return }
                guard let request = client.webSocketRequest() else {
                    problem = trNow("The server address isn't valid.", "Adres serwera jest nieprawidłowy.")
                    state = .offline
                    await sleep(seconds: 30)
                    continue
                }
                let task = URLSession.shared.webSocketTask(with: request)
                task.maximumMessageSize = 64 * 1024
                socket = task
                task.resume()
                do {
                    // The handshake is done once a ping comes back (the backend has no "hello" message).
                    try await ping(task)
                    guard wanted, socket === task else { throw CancellationError() }
                    print("[Server] connected to \(request.url?.absoluteString ?? "?")")
                    problem = nil
                    state = .online
                    pause = 2
                    resync()
                    let heartbeat = Task { [weak self] in await self?.heartbeat(task) }
                    defer { heartbeat.cancel() }
                    while wanted, socket === task {
                        let message = try await task.receive()
                        switch message {
                        case .string(let text): handle(text)
                        case .data(let data): handle(String(decoding: data, as: UTF8.self))
                        @unknown default: break
                        }
                    }
                } catch {
                    let status = (task.response as? HTTPURLResponse)?.statusCode
                    if status == 401 || status == 403 || task.closeCode == .policyViolation {
                        print("[Server] session refused (HTTP \(status.map { String($0) } ?? "-"), close \(task.closeCode.rawValue)); logging in again")
                        onSessionRejected?()
                        problem = trNow("The server ended the session; logging in again.", "Serwer zakończył sesję, loguję ponownie.")
                    } else {
                        problem = error.localizedDescription
                    }
                    print("[Server] connection lost: \(error.localizedDescription)")
                }
                if socket === task { closeSocket() }
                guard wanted, !Task.isCancelled else { return }
                state = .offline
                await sleep(seconds: pause)
                pause = min(pause * 2, 30)
            }
        }
    }

    /// After (re)connecting: position first, then the destination, as the contract asks.
    private func resync() {
        lastSentPosition = nil
        lastSentAt = nil
        if let position { sendPosition(position) }
        if let destination {
            send(["type": "destination", "x": Self.metres(destination.x), "y": Self.metres(destination.y)])
        }
    }

    /// Notices a dead connection (no pong) within ~25 s.
    private func heartbeat(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, socket === task else { return }
            do {
                try await ping(task)
            } catch {
                task.cancel(with: .goingAway, reason: nil)
                return
            }
        }
    }

    private func ping(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            task.sendPing { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private func closeSocket() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    private func sleep(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: - Sending and receiving

    private func sendPosition(_ point: SIMD2<Float>) {
        lastSentPosition = point
        lastSentAt = .now
        send(["type": "position", "x": Self.metres(point.x), "y": Self.metres(point.y)])
    }

    private func send(_ object: [String: Any]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { error in
            if let error { print("[Server] send failed: \(error.localizedDescription)") }
        }
    }

    private struct Head: Decodable {
        let type: String?
        let code: String?
        let message: String?
    }

    private func handle(_ text: String) {
        let data = Data(text.utf8)
        let decoder = JSONDecoder()
        guard let head = try? decoder.decode(Head.self, from: data) else { return }
        switch head.type {
        case "navigation":
            guard let navigation = try? decoder.decode(Navigation.self, from: data) else { return }
            if navigation.status == "awaiting_position", let position { sendPosition(position) }
            onNavigation?(navigation)
        case "policy":
            guard let policy = try? decoder.decode(Policy.self, from: data) else { return }
            self.policy = policy
            onPolicy?(policy)
        case "error":
            print("[Server] error \(head.code ?? "?"): \(head.message ?? "")")
            onError?(head.code ?? "UNKNOWN")
        default:
            break // "position" = just "got it"
        }
    }

    /// Metres with centimetre precision (keeps messages small; the server limit is 1024 bytes).
    private static func metres(_ value: Float) -> Double {
        (Double(value) * 100).rounded() / 100
    }
}

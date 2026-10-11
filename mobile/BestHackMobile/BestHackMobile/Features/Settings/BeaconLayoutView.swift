import SwiftUI
import simd

/// Settings → Beacon layout and steps: where your own beacons hang, how your room sits in the museum, and the
/// step tracking. Shows a live plan of the room with you on it.
struct BeaconLayoutView: View {
    @Bindable var positioning: PositionService

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $positioning.layout.enabled) {
                    SettingsRow(title: tr("Use my beacon layout", "Używaj mojego układu beaconów"), systemImage: "square.dashed", tint: Theme.accent)
                }
            } footer: {
                Text(tr("On: the beacons below, in your room, instead of the server's list. Walk around the room to walk through the museum.",
                        "Włączone: beacony poniżej, w Twoim pomieszczeniu, zamiast listy z serwera. Chodź po pokoju, żeby chodzić po muzeum."))
            }

            Section {
                RoomPlanView(positioning: positioning)
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                LiveStatusRow(positioning: positioning)
            } header: {
                Text(tr("Live", "Na żywo"))
            }

            beaconsSection
            roomSection
            motionSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(tr("Beacon layout", "Układ beaconów"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Beacons

    private var beaconsSection: some View {
        Section {
            ForEach(positioning.layout.beacons) { beacon in
                NavigationLink {
                    BeaconEditView(positioning: positioning, beaconID: beacon.id)
                } label: {
                    HStack(spacing: 12) {
                        Circle().fill(Theme.coral).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(beacon.name).font(Theme.body).foregroundStyle(Theme.ink)
                            Text("\(beacon.key) · x \(Self.metres(beacon.x)), y \(Self.metres(beacon.y)) · \(Int(beacon.txPower)) dBm")
                                .font(Theme.small)
                                .foregroundStyle(Theme.inkSoft)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { positioning.layout.beacons[$0].id }
                for id in ids { positioning.removeLayoutBeacon(id: id) }
            }
            if positioning.layout.beacons.isEmpty {
                Button {
                    positioning.addHeardBeacons()
                } label: {
                    Label(tr("Add the beacons I hear (up to 4)", "Dodaj słyszane beacony (do 4)"), systemImage: "wand.and.stars")
                }
            }
            Button {
                positioning.addLayoutBeacon()
            } label: {
                Label(tr("Add a beacon", "Dodaj beacon"), systemImage: "plus")
            }
        } header: {
            Text(tr("Beacons", "Beacony"))
        } footer: {
            Text(tr("Metres from one corner of the room: stand in that corner facing into the room, x = to your right, y = straight ahead. Four beacons, one in each corner, work best.",
                    "Metry od jednego rogu pokoju: stań w tym rogu twarzą do pokoju, x = w prawo, y = prosto przed siebie. Najlepiej cztery beacony, po jednym w każdym rogu."))
        }
    }

    // MARK: Room in the museum

    private var roomSection: some View {
        Section {
            NumberRow(title: tr("Calibration point x", "Punkt kalibracji x"), unit: "m", value: $positioning.layout.calibrationX)
            NumberRow(title: tr("Calibration point y", "Punkt kalibracji y"), unit: "m", value: $positioning.layout.calibrationY)
            Picker(tr("Facing there", "Kierunek patrzenia"), selection: $positioning.layout.facing) {
                ForEach(BeaconLayout.Facing.allCases) { facing in
                    Text(facing.title).tag(facing)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(tr("Walk scale", "Skala chodzenia"),
                               value: tr("1 m = \(Self.metres(positioning.layout.walkScale)) m in the museum",
                                         "1 m = \(Self.metres(positioning.layout.walkScale)) m w muzeum"))
                Slider(value: $positioning.layout.walkScale, in: 1...10, step: 0.5)
                    .tint(Theme.accent)
            }
            Stepper(value: $positioning.layout.beaconHeight, in: 0...3, step: 0.25) {
                LabeledContent(tr("Beacons above the phone", "Beacony nad telefonem"), value: "\(Self.metres(positioning.layout.beaconHeight)) m")
            }
        } header: {
            Text(tr("Your room in the museum", "Twój pokój w muzeum"))
        } footer: {
            Text(tr("Calibrating at this point, facing this way, puts you at the museum's calibration spot (\(positioning.spot.name)), facing its front. A bigger walk scale lets a small room cover more of the museum.",
                    "Kalibracja w tym punkcie i w tym kierunku stawia Cię w punkcie kalibracji muzeum, twarzą do jego przodu. Większa skala pozwala małym pokojem przejść większą część muzeum."))
        }
    }

    // MARK: Motion

    private var motionSection: some View {
        Section {
            Toggle(isOn: $positioning.useMotion) {
                SettingsRow(title: tr("Count my steps", "Licz moje kroki"), systemImage: "figure.walk", tint: Theme.mint)
            }
            if positioning.useMotion {
                Picker(tr("Walking direction from", "Kierunek marszu z"), selection: $positioning.headingSource) {
                    ForEach(PositionService.HeadingSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent(tr("Step length", "Długość kroku"), value: "×\(String(format: "%.2f", positioning.stepLengthFactor))")
                    Slider(value: $positioning.stepLengthFactor, in: 0.7...1.3, step: 0.05)
                        .tint(Theme.mint)
                }
                StepStatusRow(positioning: positioning)
            }
        } header: {
            Text(tr("Steps (motion sensors)", "Kroki (czujniki ruchu)"))
        } footer: {
            Text(tr("Each step moves you straight away; the beacons keep the steps from drifting. Direction: the phone while you hold it in front of you, otherwise your AirPods (Automatic). Both are lined up when you calibrate. If you move too little or too far on the map, change the step length.",
                    "Każdy krok od razu Cię przesuwa, a beacony pilnują, żeby kroki nie zniosły Cię w bok. Kierunek: telefon, gdy trzymasz go przed sobą, inaczej AirPodsy (Automatycznie). Oba ustawiają się przy kalibracji. Jeśli na mapie idziesz za mało albo za daleko, zmień długość kroku."))
        }
    }

    static func metres(_ value: Float) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}

// MARK: - Live plan

/// Top-down plan of the room: beacons (with the distance each one measures right now), the calibration point
/// with its facing arrow, and you (with your accuracy and walking direction). Redraws 5 times a second.
private struct RoomPlanView: View {
    let positioning: PositionService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { _ in
            let snapshot = PlanSnapshot(positioning: positioning)
            Canvas { context, size in
                draw(snapshot, in: &context, size: size)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.cardSunken))
            .accessibilityElement()
            .accessibilityLabel(tr("Room plan", "Plan pokoju"))
            .accessibilityValue(String(format: "x %.1f, y %.1f", snapshot.you.x, snapshot.you.y))
        }
    }

    private func draw(_ plan: PlanSnapshot, in context: inout GraphicsContext, size: CGSize) {
        // Fit everything (with a margin) into the view, y up.
        var low = plan.you, high = plan.you
        for point in plan.beacons.map(\.point) + [plan.calibration] {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }
        low -= SIMD2(1, 1)
        high += SIMD2(1, 1)
        let span = simd_max(high - low, SIMD2(3, 3))
        let scale = min(Float(size.width) / span.x, Float(size.height) / span.y)
        let offset = SIMD2(Float(size.width), Float(size.height)) / 2 - (low + high) / 2 * SIMD2(scale, -scale)
        func screen(_ p: SIMD2<Float>) -> CGPoint {
            CGPoint(x: CGFloat(p.x * scale + offset.x), y: CGFloat(-p.y * scale + offset.y))
        }
        let metre = CGFloat(scale)

        // 1 m grid.
        var grid = Path()
        for x in Int(low.x.rounded(.down))...Int(high.x.rounded(.up)) {
            grid.move(to: screen(SIMD2(Float(x), low.y - 5)))
            grid.addLine(to: screen(SIMD2(Float(x), high.y + 5)))
        }
        for y in Int(low.y.rounded(.down))...Int(high.y.rounded(.up)) {
            grid.move(to: screen(SIMD2(low.x - 5, Float(y))))
            grid.addLine(to: screen(SIMD2(high.x + 5, Float(y))))
        }
        context.stroke(grid, with: .color(Theme.line), lineWidth: 0.5)

        // The room's corner (0, 0) with its axes.
        let origin = screen(.zero)
        var axes = Path()
        axes.move(to: origin)
        axes.addLine(to: screen(SIMD2(1, 0)))
        axes.move(to: origin)
        axes.addLine(to: screen(SIMD2(0, 1)))
        context.stroke(axes, with: .color(Theme.inkSoft), lineWidth: 1.5)
        context.draw(Text("x").font(.caption2).foregroundStyle(Theme.inkSoft), at: screen(SIMD2(1.25, 0)))
        context.draw(Text("y").font(.caption2).foregroundStyle(Theme.inkSoft), at: screen(SIMD2(0, 1.25)))

        // Beacons and the distance each one measures.
        for beacon in plan.beacons {
            let centre = screen(beacon.point)
            if let distance = beacon.distance {
                let r = CGFloat(distance) * metre
                let ring = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
                context.stroke(ring, with: .color(Theme.coral.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            let dot = Path(ellipseIn: CGRect(x: centre.x - 6, y: centre.y - 6, width: 12, height: 12))
            context.fill(dot, with: .color(beacon.distance == nil ? Theme.lineStrong : Theme.coral))
            context.draw(Text(beacon.label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.ink),
                         at: CGPoint(x: centre.x, y: centre.y - 14))
        }

        // Calibration point and which way to face there.
        let spot = screen(plan.calibration)
        context.stroke(Path(CGRect(x: spot.x - 5, y: spot.y - 5, width: 10, height: 10)), with: .color(Theme.accent), lineWidth: 1.5)
        let tip = screen(plan.calibration + plan.calibrationFacing * 0.8)
        var arrow = Path()
        arrow.move(to: spot)
        arrow.addLine(to: tip)
        context.stroke(arrow, with: .color(Theme.accent), lineWidth: 1.5)

        // You.
        let you = screen(plan.you)
        if let accuracy = plan.accuracy {
            let r = max(CGFloat(accuracy) * metre, 8)
            context.fill(Path(ellipseIn: CGRect(x: you.x - r, y: you.y - r, width: r * 2, height: r * 2)), with: .color(Theme.accent.opacity(0.15)))
        }
        if let heading = plan.heading {
            var walk = Path()
            walk.move(to: you)
            walk.addLine(to: screen(plan.you + heading * 1.0))
            context.stroke(walk, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        context.fill(Path(ellipseIn: CGRect(x: you.x - 8, y: you.y - 8, width: 16, height: 16)), with: .color(Theme.accent))
        context.stroke(Path(ellipseIn: CGRect(x: you.x - 8, y: you.y - 8, width: 16, height: 16)), with: .color(.white), lineWidth: 2)
    }
}

/// Everything the plan draws, read once per frame.
private struct PlanSnapshot {
    struct Beacon {
        let point: SIMD2<Float>
        let label: String
        /// Floor distance measured right now, nil when not heard lately.
        let distance: Float?
    }

    let beacons: [Beacon]
    let calibration: SIMD2<Float>
    let calibrationFacing: SIMD2<Float>
    let you: SIMD2<Float>
    let accuracy: Float?
    let heading: SIMD2<Float>?

    init(positioning: PositionService) {
        let frame = positioning.frame
        let sightings = Dictionary(positioning.sightings().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let layout = positioning.layout
        if positioning.usesLayout {
            beacons = layout.beacons.map { beacon in
                let sighting = sightings[beacon.key]
                let distance = sighting.flatMap { $0.secondsAgo < 4 ? $0.distance : nil }.map { positioning.floorDistance($0) }
                return Beacon(point: beacon.point, label: beacon.name, distance: distance)
            }
            calibration = layout.calibrationPoint
            let angle = layout.facing.angle
            calibrationFacing = SIMD2(-sin(angle), cos(angle))
        } else {
            // Server beacons: show the ones near you (the museum is big).
            let here = positioning.framePosition
            beacons = positioning.directory.beacons.compactMap { beacon in
                guard let point = positioning.anchorPoint(id: beacon.id), simd_distance(point, here) < 25 else { return nil }
                let sighting = sightings[beacon.id]
                let distance = sighting.flatMap { $0.secondsAgo < 4 ? $0.distance : nil }.map { positioning.floorDistance($0) }
                return Beacon(point: point, label: beacon.name ?? beacon.id, distance: distance)
            }
            calibration = frame.toFrame(positioning.spot.point)
            calibrationFacing = frame.direction(museumYaw: positioning.spot.yaw)
        }
        you = positioning.framePosition
        accuracy = positioning.frameAccuracy
        heading = positioning.currentHeading().map { frame.direction(museumYaw: $0.yaw) }
    }
}

/// "x 2.3 m, y 1.8 m · ±0.8 m · 4 beacons + steps"
private struct LiveStatusRow: View {
    let positioning: PositionService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let you = positioning.framePosition
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "x %.1f m, y %.1f m", you.x, you.y)
                     + (positioning.frameAccuracy.map { String(format: " · ±%.1f m", $0) } ?? ""))
                    .font(Theme.bodyBold)
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text(positioning.statusText)
                    .font(Theme.small)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

/// "123 steps · last 0.68 m · direction: phone"
private struct StepStatusRow: View {
    let positioning: PositionService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let motion = positioning.motion
            let direction: String = {
                guard let heading = positioning.currentHeading() else {
                    return tr("unknown: calibrate first", "nieznany: najpierw skalibruj")
                }
                return heading.source.title
            }()
            VStack(alignment: .leading, spacing: 2) {
                if !motion.isAvailable {
                    Text(tr("This device has no motion sensors.", "To urządzenie nie ma czujników ruchu."))
                } else if !motion.isRunning {
                    Text(tr("Starts with the guide (after calibration).", "Rusza razem z przewodnikiem (po kalibracji)."))
                } else {
                    Text(tr("\(motion.stepCount) steps · last \(String(format: "%.2f", motion.lastStepLength)) m",
                            "Kroki: \(motion.stepCount) · ostatni \(String(format: "%.2f", motion.lastStepLength)) m"))
                        .monospacedDigit()
                    Text(tr("Direction: ", "Kierunek: ") + direction)
                }
            }
            .font(Theme.small)
            .foregroundStyle(Theme.inkSoft)
        }
    }
}

/// A labelled number field ("Calibration point x  [2.5] m").
private struct NumberRow: View {
    var title: String
    var unit: String
    @Binding var value: Float

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: FloatingPointFormatStyle<Float>(locale: .current).precision(.fractionLength(0...2)))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
                Text(unit).foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

// MARK: - One beacon

/// Edit one beacon of your layout: which beacon (pick one you hear), where it hangs, its signal at 1 m.
struct BeaconEditView: View {
    let positioning: PositionService
    let beaconID: UUID

    @State private var draft: BeaconLayout.Beacon
    @State private var isMeasuring = false
    @State private var measureNote: String?
    @State private var deleted = false
    @Environment(\.dismiss) private var dismiss

    init(positioning: PositionService, beaconID: UUID) {
        self.positioning = positioning
        self.beaconID = beaconID
        _draft = State(initialValue: positioning.layout.beacons.first { $0.id == beaconID }
                       ?? BeaconLayout.Beacon(name: "", major: 1, minor: 1, x: 0, y: 0))
    }

    var body: some View {
        Form {
            Section {
                TextField(tr("Name", "Nazwa"), text: $draft.name)
            } header: {
                Text(tr("Name", "Nazwa"))
            }

            Section {
                Stepper(value: $draft.major, in: 0...65535) {
                    LabeledContent("Major", value: "\(draft.major)")
                }
                Stepper(value: $draft.minor, in: 0...65535) {
                    LabeledContent("Minor", value: "\(draft.minor)")
                }
                HeardPicker(positioning: positioning, selected: draft.key) { heard in
                    draft.major = heard.major
                    draft.minor = heard.minor
                }
            } header: {
                Text(tr("Which beacon", "Który beacon"))
            } footer: {
                Text(tr("Tap one the phone hears (strongest first). Hold the phone right next to a beacon: it'll be at the top.",
                        "Stuknij jeden ze słyszanych (najsilniejsze na górze). Przyłóż telefon do beacona: będzie pierwszy."))
            }

            Section {
                NumberRow(title: "x", unit: "m", value: $draft.x)
                NumberRow(title: "y", unit: "m", value: $draft.y)
            } header: {
                Text(tr("Where it hangs", "Gdzie wisi"))
            } footer: {
                Text(tr("Metres from the room's corner: x to the right, y straight ahead.", "Metry od rogu pokoju: x w prawo, y prosto."))
            }

            Section {
                Stepper(value: $draft.txPower, in: -100 ... -30, step: 1) {
                    LabeledContent(tr("Signal at 1 m", "Sygnał z 1 m"), value: "\(Int(draft.txPower)) dBm")
                }
                Button {
                    measure()
                } label: {
                    if isMeasuring {
                        HStack {
                            ProgressView()
                            Text(tr("Measuring… hold still", "Mierzę… nie ruszaj się"))
                        }
                    } else {
                        Label(tr("Measure: hold the phone 1 m from it", "Zmierz: trzymaj telefon 1 m od niego"), systemImage: "ruler")
                    }
                }
                .disabled(isMeasuring)
                if let measureNote {
                    Text(measureNote).font(Theme.small).foregroundStyle(Theme.inkSoft)
                }
            } header: {
                Text(tr("Signal", "Sygnał"))
            } footer: {
                Text(tr("How strong this beacon is 1 m away. Measuring it makes the distances much better.",
                        "Jak silny jest ten beacon z odległości 1 m. Pomiar mocno poprawia odległości."))
            }

            Section {
                Button(tr("Delete beacon", "Usuń beacon"), role: .destructive) {
                    deleted = true
                    positioning.removeLayoutBeacon(id: beaconID)
                    dismiss()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(draft.name.isEmpty ? tr("Beacon", "Beacon") : draft.name)
        .onDisappear {
            if !deleted { positioning.updateLayoutBeacon(draft) }
        }
    }

    private func measure() {
        isMeasuring = true
        measureNote = nil
        let major = draft.major, minor = draft.minor
        Task {
            let result = await positioning.measurePower(major: major, minor: minor)
            isMeasuring = false
            if let result {
                draft.txPower = result.rounded()
                measureNote = tr("Measured \(Int(result.rounded())) dBm.", "Zmierzono \(Int(result.rounded())) dBm.")
            } else {
                measureNote = tr("This beacon wasn't heard. Check major and minor.", "Nie słychać tego beacona. Sprawdź major i minor.")
            }
        }
    }
}

/// The beacons heard right now, strongest first; tap one to use it.
private struct HeardPicker: View {
    let positioning: PositionService
    var selected: String
    var onPick: (PositionService.Heard) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let heard = Array(positioning.heardBeacons().prefix(6))
            if heard.isEmpty {
                Text(tr("No beacons heard right now.", "Teraz nie słychać żadnych beaconów."))
                    .font(Theme.small)
                    .foregroundStyle(Theme.inkSoft)
            } else {
                ForEach(heard) { beacon in
                    Button {
                        onPick(beacon)
                    } label: {
                        HStack {
                            Image(systemName: beacon.id == selected ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                                .foregroundStyle(beacon.id == selected ? Theme.accent : Theme.coral)
                            Text(beacon.id).foregroundStyle(Theme.ink).monospacedDigit()
                            Spacer()
                            Text("\(beacon.rssi) dBm").foregroundStyle(Theme.inkSoft).monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

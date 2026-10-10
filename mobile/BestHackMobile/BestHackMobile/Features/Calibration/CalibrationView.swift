import SwiftUI

/// Calibration, at the start of every visit: stand on the known spot, face the front, tap Calibrate.
/// One screen, no scrolling.
///
/// That one tap lines up all the systems with the museum: your position (beacons), which way is front (AirPods),
/// and each beacon's signal strength at that spot.
struct CalibrationView: View {
    let guide: GuideModel
    let mode: UserMode
    var onDone: () -> Void

    private enum Phase: Equatable {
        case ready
        case measuring
        case done(beacons: Int, airPods: Bool)
    }

    @State private var phase: Phase = .ready
    @State private var progress: Double = 0

    private static let holdStill: Double = 3

    private var spot: CalibrationSpot { guide.positioning.spot }

    /// Where to stand, in the app's language (custom spots from the server keep their own words).
    private var spotName: String {
        switch spot.name {
        case CalibrationSpot.southEntrance.name: tr(spot.name, "znaczniku startowym tuż za Wejściem Południowym")
        case "the calibration marker": tr(spot.name, "znaczniku kalibracyjnym")
        default: spot.name
        }
    }

    private var spotFacing: String {
        switch spot.facing {
        case CalibrationSpot.southEntrance.facing: tr(spot.facing, "w stronę dużej hali i Pali Totemicznych")
        case "the way the arrow on the marker points": tr(spot.facing, "w kierunku strzałki na znaczniku")
        default: spot.facing
        }
    }

    var body: some View {
        Group {
            if mode == .blind {
                listeningLayout
            } else {
                mapLayout
            }
        }
        .onAppear {
            // Registered first, so the instructions below belong to this screen (and stop when you leave it).
            guide.screenAppeared(.calibration)
            guide.start(mode: mode)
            if mode == .blind {
                Haptics.shared.attention()
                guide.speak([.init(text: instructionsSpoken)])
            }
        }
        .sensoryFeedback(.success, trigger: phase) { _, new in
            if case .done = new { return true }
            return false
        }
    }

    private var instructionsSpoken: String {
        tr("Let's calibrate. Stand on \(spotName), face \(spotFacing), and keep your AirPods in. When you're ready, tap the bottom half of the screen, then hold still for three seconds.",
           "Kalibracja. Stań na \(spotName), zwróć się \(spotFacing) i miej założone AirPodsy. Kiedy będziesz gotowy, stuknij w dolną połowę ekranu i nie ruszaj się przez trzy sekundy.")
    }

    // MARK: - Map mode layout (fits one screen)

    private var mapLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Calibrate", "Kalibracja"))
                    .font(Theme.title(.largeTitle))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(tr("So the map, the arrows and the sounds all point the right way.",
                        "Żeby mapa, strzałki i dźwięki wskazywały właściwy kierunek."))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 12)

            SpotIllustration(phase: phaseValue, progress: progress)
                .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 150)
                .layoutPriority(-1)

            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: tr("Stand on \(spotName).", "Stań na \(spotName)."))
                StepRow(number: 2, text: tr("Put your AirPods in and face \(spotFacing).", "Załóż AirPodsy i zwróć się \(spotFacing)."))
                StepRow(number: 3, text: tr("Tap Calibrate and hold still for 3 seconds.", "Stuknij „Kalibruj” i nie ruszaj się przez 3 sekundy."))
            }

            statusCard

            Spacer(minLength: 0)

            VStack(spacing: 4) {
                mainButton
                if phase == .ready {
                    Button(tr("Skip for now", "Pomiń")) { skip() }
                        .buttonStyle(AppButtonStyle(kind: .quiet, height: 40))
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.page.ignoresSafeArea())
    }

    private var phaseValue: Int {
        switch phase {
        case .ready: 0
        case .measuring: 1
        case .done: 2
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusRow(
                systemImage: "airpodspro",
                title: guide.head.status == .tracking ? tr("AirPods connected", "AirPodsy połączone") : tr("AirPods not connected", "AirPodsy niepołączone"),
                detail: guide.head.status == .tracking ? tr("The sound will turn with your head.", "Dźwięk będzie obracał się z głową.") : headphonesHint,
                isGood: guide.head.status == .tracking
            )
            Divider()
            StatusRow(
                systemImage: "dot.radiowaves.left.and.right",
                title: beaconTitle,
                detail: beaconDetail,
                isGood: guide.positioning.beaconsHeard > 0
            )
        }
        .card(padding: 12)
    }

    private var headphonesHint: String {
        switch guide.head.status {
        case .denied: tr("Motion access is off. Turn it on in Settings › Privacy › Motion.",
                         "Dostęp do ruchu jest wyłączony. Włącz go w Ustawieniach › Prywatność › Ruch.")
        case .unsupported: tr("Head tracking needs AirPods Pro, Max or 3rd generation or newer.",
                              "Śledzenie głowy wymaga AirPods Pro, Max albo 3. generacji lub nowszych.")
        default: tr("Without them the app can't tell which way you face.", "Bez nich aplikacja nie wie, w którą stronę patrzysz.")
        }
    }

    private var beaconTitle: String {
        let count = guide.positioning.beaconsHeard
        return count > 0 ? tr("\(count) beacon\(count == 1 ? "" : "s") nearby", "Beacony w pobliżu: \(count)")
                         : tr("Looking for beacons…", "Szukam beaconów…")
    }

    private var beaconDetail: String {
        let positioning = guide.positioning
        if let problem = positioning.scanner.problem { return problem }
        if positioning.directory.beacons.isEmpty {
            return positioning.directoryError ?? tr("The beacon positions haven't loaded from the server yet.",
                                                    "Pozycje beaconów jeszcze nie przyszły z serwera.")
        }
        if positioning.beaconsHeard == 0, !positioning.unknownBeacons.isEmpty {
            return tr("Beacons heard (\(positioning.unknownBeacons.joined(separator: ", "))), but they aren't in the server's list.",
                      "Słychać beacony (\(positioning.unknownBeacons.joined(separator: ", "))), ale nie ma ich na liście z serwera.")
        }
        return tr("\(positioning.directory.beacons.count) beacons are set up in this museum.",
                  "Beacony w muzeum: \(positioning.directory.beacons.count).")
    }

    @ViewBuilder
    private var mainButton: some View {
        switch phase {
        case .ready:
            Button(tr("Calibrate", "Kalibruj")) { calibrate() }
                .buttonStyle(AppButtonStyle(kind: .primary))
        case .measuring:
            Button {} label: {
                Text(tr("Hold still…", "Nie ruszaj się…"))
            }
            .buttonStyle(AppButtonStyle(kind: .primary))
            .disabled(true)
        case .done:
            Button(tr("Start exploring", "Zaczynamy zwiedzanie")) { onDone() }
                .buttonStyle(AppButtonStyle(kind: .primary))
        }
    }

    // MARK: - Listening mode layout

    private var listeningLayout: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("Calibrate", "Kalibracja"))
                    .font(.system(.largeTitle, weight: .heavy))
                    .accessibilityAddTraits(.isHeader)
                Text(tr("Stand on \(spotName). Face \(spotFacing). Keep your AirPods in.",
                        "Stań na \(spotName). Zwróć się \(spotFacing). Miej założone AirPodsy."))
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    guide.userTapped()
                    guide.speak([.init(text: instructionsSpoken)])
                } label: {
                    Label(tr("Hear the instructions again", "Posłuchaj instrukcji jeszcze raz"), systemImage: "speaker.wave.2.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(Capsule().fill(Color(white: 0.2)))
                }
                .buttonStyle(.plain)
                if phase == .ready {
                    Button {
                        skip()
                    } label: {
                        Text(tr("Skip calibration", "Pomiń kalibrację"))
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Capsule().fill(Color(white: 0.2)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // The bottom half is one big button.
            VStack(spacing: 10) {
                Text(listeningButtonTitle)
                    .font(.system(.largeTitle, weight: .heavy))
                    .multilineTextAlignment(.center)
                if phase == .measuring {
                    ProgressLine(value: progress, tint: .black, height: 10)
                        .padding(.horizontal, 40)
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(hex: 0xFFD60A)))
            .contentShape(Rectangle())
            .onTapGesture {
                switch phase {
                case .ready: calibrate()
                case .measuring: break
                case .done:
                    guide.userTapped()
                    onDone()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(listeningButtonTitle)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if phase == .ready { calibrate() } else if case .done = phase { onDone() }
            }
        }
        .padding(6)
        .background(Color.black.ignoresSafeArea())
    }

    private var listeningButtonTitle: String {
        switch phase {
        case .ready: tr("Tap to calibrate", "Stuknij, żeby skalibrować")
        case .measuring: tr("Hold still…", "Nie ruszaj się…")
        case .done: tr("Calibrated. Tap to start.", "Skalibrowano. Stuknij, żeby zacząć.")
        }
    }

    // MARK: - Actions

    private func calibrate() {
        guard phase == .ready else { return }
        guide.userTapped()
        phase = .measuring
        progress = 0
        guide.beginCalibration()
        if mode == .blind { Haptics.shared.selected() }
        Task {
            let steps = 30
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(Int(Self.holdStill * 1000) / steps))
                progress = Double(step) / Double(steps)
            }
            let result = guide.finishCalibration()
            phase = .done(beacons: result.beacons, airPods: result.airPods)
            if mode == .blind {
                Haptics.shared.confirmed()
                guide.speakAfterCurrent([.init(text: tr("Tap the bottom half of the screen to start.", "Stuknij w dolną połowę ekranu, żeby zacząć."))])
            }
            // Map mode: go straight on after a moment. Listening mode waits for a tap (it's announced).
            if mode == .standard {
                try? await Task.sleep(for: .milliseconds(1200))
                if case .done = phase { onDone() }
            }
        }
    }

    private func skip() {
        guide.userTapped()
        guide.skipCalibration()
        onDone()
    }
}

// MARK: - Pieces

/// A marker on the floor with an arrow for "front"; fills up while measuring, ticks when done.
private struct SpotIllustration: View {
    var phase: Int
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(Theme.accentSoft)
                Circle()
                    .trim(from: 0, to: phase == 1 ? progress : (phase == 2 ? 1 : 0))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
                if phase == 2 {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: size * 0.18, weight: .bold))
                            .foregroundStyle(Theme.coral)
                        Image(systemName: "figure.stand")
                            .font(.system(size: size * 0.3, weight: .regular))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.25), value: phase)
        .accessibilityHidden(true)
    }
}

private struct StepRow: View {
    var number: Int
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.accent))
            Text(text)
                .font(Theme.caption)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatusRow: View {
    var systemImage: String
    var title: String
    var detail: String
    var isGood: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isGood ? Theme.mintText : Theme.inkSoft)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.bodyBold)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.small)
                    .foregroundStyle(Theme.inkSoft)
                    .lineLimit(3)
                    .minimumScaleFactor(0.9)
            }
            Spacer(minLength: 0)
            Image(systemName: isGood ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isGood ? Theme.mint : Theme.lineStrong)
        }
        .accessibilityElement(children: .combine)
    }
}

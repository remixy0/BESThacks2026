import simd
import SwiftUI

/// Listening mode, for blind and low-vision visitors. No map: the screen is split into four big, brightly coloured
/// corners, each holding one of the four exhibits closest to you, and a "Talk" strip along the bottom.
///
/// 1. The guide says what's in each corner ("Lewy górny, żółty: Máximo, 20 metrów prosto…") and the phone gives
///    three hard knocks: time to choose. Then it listens.
/// 2. Choose by tapping a corner, or by saying its position, colour, number or the exhibit's name.
///    One long buzz, and the guide repeats your choice and asks you to confirm.
/// 3. Tap the same corner again, or say "tak": long-short-long buzz, and guidance starts.
/// Hold anywhere to hear the four options again.
///
/// While walking, the screen has two halves: top = "which way?" (green when you face the right way),
/// bottom = stop (tap twice).
struct ListenModeView: View {
    let guide: GuideModel
    let visits: VisitLog
    var onSettings: () -> Void

    @State private var choices: [MuseumInfo.Exhibit] = []
    @State private var pending: String?
    @State private var pendingSince = Date.distantPast
    @State private var stopArmedSince: Date?
    @State private var lastAnnouncedPosition = SIMD2<Float>(repeating: .infinity)
    /// Listen once the guide stops talking (after the options or a choice were read out).
    @State private var listenWhenQuiet = false

    /// The four corners: where on the screen, and a colour you can tell apart easily (black text on all of them).
    private struct Corner {
        let name: String
        let colourName: String
        let color: Color
    }

    private var corners: [Corner] {
        [
            Corner(name: tr("Top left", "Lewy górny"), colourName: tr("yellow", "żółty"), color: Color(hex: 0xFFD60A)),
            Corner(name: tr("Top right", "Prawy górny"), colourName: tr("blue", "niebieski"), color: Color(hex: 0x3CCBFF)),
            Corner(name: tr("Bottom left", "Lewy dolny"), colourName: tr("pink", "różowy"), color: Color(hex: 0xFF5FA8)),
            Corner(name: tr("Bottom right", "Prawy dolny"), colourName: tr("green", "zielony"), color: Color(hex: 0x4BE07C)),
        ]
    }

    var body: some View {
        VStack(spacing: 6) {
            menuBar
            if let target = guide.target {
                walkingHalves(target)
            } else {
                choiceGrid
            }
            talkStrip
        }
        .padding(6)
        .background(Color.black.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear {
            refreshChoices()
            announceChoices(queued: guide.audio.isSpeaking)
        }
        .onChange(of: guide.target?.key) { old, new in
            // Guidance ended (stopped or arrived): offer four new exhibits, after the arrival story.
            if old != nil, new == nil {
                refreshChoices()
                announceChoices(queued: true)
            }
            stopArmedSince = nil
            pending = nil
        }
        .onChange(of: guide.arrivalEvent) { _, _ in
            // "You're already at…" (no guidance started): offer the next ones after the story.
            if guide.target == nil {
                refreshChoices()
                announceChoices(queued: true)
            }
        }
        .onChange(of: guide.speechFinishedEvent) { _, _ in
            guard listenWhenQuiet, guide.target == nil else { return }
            listenWhenQuiet = false
            Task { await listenAndAct() }
        }
        // "Hej Bloop": listen for a command right away.
        .onChange(of: guide.wakeEvent) { _, _ in
            guard !guide.voiceInput.isBusy else { return }
            listenWhenQuiet = false
            Haptics.shared.selected()
            Task { await listenAndAct() }
        }
        .onChange(of: guide.audio.speechNotice) { _, notice in
            if let notice { AccessibilityNotification.Announcement(notice).post() }
        }
    }

    // MARK: - Top bar

    private var menuBar: some View {
        HStack(spacing: 10) {
            Button(action: onSettings) {
                Label(tr("Settings", "Ustawienia"), systemImage: "gearshape.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(Capsule().fill(Color(white: 0.2)))
            }
            .buttonStyle(.plain)
            .accessibilityHint(tr("Mode, voice, language, calibration and account", "Tryb, głos, język, kalibracja i konto"))

            Spacer(minLength: 0)

            Text(guide.placeName.isEmpty ? "Field Museum" : guide.placeName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(white: 0.75))
                .lineLimit(1)
                .accessibilityLabel(tr("You are in: ", "Jesteś tutaj: ") + (guide.placeName.isEmpty ? "Field Museum" : guide.placeName))
        }
    }

    // MARK: - Choosing

    private var choiceGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                corner(0)
                corner(1)
            }
            HStack(spacing: 6) {
                corner(2)
                corner(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func corner(_ index: Int) -> some View {
        let corner = corners[index]
        let exhibit = index < choices.count ? choices[index] : nil
        let isPending = exhibit != nil && exhibit?.key == pending
        let dimmed = pending != nil && !isPending

        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)

        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(corner.name.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1)
                if let exhibit {
                    Text(exhibit.name)
                        .font(.system(.title2, weight: .heavy))
                        .lineLimit(isPending ? 2 : 4)
                        .minimumScaleFactor(0.6)
                    Text(guide.directions(to: exhibit))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if !isPending, visits.contains(exhibit.key) {
                        Label(tr("Visited", "Odwiedzony"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.bold))
                    }
                } else {
                    Text(tr("Nothing here", "Pusto"))
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 0)
                }
            }
            .foregroundStyle(exhibit == nil ? Color(white: 0.6) : Color.black)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // Chosen: a solid black band across the bottom says what to do next (the text always fits).
            if isPending {
                ConfirmBand()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(shape.fill(exhibit == nil ? Color(white: 0.16) : corner.color))
        .clipShape(shape)
        .overlay {
            if isPending {
                shape.strokeBorder(Color.white, lineWidth: 6)
            }
        }
        .opacity(dimmed ? 0.45 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { tapCorner(index) }
        .onLongPressGesture(minimumDuration: 0.7) { repeatChoices() }
        .animation(.easeOut(duration: 0.15), value: pending)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exhibit.map { "\(corner.name). \($0.name). \(guide.directions(to: $0))." } ?? "\(corner.name). " + tr("Nothing here.", "Pusto."))
        .accessibilityHint(isPending ? tr("Double-tap again to go there.", "Stuknij dwukrotnie jeszcze raz, żeby tam iść.")
                                     : tr("Double-tap to choose.", "Stuknij dwukrotnie, żeby wybrać."))
        .accessibilityAddTraits(isPending ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { tapCorner(index) }
        .accessibilityAction(named: tr("Hear all four options", "Posłuchaj wszystkich opcji")) { repeatChoices() }
    }

    private func tapCorner(_ index: Int) {
        let corner = corners[index]
        guard index < choices.count else {
            Haptics.shared.warning()
            guide.speak([.init(text: corner.name + ": " + tr("nothing here.", "pusto."))])
            return
        }
        choose(choices[index], corner: corner)
    }

    /// First choice: buzz and ask to confirm. Same choice again: go.
    private func choose(_ exhibit: MuseumInfo.Exhibit, corner: Corner?) {
        if guide.voiceInput.state == .listening { guide.voiceInput.finishListening() }
        if pending == exhibit.key, Date().timeIntervalSince(pendingSince) < 20 {
            confirm(exhibit)
        } else {
            pending = exhibit.key
            pendingSince = Date()
            Haptics.shared.selected()
            let where_ = corner.map { "\($0.name), \($0.colourName): " } ?? ""
            guide.speak([.init(text: where_ + "\(exhibit.name), \(guide.spokenDirections(to: exhibit)). "
                               + tr("Tap again, or say yes.", "Stuknij jeszcze raz albo powiedz: tak."),
                               toward: exhibit.floorPoint)])
            listenWhenQuiet = true
        }
    }

    private func confirm(_ exhibit: MuseumInfo.Exhibit) {
        pending = nil
        listenWhenQuiet = false
        Haptics.shared.confirmed()
        guide.navigate(to: exhibit)
    }

    private func repeatChoices() {
        pending = nil
        // Moved since the options were made? Then offer the closest ones again.
        if simd_distance(lastAnnouncedPosition, guide.position) > 4 { refreshChoices() }
        announceChoices(queued: false)
    }

    private func refreshChoices() {
        guard let info = guide.info else { return }
        choices = info.nearest(to: guide.position, count: 4, excluding: guide.atExhibit?.key)
        pending = nil
        lastAnnouncedPosition = guide.position
    }

    /// "Choose an exhibit. Top left, yellow: …" — one sentence, so it starts quickly and flows without gaps.
    private func announceChoices(queued: Bool) {
        guard !choices.isEmpty else { return }
        var text = tr("Choose an exhibit. ", "Wybierz eksponat. ")
        for (index, exhibit) in choices.enumerated() {
            let corner = corners[index]
            text += "\(corner.name), \(corner.colourName): \(exhibit.name), \(guide.spokenDirections(to: exhibit)). "
        }
        text += tr("Tap a corner, or say its colour or the exhibit's name. Hold to hear this again.",
                   "Stuknij róg albo powiedz kolor lub nazwę eksponatu. Przytrzymaj, żeby usłyszeć to jeszcze raz.")
        let items: [GuideModel.Utterance] = [.init(text: text)]
        if queued {
            guide.speakAfterCurrent(items)
            if !guide.audio.isSpeaking { Haptics.shared.attention() }
        } else {
            Haptics.shared.attention()
            guide.speak(items)
        }
        listenWhenQuiet = guide.listenOnArrival
    }

    // MARK: - Talking

    /// Listens once and acts on it: a corner, colour, number or exhibit name chooses; "tak" confirms.
    private func listenAndAct() async {
        guard let result = await guide.listen() else {
            if let problem = guide.voiceInput.problem { guide.speak([.init(text: problem)]) }
            return
        }
        let heard = result.heard

        if guide.target != nil {
            // Walking: which way, story, stop talking…
            if !guide.perform(heard) {
                guide.sayNotUnderstood(result.text, hint: tr("Say: which way, tell me, or stop.", "Powiedz: którędy, opowiedz albo stop."))
            }
            return
        }

        if heard.yes, let pending, let exhibit = guide.info?.exhibits.first(where: { $0.key == pending }) {
            confirm(exhibit)
            return
        }
        if heard.no, pending != nil {
            pending = nil
            guide.speak([.init(text: tr("Okay. Choose another one.", "Dobrze. Wybierz inny."))])
            return
        }
        // A corner (position, colour or number) or an exhibit's name.
        if let index = heard.corner, index < choices.count {
            choose(choices[index], corner: corners[index])
            return
        }
        if let key = heard.exhibits.first {
            if let index = choices.firstIndex(where: { $0.key == key }) {
                choose(choices[index], corner: corners[index])
            } else if let exhibit = guide.info?.exhibits.first(where: { $0.key == key }) {
                choose(exhibit, corner: nil)
            }
            return
        }
        if heard.next || heard.repeatIt {
            repeatChoices()
            return
        }
        if guide.perform(heard) { return }
        guide.sayNotUnderstood(result.text, hint: tr("Say a colour, a corner, or an exhibit's name. For example: yellow.",
                                                     "Powiedz kolor, róg albo nazwę eksponatu. Na przykład: żółty."))
    }

    /// The strip along the bottom: tap to talk (white, so it's easy to find and different from the corners).
    private var talkStrip: some View {
        let state = guide.voiceInput.state
        return HStack(spacing: 16) {
            Image(systemName: state == .idle ? "mic.fill" : (state == .listening ? "waveform" : "ellipsis"))
                .font(.system(size: 38, weight: .bold))
                .frame(width: 48)
                .symbolEffect(.pulse, isActive: state != .idle)
            VStack(alignment: .leading, spacing: 2) {
                Text(state == .idle ? tr("Talk", "Mów") : (state == .listening ? tr("Listening…", "Słucham…") : tr("Recognizing…", "Rozpoznaję…")))
                    .font(.system(.largeTitle, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if state == .idle, guide.wakeWordEnabled {
                    Text(tr("or say “\(guide.wakePhrase)”", "albo powiedz „\(guide.wakePhrase)”"))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
            if state == .listening {
                LevelBars(level: guide.voiceInput.recorder.level, color: .black)
                    .scaleEffect(1.4)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(state == .idle ? Color.white : Color(hex: 0xFFE9A8)))
        .contentShape(Rectangle())
        .onTapGesture { talkTapped() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state == .idle ? tr("Talk", "Mów") : tr("Listening", "Słucham"))
        .accessibilityHint(tr("Double-tap, then say a colour, a corner or an exhibit's name.",
                              "Stuknij dwukrotnie i powiedz kolor, róg albo nazwę eksponatu."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { talkTapped() }
    }

    private func talkTapped() {
        switch guide.voiceInput.state {
        case .listening: guide.voiceInput.finishListening()
        case .thinking: break
        case .idle:
            listenWhenQuiet = false
            Haptics.shared.selected()
            Task { await listenAndAct() }
        }
    }

    // MARK: - Walking

    private func walkingHalves(_ target: MuseumInfo.Exhibit) -> some View {
        let onTrack = guide.onTrack
        let instruction = onTrack ? tr("Right way!", "Dobry kierunek!") : turnInstruction(guide.turn).text
        let distance = guide.remaining.map { tr("\(Int($0.rounded())) m to go", "zostało \(Int($0.rounded())) m") }
            ?? tr("Finding the way", "Szukam drogi")
        let stopArmed = stopArmedSince.map { Date().timeIntervalSince($0) < 10 } ?? false

        return VStack(spacing: 6) {
            bigHalf(color: onTrack ? Color(hex: 0x4BE07C) : Color(hex: 0x3CCBFF),
                    title: instruction, detail: "\(distance) · \(target.name)",
                    footer: tr("Tap: which way? · Hold: hear its story", "Stuknij: którędy? · Przytrzymaj: historia"),
                    accessibility: "\(instruction). \(distance). \(target.name).",
                    hint: tr("Double-tap to hear which way to go.", "Stuknij dwukrotnie, żeby usłyszeć, którędy iść.")) {
                Haptics.shared.selected()
                guide.announceDirection()
            } onHold: {
                guide.tellStory(of: target)
            }

            bigHalf(color: stopArmed ? Color(hex: 0xFF4D4D) : Color(hex: 0xFF5FA8),
                    title: stopArmed ? tr("Tap again to stop", "Stuknij, żeby zakończyć") : tr("Stop guidance", "Zakończ prowadzenie"),
                    detail: stopArmed ? tr("Or wait and keep walking", "Albo poczekaj i idź dalej") : tr("Tap twice to stop", "Stuknij dwa razy"),
                    footer: nil,
                    accessibility: stopArmed ? tr("Tap again to stop guidance.", "Stuknij jeszcze raz, żeby zakończyć prowadzenie.")
                                             : tr("Stop guidance.", "Zakończ prowadzenie."),
                    hint: stopArmed ? tr("Double-tap again to stop.", "Stuknij dwukrotnie jeszcze raz.")
                                    : tr("Double-tap twice to stop.", "Stuknij dwukrotnie dwa razy.")) {
                if stopArmed {
                    stopArmedSince = nil
                    Haptics.shared.confirmed()
                    guide.stopGuidance()
                } else {
                    stopArmedSince = Date()
                    Haptics.shared.selected()
                    guide.speak([.init(text: tr("Tap again to stop guiding you to \(target.name).",
                                                "Stuknij jeszcze raz, żeby przerwać prowadzenie do: \(target.name)."))])
                }
            } onHold: {}
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bigHalf(color: Color, title: String, detail: String, footer: String?, accessibility: String, hint: String,
                         onTap: @escaping () -> Void, onHold: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.largeTitle, weight: .heavy))
                .minimumScaleFactor(0.6)
                .lineLimit(2)
            Text(detail)
                .font(.title3.weight(.bold))
                .lineLimit(3)
            Spacer(minLength: 0)
            if let footer {
                Text(footer)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(Color.black)
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(color))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.7, perform: onHold)
        .animation(.easeOut(duration: 0.2), value: title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
        .accessibilityHint(hint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
    }
}

/// The black band at the bottom of a chosen corner: "Tap again / or say yes". Short words, scaled to fit,
/// so it never spills out of a narrow corner.
private struct ConfirmBand: View {
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 22, weight: .bold))
                Text(tr("Tap again", "Stuknij ponownie"))
                    .font(.system(.title3, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(tr("or say “yes”", "lub powiedz „tak”"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color.black)
        .accessibilityHidden(true)
    }
}

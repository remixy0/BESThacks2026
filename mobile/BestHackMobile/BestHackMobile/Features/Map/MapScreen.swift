import SwiftUI

/// The main screen. With the map: the museum, a sliding 3D / Look / 2D switch and a settings button on top,
/// and one card at the bottom that shows just the next thing to do. Nothing else.
/// In listening mode: four big coloured choices instead of the map.
struct MapScreen: View {
    let guide: GuideModel
    let visits: VisitLog
    let account: AccountStore
    @Binding var mode: UserMode
    var onShowIntro: () -> Void
    var onRecalibrate: () -> Void
    var onLogout: () -> Void

    @AppStorage("map.style") private var style: MapStyle = .overview
    @State private var showExhibits = false
    @State private var showSettings = false
    @State private var detail: MuseumInfo.Exhibit?
    @State private var dismissedNotice: String?
    @State private var topBarHeight: CGFloat = 56
    @State private var panelHeight: CGFloat = 260

    var body: some View {
        ZStack {
            if mode == .blind {
                ListenModeView(guide: guide, visits: visits, onSettings: { showSettings = true })
            } else {
                mapScreen
            }
        }
        // Haptics and "visited" ticks live in a tiny view of their own, so the guide's frequent events
        // don't redraw this whole screen.
        .background { GuideEvents(guide: guide, visits: visits, mode: mode) }
        .sheet(isPresented: $showExhibits) {
            ArtifactListView(guide: guide, visits: visits) {
                showExhibits = false
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(guide: guide, visits: visits, account: account, mode: $mode,
                         onShowIntro: { showSettings = false; onShowIntro() },
                         onRecalibrate: { showSettings = false; onRecalibrate() },
                         onLogout: { showSettings = false; onLogout() })
        }
        .sheet(item: $detail) { exhibit in
            NavigationStack {
                ArtifactDetailView(guide: guide, visits: visits, exhibit: exhibit, showsClose: true) {
                    detail = nil
                }
            }
        }
        // VoiceOver "magic tap" (two-finger double tap) reads what's nearby.
        .accessibilityAction(.magicTap) { guide.announceNearby() }
    }

    // MARK: - Map mode

    private var mapScreen: some View {
        GeometryReader { geo in
            // What the top bar and the bottom card cover, measured from the screen edges, so the maps can keep
            // you in the part of the screen you can actually see.
            let covered = EdgeInsets(top: geo.safeAreaInsets.top + topBarHeight, leading: 0,
                                     bottom: geo.safeAreaInsets.bottom + panelHeight, trailing: 0)
            ZStack(alignment: .top) {
                mapLayer(covered: covered)
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        MapStyleSlider(style: $style)
                        Spacer(minLength: 0)
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(RoundIconButtonStyle(tint: Theme.ink, size: 44))
                        .accessibilityLabel(tr("Settings", "Ustawienia"))
                    }
                    .padding(.horizontal, 14)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height + 4 } action: { topBarHeight = $0 }

                    if guide.voiceInput.isBusy {
                        VoiceIndicator(voice: guide.voiceInput)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else if let notice, notice != dismissedNotice {
                        NoticeBanner(text: notice) { dismissedNotice = notice }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Spacer(minLength: 0)
                    GuidePanel(guide: guide, visits: visits, onShowAll: { showExhibits = true }, onShowDetail: { detail = $0 })
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
                }
                .padding(.top, 4)
            }
            .animation(.easeInOut(duration: 0.25), value: notice)
            .animation(.easeInOut(duration: 0.2), value: guide.voiceInput.isBusy)
        }
    }

    @ViewBuilder
    private func mapLayer(covered: EdgeInsets) -> some View {
        switch style {
        case .plan:
            Map2DView(guide: guide, visited: visits.visited, covered: covered) { guide.preview = $0 }
                .transition(.opacity)
        case .overview, .eyeLevel:
            Map3DView(guide: guide, style: style, visited: visits.visited, covered: covered) { guide.preview = $0 }
                .transition(.opacity)
        }
    }

    /// Something worth telling you (missing data, route service problem, voice fell back…).
    private var notice: String? {
        guide.loadError ?? guide.statusMessage ?? guide.audio.speechNotice ?? guide.voiceInput.problem
    }
}

// MARK: - Events (haptics, visits)

/// Plays a haptic for what the guide is doing, ticks off exhibits you reach, and (map mode) listens for a spoken
/// command after the guide asks for one.
private struct GuideEvents: View {
    let guide: GuideModel
    let visits: VisitLog
    let mode: UserMode

    var body: some View {
        Color.clear
            .sensoryFeedback(.selection, trigger: guide.facedEvent)
            .sensoryFeedback(.success, trigger: guide.selectionEvent)
            .sensoryFeedback(.impact(weight: .medium), trigger: guide.waypointEvent)
            .sensoryFeedback(.success, trigger: guide.arrivalEvent)
            // Facing the right way: a firm, unmistakable tap.
            .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: guide.onTrackEvent)
            .sensoryFeedback(.warning, trigger: guide.offRouteEvent)
            .onChange(of: guide.arrivalEvent) { _, _ in
                if let arrived = guide.arrived { visits.mark(arrived.key) }
            }
            .onChange(of: guide.speechFinishedEvent) { _, _ in
                guard mode == .standard, guide.listenAfterSpeech else { return }
                guide.listenAfterSpeech = false
                Task { await runMapVoice(guide: guide, visits: visits) }
            }
            // "Hej Bloop": take a command (listening mode handles its own).
            .onChange(of: guide.wakeEvent) { _, _ in
                guard mode == .standard, !guide.voiceInput.isBusy else { return }
                Task { await runMapVoice(guide: guide, visits: visits) }
            }
            .accessibilityHidden(true)
    }
}

/// Map mode: listen once and do what was said ("opowiedz", "dalej", an exhibit's name…).
@MainActor
func runMapVoice(guide: GuideModel, visits: VisitLog) async {
    guard let result = await guide.listen() else { return }
    let heard = result.heard
    if guide.perform(heard) { return }
    if heard.next, let next = nextExhibits(guide, visits: visits, excluding: guide.atExhibit?.key).first {
        guide.navigate(to: next)
        return
    }
    if let key = heard.exhibits.first, let exhibit = guide.info?.exhibits.first(where: { $0.key == key }) {
        guide.navigate(to: exhibit)
        return
    }
    guide.sayNotUnderstood(result.text, hint: tr("You can say: tell me, next, repeat, where am I, or an exhibit's name.",
                                                 "Możesz powiedzieć: opowiedz, dalej, powtórz, gdzie jestem albo nazwę eksponatu."))
}

/// "Listening…" with a live microphone level, then "Recognizing…".
struct VoiceIndicator: View {
    let voice: VoiceControl

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: voice.state == .listening ? "mic.fill" : "waveform")
                .foregroundStyle(Theme.coral)
                .symbolEffect(.pulse, isActive: voice.state == .thinking)
            Text(voice.state == .listening ? tr("Listening… speak now", "Słucham… mów teraz") : tr("Recognizing…", "Rozpoznaję…"))
                .font(Theme.bodyBold)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            if voice.state == .listening {
                LevelBars(level: voice.recorder.level)
                Button(tr("Done", "Gotowe")) { voice.finishListening() }
                    .font(Theme.bodyBold)
                    .foregroundStyle(Theme.accentText)
            }
        }
        .card(padding: 12)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Five little bars showing the microphone level.
struct LevelBars: View {
    var level: Float
    var color: Color = Theme.coral

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(level > Float(index) / 5 ? color : color.opacity(0.2))
                    .frame(width: 4, height: 8 + CGFloat(index) * 4)
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
        .accessibilityHidden(true)
    }
}


// MARK: - Map style switch

/// 3D · Look · 2D as one sliding switch: tap a side, or slide the knob along.
struct MapStyleSlider: View {
    @Binding var style: MapStyle

    @Namespace private var knob
    private static let segment: CGFloat = 62

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MapStyle.allCases) { option in
                Text(option.shortTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style == option ? Color.white : Theme.ink)
                    .frame(width: Self.segment, height: 36)
                    .background {
                        if style == option {
                            Capsule()
                                .fill(Theme.accent)
                                .matchedGeometryEffect(id: "knob", in: knob)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { select(option) }
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let index = Int(((value.location.x - 4) / Self.segment).rounded(.down))
                    let options = MapStyle.allCases
                    select(options[min(max(index, 0), options.count - 1)])
                }
        )
        .sensoryFeedback(.selection, trigger: style)
        .accessibilityRepresentation {
            Picker(tr("Map", "Mapa"), selection: $style) {
                ForEach(MapStyle.allCases) { option in
                    Text(option.accessibilityName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func select(_ option: MapStyle) {
        guard option != style else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { style = option }
    }
}

/// A small banner for problems, with a close button. Goes away by itself after a while.
struct NoticeBanner: View {
    var text: String
    var onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.coral)
                .padding(.top, 1)
            Text(text)
                .font(Theme.small)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .padding(-12)
            .accessibilityLabel(tr("Dismiss", "Zamknij"))
        }
        .card(padding: 12)
        .padding(.horizontal, 14)
        .task(id: text) {
            try? await Task.sleep(for: .seconds(8))
            onClose()
        }
    }
}

import SwiftUI

/// The card at the bottom of the map. It shows one thing at a time:
/// 1. Explore: where you are, the next exhibit to see, and one big "Let's go".
/// 2. Preview: one exhibit you tapped, with "Let's go".
/// 3. Walking: which way to turn, how far is left, and a way to stop.
struct GuidePanel: View {
    let guide: GuideModel
    let visits: VisitLog
    var onShowAll: () -> Void
    var onShowDetail: (MuseumInfo.Exhibit) -> Void

    private enum Phase: Hashable {
        case explore, preview(String), walking(String)
    }

    private var phase: Phase {
        if let target = guide.target { return .walking(target.key) }
        if let preview = guide.preview { return .preview(preview.key) }
        return .explore
    }

    var body: some View {
        ZStack {
            Group {
                if let target = guide.target {
                    WalkingCard(guide: guide, target: target)
                } else if let exhibit = guide.preview {
                    PreviewCard(guide: guide, exhibit: exhibit, isVisited: visits.contains(exhibit.key)) {
                        onShowDetail(exhibit)
                    }
                } else {
                    ExploreCard(guide: guide, visits: visits, onShowAll: onShowAll)
                }
            }
            .id(phase)
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: 620)
        .floatingPanel()
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: phase)
    }
}

/// Exhibits in "next up" order: nearest you haven't visited first, then the rest by distance.
@MainActor
func nextExhibits(_ guide: GuideModel, visits: VisitLog, excluding: String? = nil) -> [MuseumInfo.Exhibit] {
    let all = (guide.info?.exhibits ?? []).filter { $0.key != excluding }
    return all.sorted { a, b in
        let va = visits.contains(a.key), vb = visits.contains(b.key)
        if va != vb { return !va }
        return guide.distance(to: a) < guide.distance(to: b)
    }
}

// MARK: - 1. Explore

struct ExploreCard: View {
    let guide: GuideModel
    let visits: VisitLog
    var onShowAll: () -> Void

    var body: some View {
        let next = nextExhibits(guide, visits: visits, excluding: guide.atExhibit?.key).first
        VStack(alignment: .leading, spacing: 12) {
            if guide.selectByLooking, let faced = guide.faced, guide.dwellProgress > 0 {
                LookingRow(title: faced.name, progress: guide.dwellProgress)
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        PositionDot(isHealthy: guide.positioning.isHealthy)
                        Text(guide.placeName.isEmpty ? "Field Museum" : guide.placeName)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { guide.announceLocation() }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(tr("You are in: ", "Jesteś tutaj: ") + (guide.placeName.isEmpty ? "Field Museum" : guide.placeName))
                    .accessibilityHint(tr("Says where you are", "Mówi, gdzie jesteś"))

                    if guide.audio.isSpeaking {
                        StopSpeakingButton(guide: guide)
                    }
                    VoiceButton(guide: guide, visits: visits)
                }
                .frame(minHeight: 36)
            }

            // Standing at an exhibit: offer its story, quietly (no pop-ups).
            if let here = guide.atExhibit {
                HStack(spacing: 10) {
                    ExhibitThumbnail(key: here.key, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Eyebrow(text: tr("You're at", "Jesteś przy"), tint: Theme.mintText)
                        Text(here.name)
                            .font(Theme.bodyBold)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if !guide.audio.isSpeaking {
                        Button {
                            guide.tellStory(of: here)
                        } label: {
                            Label(tr("Story", "Historia"), systemImage: "speaker.wave.2.fill")
                        }
                        .buttonStyle(AppButtonStyle(kind: .secondary, fullWidth: false, height: 40))
                        .accessibilityLabel(tr("Hear the story of \(here.name)", "Posłuchaj historii: \(here.name)"))
                    }
                }
            }

            if let next {
                Button {
                    guide.preview = next
                } label: {
                    HStack(spacing: 12) {
                        ExhibitThumbnail(key: next.key, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow(text: visits.contains(next.key) ? tr("Nearest", "Najbliżej") : tr("Next up", "Następny"), tint: Theme.coralText)
                            Text(next.name)
                                .font(Theme.headline)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text(guide.directions(to: next))
                                .font(Theme.small)
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .buttonStyle(CardButtonStyle(padding: 10))
                .accessibilityLabel(tr("Next up: ", "Następny: ") + "\(next.name), \(guide.directions(to: next))")
                .accessibilityHint(tr("Shows the exhibit", "Pokazuje eksponat"))

                HStack(spacing: 10) {
                    Button {
                        guide.navigate(to: next)
                    } label: {
                        Text(tr("Let's go", "Ruszamy"))
                    }
                    .buttonStyle(AppButtonStyle(kind: .primary))
                    .accessibilityLabel(tr("Let's go to \(next.name)", "Ruszamy do: \(next.name)"))

                    Button(action: onShowAll) {
                        Image(systemName: "square.grid.2x2")
                    }
                    .buttonStyle(AppButtonStyle(kind: .secondary, fullWidth: false, height: 52))
                    .accessibilityLabel(tr("All exhibits", "Wszystkie eksponaty"))
                }
            } else {
                Text(tr("The museum map couldn't be loaded, so there are no exhibits to show.",
                        "Nie udało się wczytać mapy muzeum, więc nie ma eksponatów do pokazania."))
                    .font(Theme.body)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }
}

/// A microphone button: tap and say what you want ("opowiedz", "dalej", an exhibit's name…).
struct VoiceButton: View {
    let guide: GuideModel
    let visits: VisitLog

    var body: some View {
        Button {
            if guide.voiceInput.state == .listening {
                guide.voiceInput.finishListening()
            } else if !guide.voiceInput.isBusy {
                Task { await runMapVoice(guide: guide, visits: visits) }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: guide.voiceInput.isBusy ? "waveform" : "mic.fill")
                    .font(.system(size: 20, weight: .bold))
                    .symbolEffect(.pulse, isActive: guide.voiceInput.isBusy)
                Text(guide.voiceInput.state == .listening ? tr("Done", "Gotowe") : tr("Talk", "Mów"))
                    .font(.system(.headline, weight: .heavy))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minWidth: 96, minHeight: 48)
            .background(Capsule().fill(Theme.coral))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(tr("Talk to the guide", "Mów do przewodnika"))
        .accessibilityHint(tr("Say for example: tell me, next, or an exhibit's name", "Powiedz na przykład: opowiedz, dalej albo nazwę eksponatu"))
    }
}

/// A small dot: green when the beacons (or the demo) know where you are, orange when they don't.
private struct PositionDot: View {
    var isHealthy: Bool

    var body: some View {
        Circle()
            .fill(isHealthy ? Theme.mint : Theme.amber)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// "Facing Totem Poles… keep looking to choose it."
private struct LookingRow: View {
    var title: String
    var progress: Double

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "eye")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Facing \(title)", "Patrzysz na: \(title)"))
                    .font(Theme.headline)
                    .foregroundStyle(Theme.ink)
                Text(tr("Keep looking to choose it", "Patrz dalej, żeby go wybrać"))
                    .font(Theme.caption)
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Stops whatever the guide is saying.
struct StopSpeakingButton: View {
    let guide: GuideModel

    var body: some View {
        Button {
            guide.stopSpeaking()
        } label: {
            Image(systemName: "speaker.slash.fill")
        }
        .buttonStyle(RoundIconButtonStyle(tint: Theme.redText, size: 36))
        .accessibilityLabel(tr("Stop speaking", "Przestań mówić"))
    }
}

// MARK: - 2. Preview

struct PreviewCard: View {
    let guide: GuideModel
    let exhibit: MuseumInfo.Exhibit
    var isVisited: Bool
    var onMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ExhibitThumbnail(key: exhibit.key, size: 72)
                VStack(alignment: .leading, spacing: 6) {
                    Text(exhibit.name)
                        .font(Theme.title(.title3))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(exhibit.galleryName)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSoft)
                    HStack(spacing: 6) {
                        Chip(text: guide.directions(to: exhibit), systemImage: "figure.walk", tint: Theme.ink)
                        if isVisited {
                            Chip(text: tr("Visited", "Odwiedzony"), systemImage: "checkmark", tint: Theme.mintText)
                        }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    guide.preview = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RoundIconButtonStyle(tint: Theme.inkSoft, size: 36))
                .accessibilityLabel(tr("Close", "Zamknij"))
            }

            Button {
                guide.navigate(to: exhibit)
            } label: {
                Text(tr("Let's go", "Ruszamy"))
            }
            .buttonStyle(AppButtonStyle(kind: .primary))

            HStack(spacing: 10) {
                StoryButton(guide: guide, exhibit: exhibit, height: 44)
                Button(action: onMore) {
                    Label(tr("Look closer", "Zobacz z bliska"), systemImage: "cube")
                }
                .buttonStyle(AppButtonStyle(kind: .secondary, height: 44))
            }
        }
    }
}

/// "Hear its story", which turns into "Stop" while the guide is talking.
struct StoryButton: View {
    let guide: GuideModel
    let exhibit: MuseumInfo.Exhibit
    var height: CGFloat = 52

    var body: some View {
        if guide.audio.isSpeaking {
            Button {
                guide.stopSpeaking()
            } label: {
                Label(tr("Stop", "Stop"), systemImage: "speaker.slash.fill")
            }
            .buttonStyle(AppButtonStyle(kind: .secondaryDanger, height: height))
            .accessibilityLabel(tr("Stop speaking", "Przestań mówić"))
        } else {
            Button {
                guide.tellStory(of: exhibit)
            } label: {
                Label(tr("Hear its story", "Posłuchaj historii"), systemImage: "speaker.wave.2.fill")
            }
            .buttonStyle(AppButtonStyle(kind: .secondary, height: height))
        }
    }
}

// MARK: - 3. Walking

struct WalkingCard: View {
    let guide: GuideModel
    let target: MuseumInfo.Exhibit

    @State private var confirmEnd = false

    var body: some View {
        let instruction = turnInstruction(guide.turn)
        let onTrack = guide.onTrack
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(onTrack ? Theme.mint : Theme.accent)
                    if onTrack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                    } else if let angle = instruction.angle {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(angle))
                    } else {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 60, height: 60)
                .scaleEffect(onTrack ? 1.08 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: onTrack)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: instruction.angle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(onTrack ? tr("Right way!", "Dobry kierunek!") : instruction.text)
                        .font(Theme.title(.title3))
                        .foregroundStyle(onTrack ? Theme.mintText : Theme.ink)
                    Text("\(remainingText) · \(target.name)")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Button {
                    confirmEnd = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(RoundIconButtonStyle(tint: Theme.inkSoft, size: 36))
                .accessibilityLabel(tr("End guidance", "Zakończ prowadzenie"))
            }
            .accessibilityElement(children: .contain)

            ProgressLine(value: guide.progress, tint: onTrack ? Theme.mint : Theme.accent)
                .accessibilityLabel(tr("Progress", "Postęp"))

            Button {
                guide.announceDirection()
            } label: {
                Label(tr("Repeat directions", "Powtórz wskazówki"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(AppButtonStyle(kind: .secondary, height: 44))
        }
        .confirmationDialog(tr("Stop guiding you to \(target.name)?", "Przerwać prowadzenie do: \(target.name)?"),
                            isPresented: $confirmEnd, titleVisibility: .visible) {
            Button(tr("Stop guidance", "Zakończ prowadzenie"), role: .destructive) { guide.stopGuidance() }
            Button(tr("Keep going", "Prowadź dalej"), role: .cancel) {}
        }
    }

    private var remainingText: String {
        guard let remaining = guide.remaining else { return tr("Finding the way…", "Szukam drogi…") }
        let meters = Int(remaining.rounded())
        return meters <= 1 ? tr("Almost there", "Prawie na miejscu") : tr("\(meters) m to go", "zostało \(meters) m")
    }
}

/// Words and an arrow angle for a turn.
@MainActor
func turnInstruction(_ turn: GuideModel.Turn) -> (text: String, angle: Double?) {
    switch turn {
    case .ahead: return (tr("Go straight ahead", "Idź prosto"), 0)
    case .left: return (tr("Turn left", "Skręć w lewo"), -90)
    case .right: return (tr("Turn right", "Skręć w prawo"), 90)
    case .around: return (tr("Turn around", "Zawróć"), 180)
    case .unknown: return (tr("Follow the bloop", "Idź za dźwiękiem"), nil)
    }
}

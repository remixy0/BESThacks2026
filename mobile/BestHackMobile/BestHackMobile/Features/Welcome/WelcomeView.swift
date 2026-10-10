import SwiftUI

/// The intro, one small question per screen: hello → map or listening → headphones → beacons.
struct WelcomeView: View {
    let guide: GuideModel
    @Binding var mode: UserMode
    var onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case hello, mode, headphones, beacons
    }

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var step: Step = .hello
    @State private var pickedMode: UserMode?
    @State private var heard: Set<Bool> = []   // test bloops played (true = left)

    var body: some View {
        VStack(spacing: 0) {
            if step != .hello {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.opacity)
            }

            ZStack {
                switch step {
                case .hello: hello.transition(slide)
                case .mode: modeStep.transition(slide)
                case .headphones: headphonesStep.transition(slide)
                case .beacons: beaconsStep.transition(slide)
                }
            }
            .frame(maxWidth: 560, maxHeight: .infinity)
            .padding(.horizontal, 24)

            footer
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.page.ignoresSafeArea())
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: step)
        .sensoryFeedback(.selection, trigger: pickedMode)
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        .onAppear {
            if pickedMode == nil { pickedMode = voiceOverEnabled ? .blind : mode }
        }
    }

    private var slide: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
    }

    // MARK: - Header: back + progress

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(tr("Back", "Wstecz"))

            ProgressLine(value: Double(step.rawValue) / Double(Step.allCases.count - 1))
                .accessibilityLabel(tr("Step \(step.rawValue) of \(Step.allCases.count - 1)", "Krok \(step.rawValue) z \(Step.allCases.count - 1)"))
        }
    }

    // MARK: - Steps

    private var hello: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                LanguageSwitch()
            }
            .padding(.top, 8)
            Spacer(minLength: 0)
            BloopOrb(isTalking: true, size: 120)
            VStack(spacing: 10) {
                Text(tr("Welcome", "Witaj"))
                    .font(Theme.title(.largeTitle))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(tr("Explore the Field Museum with sound. Pick an exhibit, follow the bloop, and hear its story when you get there.", "Zwiedzaj Field Museum za pomocą dźwięku. Wybierz eksponat, idź za dźwiękiem i posłuchaj jego historii na miejscu."))
                    .font(Theme.body)
                    .foregroundStyle(Theme.inkSoft)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var modeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepTitle(text: tr("How do you want to explore?", "Jak chcesz zwiedzać?"))
                .padding(.top, 18)
            VStack(spacing: 12) {
                ForEach(Array(UserMode.allCases.reversed())) { option in
                    ChoiceCard(
                        title: option.title,
                        detail: option.detail,
                        systemImage: option.systemImage,
                        tint: option == .standard ? Theme.accent : Theme.coral,
                        isSelected: pickedMode == option
                    ) {
                        pickedMode = option
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var headphonesStep: some View {
        VStack(spacing: 22) {
            StepTitle(text: tr("Put on your AirPods", "Załóż AirPodsy"))
                .padding(.top, 18)

            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 150, height: 150)
                Image(systemName: "airpodspro")
                    .font(.system(size: 60, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.bounce, value: heard.count)
            }
            .accessibilityHidden(true)

            Text(tr("Bloops come from the direction you should walk, and AirPods tell the app which way you face. Try it:", "Dźwięki dochodzą z kierunku, w którym masz iść, a AirPodsy mówią aplikacji, gdzie patrzysz. Sprawdź:"))
                .font(Theme.body)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    guide.playTestBloop(onLeft: true)
                    heard.insert(true)
                } label: {
                    Label(tr("Left", "Lewo"), systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(AppButtonStyle(kind: .secondary, height: 50))
                .accessibilityLabel(tr("Play a bloop on the left", "Zagraj dźwięk z lewej"))

                Button {
                    guide.playTestBloop(onLeft: false)
                    heard.insert(false)
                } label: {
                    Label(tr("Right", "Prawo"), systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(AppButtonStyle(kind: .secondary, height: 50))
                .accessibilityLabel(tr("Play a bloop on the right", "Zagraj dźwięk z prawej"))
            }
            Spacer(minLength: 0)
        }
    }

    private var beaconsStep: some View {
        VStack(spacing: 22) {
            StepTitle(text: tr("Finding you in the museum", "Jak znajdujemy Cię w muzeum"))
                .padding(.top, 18)

            ZStack {
                Circle().fill(Theme.accentSoft).frame(width: 150, height: 150)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text(tr("Small Bluetooth beacons around the museum tell the app where you are. No GPS.", "Małe beacony Bluetooth w muzeum mówią aplikacji, gdzie jesteś. Bez GPS."))
                Text(tr("iPhone only lets apps hear beacons with location access, so it will ask for that next.", "iPhone pozwala słyszeć beacony tylko z dostępem do lokalizacji, więc za chwilę o niego zapyta."))
            }
            .font(Theme.body)
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Footer: one main button

    @ViewBuilder
    private var footer: some View {
        switch step {
        case .hello:
            Button(tr("Get started", "Zaczynamy")) { step = .mode }
                .buttonStyle(AppButtonStyle(kind: .primary))
        case .mode:
            Button(tr("Continue", "Dalej")) {
                if let pickedMode { mode = pickedMode }
                step = .headphones
            }
            .buttonStyle(AppButtonStyle(kind: .primary))
            .disabled(pickedMode == nil)
        case .headphones:
            Button(heard.isEmpty ? tr("Skip for now", "Pomiń") : tr("Sounds good", "Działa")) { step = .beacons }
                .buttonStyle(AppButtonStyle(kind: heard.isEmpty ? .secondary : .primary))
        case .beacons:
            VStack(spacing: 6) {
                Button(tr("Allow and continue", "Zezwól i kontynuuj")) {
                    guide.requestLocationPermission()
                    onFinish()
                }
                .buttonStyle(AppButtonStyle(kind: .primary))
                Button(tr("Not now", "Nie teraz")) { onFinish() }
                    .buttonStyle(AppButtonStyle(kind: .quiet, height: 44))
            }
        }
    }
}

private struct StepTitle: View {
    var text: String

    var body: some View {
        Text(text)
            .font(Theme.title(.title2))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A big tappable option card with an icon.
struct ChoiceCard: View {
    var title: String
    var detail: String
    var systemImage: String
    var tint: Color
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(Theme.caption)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.lineStrong)
            }
            .multilineTextAlignment(.leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardButtonStyle(padding: 14, fill: isSelected ? Theme.accentSoft : Theme.card,
                                     highlight: isSelected ? Theme.accent : nil))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

#Preview {
    WelcomeView(guide: GuideModel(), mode: .constant(.standard)) {}
}

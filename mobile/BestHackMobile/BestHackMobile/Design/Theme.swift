import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The app's look: calm and clean. A warm off-white page, indigo for actions, coral for sound and routes,
/// flat shapes and the system font. Every colour has a light and a dark version.
enum Theme {
    // MARK: Colours
    // Button faces are dark enough for white text (at least 4.5:1); text colours are at least 4.5:1 on cards.

    /// Main action colour (Let's go, Log in, Calibrate).
    static let accent = Color(light: 0x3B4CCA, dark: 0x5869F0)
    /// Tinted backgrounds behind accent things.
    static let accentSoft = Color(light: 0xE9EBFB, dark: 0x23284A)
    /// Accent for text and icons on cards.
    static let accentText = Color(light: 0x3443B8, dark: 0xA3AEFF)
    /// Sound, the route and "you are here".
    static let coral = Color(light: 0xEF5B36, dark: 0xFF7A55)
    static let coralText = Color(light: 0xB43D1C, dark: 0xFF9C7E)
    /// Visited, done.
    static let mint = Color(light: 0x1E9E78, dark: 0x34C79A)
    static let mintText = Color(light: 0x14795B, dark: 0x6FDDB8)
    /// Progress and stars (no text on it).
    static let amber = Color(light: 0xF2A21B, dark: 0xF7B23B)
    /// Stop, end, problems.
    static let red = Color(light: 0xD23B3B, dark: 0xE04D4D)
    static let redText = Color(light: 0xC02F2F, dark: 0xFF8C8C)

    static let ink = Color(light: 0x17191E, dark: 0xEEF0F4)
    static let inkSoft = Color(light: 0x5D636E, dark: 0xA2A8B4)
    static let page = Color(light: 0xF6F5F1, dark: 0x0F1115)
    static let card = Color(light: 0xFFFFFF, dark: 0x1A1D23)
    static let cardSunken = Color(light: 0xEEEDE8, dark: 0x15181D)
    static let line = Color(light: 0xE3E1DA, dark: 0x2C3038)
    static let lineStrong = Color(light: 0xCFCCC3, dark: 0x3E434D)

    // MARK: Shapes

    static let corner: CGFloat = 16

    // MARK: Type (system font; all of it follows Dynamic Type)

    static func title(_ style: Font.TextStyle = .title) -> Font { .system(style, weight: .bold) }
    static let headline = Font.headline
    static let body = Font.body
    static let bodyBold = Font.body.weight(.semibold)
    static let caption = Font.subheadline
    static let small = Font.footnote.weight(.medium)
    static let button = Font.headline
}

extension Color {
    /// A colour from 0xRRGGBB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A colour that switches with light and dark mode.
    init(light: UInt32, dark: UInt32) {
        let lightColor = Color(hex: light)
        let darkColor = Color(hex: dark)
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(darkColor) : UIColor(lightColor)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(darkColor) : NSColor(lightColor)
        })
        #else
        self = lightColor
        #endif
    }
}

// MARK: - Buttons

/// A button was tapped. The guide hooks in here (`GuideModel.userTapped`) and stops talking, so speech never runs
/// on past a tap or over the next screen. The app's button styles call it just before the button's own action.
enum UserTap {
    static var onTap: (() -> Void)?

    static func happened() {
        onTap?()
    }
}

/// Wraps a button so a tap first silences the guide (`UserTap`), then runs the button's action, drawn with `face`.
private struct InterruptingButton<Face: ButtonStyle>: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let face: Face

    var body: some View {
        Button(role: configuration.role) {
            UserTap.happened()
            configuration.trigger()
        } label: {
            configuration.label
        }
        .buttonStyle(face)
    }
}

/// The app's button: a flat rounded shape that dims and shrinks a little while pressed.
/// Tapping it stops the guide talking first (see `UserTap`).
struct AppButtonStyle: PrimitiveButtonStyle {
    enum Kind {
        case primary          // accent, white text
        case secondary        // card with a thin outline, accent text
        case danger           // red, white text
        case secondaryDanger  // card with a thin outline, red text
        case quiet            // text only
    }

    var kind: Kind = .primary
    var fullWidth = true
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        InterruptingButton(configuration: configuration, face: AppButtonFace(kind: kind, fullWidth: fullWidth, height: height))
    }
}

private struct AppButtonFace: ButtonStyle {
    let kind: AppButtonStyle.Kind
    let fullWidth: Bool
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        AppButtonBody(configuration: configuration, kind: kind, fullWidth: fullWidth, height: height)
    }
}

private struct AppButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: AppButtonStyle.Kind
    let fullWidth: Bool
    let height: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    private var colors: (face: Color, text: Color, border: Color?) {
        guard isEnabled else { return (Theme.cardSunken, Theme.inkSoft, nil) }
        switch kind {
        case .primary: return (Theme.accent, .white, nil)
        case .secondary: return (Theme.card, Theme.accentText, Theme.line)
        case .danger: return (Theme.red, .white, nil)
        case .secondaryDanger: return (Theme.card, Theme.redText, Theme.line)
        case .quiet: return (.clear, Theme.accentText, nil)
        }
    }

    var body: some View {
        let pressed = configuration.isPressed
        let c = colors
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        configuration.label
            .font(Theme.button)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .multilineTextAlignment(.center)
            .foregroundStyle(c.text)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(shape.fill(c.face))
            .overlay {
                if let border = c.border { shape.strokeBorder(border, lineWidth: 1) }
            }
            .contentShape(shape)
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(pressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// A round icon button (settings, close, stop speaking…). Tapping it stops the guide talking first.
struct RoundIconButtonStyle: PrimitiveButtonStyle {
    var tint: Color = Theme.accentText
    var size: CGFloat = 44
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        InterruptingButton(configuration: configuration, face: RoundIconButtonFace(tint: tint, size: size, filled: filled))
    }
}

private struct RoundIconButtonFace: ButtonStyle {
    let tint: Color
    let size: CGFloat
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(filled ? Color.white : tint)
            .frame(width: size, height: size)
            .background(Circle().fill(filled ? tint : Theme.card))
            .overlay(Circle().strokeBorder(filled ? Color.clear : Theme.line, lineWidth: 1))
            .contentShape(Circle())
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

// MARK: - Cards

/// A white card with a thin outline.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    var fill: Color = Theme.card
    var highlight: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(highlight ?? Theme.line, lineWidth: highlight == nil ? 1 : 2))
    }
}

/// A card you can tap. Tapping it stops the guide talking first.
struct CardButtonStyle: PrimitiveButtonStyle {
    var padding: CGFloat = 12
    var fill: Color = Theme.card
    var highlight: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        InterruptingButton(configuration: configuration, face: CardButtonFace(padding: padding, fill: fill, highlight: highlight))
    }
}

private struct CardButtonFace: ButtonStyle {
    let padding: CGFloat
    let fill: Color
    let highlight: Color?

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        configuration.label
            .padding(padding)
            .background(shape.fill(pressed ? Theme.cardSunken : fill))
            .overlay(shape.strokeBorder(highlight ?? Theme.line, lineWidth: highlight == nil ? 1 : 2))
            .contentShape(shape)
            .scaleEffect(pressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

extension View {
    func card(padding: CGFloat = 16, fill: Color = Theme.card, highlight: Color? = nil) -> some View {
        modifier(CardModifier(padding: padding, fill: fill, highlight: highlight))
    }

    /// The floating panel at the bottom of the map: rounded, with a soft shadow.
    func floatingPanel() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.page)
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 2)
            )
    }
}

// MARK: - Progress

/// A thin rounded progress line.
struct ProgressLine: View {
    var value: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 6

    var body: some View {
        let clamped = CGFloat(min(max(value, 0), 1))
        Capsule()
            .fill(Theme.line)
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint)
                        .frame(width: max(clamped * geo.size.width, clamped > 0 ? height : 0))
                }
            }
            .clipShape(Capsule())
            .animation(.easeInOut(duration: 0.4), value: value)
            .accessibilityElement()
            .accessibilityValue("\(Int((clamped * 100).rounded())) percent")
    }
}

// MARK: - Small pieces

/// A small rounded label, e.g. a distance or "Visited".
struct Chip: View {
    var text: String
    var systemImage: String?
    var tint: Color = Theme.ink

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
            }
            Text(text)
                .font(Theme.small)
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.cardSunken))
    }
}

/// An exhibit's picture (rendered from its 3D model), on a soft tile.
struct ExhibitThumbnail: View {
    let key: String
    var size: CGFloat = 64
    var background: Color = Theme.cardSunken

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(background)
            Image("Exhibit-\(key)")
                .resizable()
                .scaledToFit()
                .padding(size * 0.06)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A small title above a group, e.g. "NEXT UP".
struct Eyebrow: View {
    var text: String
    var tint: Color = Theme.inkSoft

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(tint)
    }
}

import SwiftUI

/// The app's mark: a sound source with two rings, like a speaker seen from above.
/// While the guide talks, a ring ripples outward (and nothing moves otherwise, so it costs nothing at rest).
struct BloopOrb: View {
    var isTalking = false
    var size: CGFloat = 64

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.coral.opacity(0.22), lineWidth: max(size * 0.05, 1.5))
            Circle()
                .strokeBorder(Theme.coral.opacity(0.5), lineWidth: max(size * 0.06, 1.5))
                .padding(size * 0.16)
            Circle()
                .fill(Theme.coral)
                .padding(size * 0.32)
            if isTalking, !reduceMotion {
                OrbRipple()
                    .padding(size * 0.32)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct OrbRipple: View {
    @State private var grow = false

    var body: some View {
        Circle()
            .stroke(Theme.coral, lineWidth: 2)
            .scaleEffect(grow ? 2.8 : 1)
            .opacity(grow ? 0 : 0.7)
            .onAppear {
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { grow = true }
            }
    }
}

#Preview {
    HStack(spacing: 30) {
        BloopOrb(size: 64)
        BloopOrb(isTalking: true, size: 96)
    }
    .padding()
}

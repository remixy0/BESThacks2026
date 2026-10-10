import SwiftUI

extension View {
    /// Marks this view as one of the app's screens for sound. When another screen comes to the front (or this one goes
    /// away), what this screen was saying stops, its queued messages are dropped and a half-said voice command is
    /// thrown away, so sound always matches what's on screen. See `GuideModel.Screen`.
    ///
    /// A screen that speaks in its own `onAppear` should also call `guide.screenAppeared(_:)` there, first.
    func soundScreen(_ screen: GuideModel.Screen, guide: GuideModel) -> some View {
        onAppear { guide.screenAppeared(screen) }
            .onDisappear { guide.screenDisappeared(screen) }
    }
}

import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Everything the app keeps for its whole life. Made once (a plain `@State var x = Model()` in a view would make
/// a throwaway copy every time the view is re-created, and the guide owns the audio engine and the beacon scanner).
@Observable
final class AppModel {
    static let shared = AppModel()

    let guide = GuideModel()
    let visits = VisitLog()
    let account = AccountStore()
    /// Calibrated (or skipped) since the app started.
    var calibrationDone = false

    private init() {
        // The live position WebSocket (`PositionSocket`, /ws/position) isn't wired into GuideModel in this version.
        // The earlier integration (guide.server + AccountStore.socketSession) is saved in backups/backend.tgz.
    }

    /// Loads the beacon positions for the signed-in account.
    func refreshBeacons() async {
        await guide.positioning.loadDirectory(using: account.backend)
    }
}

/// Log in → (first time) intro → calibrate → the museum.
struct RootView: View {
    @AppStorage("userMode") private var mode: UserMode = .standard
    @AppStorage("onboarding.done") private var onboarded = false
    @State private var app = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase: Equatable {
        case login, welcome, calibration, museum
    }

    private var phase: Phase {
        if !app.account.isSignedIn { return .login }
        if !onboarded { return .welcome }
        if !app.calibrationDone { return .calibration }
        return .museum
    }

    var body: some View {
        ZStack {
            switch phase {
            case .login:
                LoginView(account: app.account) {
                    Task { await app.refreshBeacons() }
                }
                .soundScreen(.login, guide: app.guide)
                .transition(.opacity)
            case .welcome:
                WelcomeView(guide: app.guide, mode: $mode) {
                    onboarded = true
                }
                .soundScreen(.welcome, guide: app.guide)
                .transition(.move(edge: .leading).combined(with: .opacity))
            case .calibration:
                CalibrationView(guide: app.guide, mode: mode) {
                    app.calibrationDone = true
                }
                .soundScreen(.calibration, guide: app.guide)
                .transition(.opacity)
            case .museum:
                MapScreen(guide: app.guide, visits: app.visits, account: app.account, mode: $mode,
                          onShowIntro: {
                              app.guide.leaveMuseum()
                              onboarded = false
                          },
                          onRecalibrate: { app.calibrationDone = false },
                          onLogout: {
                              app.guide.leaveMuseum()
                              app.account.signOut()
                              app.calibrationDone = false
                          })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: phase)
        .tint(Theme.accent)
        .task {
            app.guide.mode = mode
            // Slow first-time work, done early so nothing stutters later.
            AppleSpeech.prewarm()
            _ = Haptics.shared
            // Load the 3D models and the beacon list while you log in and calibrate.
            let info = app.guide.info
            Task { await MuseumAssets.preload(info) }
            if app.account.isSignedIn { await app.refreshBeacons() }
        }
        .onChange(of: mode) { _, newMode in app.guide.mode = newMode }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if phase == .calibration || phase == .museum { app.guide.start(mode: mode) }
                setScreenAlwaysOn(phase == .museum)
            case .background:
                app.guide.stop()
                setScreenAlwaysOn(false)
            default:
                break
            }
        }
        .onChange(of: phase) { _, newPhase in
            if newPhase == .museum || newPhase == .calibration {
                app.guide.start(mode: mode)
            } else {
                // Back to the welcome or login screen: no bloops or talking in the background.
                app.guide.leaveMuseum()
            }
            setScreenAlwaysOn(newPhase == .museum)
        }
    }

    /// In the museum the phone is often held without touching it: don't let the screen lock (beacons and
    /// head tracking stop when it does).
    private func setScreenAlwaysOn(_ on: Bool) {
        #if os(iOS)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}

#Preview {
    RootView()
}

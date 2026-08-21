import SwiftUI
import SwiftData

@main
struct ShakedownAIApp: App {
    // Catches background-download session relaunches.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment

    init() {
        _environment = State(initialValue: AppEnvironment.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modelContainer(environment.modelContainer)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                // Sign-in/out changes which mode the cloud store opens in, and
                // that's fixed at container creation — so rebuild the whole
                // environment. Same store file either way; no data moves.
                .onReceive(NotificationCenter.default.publisher(for: .shakedownAuthChanged)) { _ in
                    environment.playerEngine.stop()
                    environment = AppEnvironment.live()
                }
        }
    }
}

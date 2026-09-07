import SwiftUI
import SwiftData

@main
struct ShakedownAIApp: App {
    // Catches background-download session relaunches.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment: AppEnvironment
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.dark

    init() {
        _environment = State(initialValue: AppEnvironment.live())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modelContainer(environment.modelContainer)
                .tint(Theme.textPrimary)
                .preferredColorScheme(appearance.colorScheme)
                // On or off the bus: the sync engine takes it from here. The
                // tape keeps rolling.
                .onReceive(NotificationCenter.default.publisher(for: .shakedownAuthChanged)) { _ in
                    environment.sync.handleAuthChange()
                }
        }
    }
}

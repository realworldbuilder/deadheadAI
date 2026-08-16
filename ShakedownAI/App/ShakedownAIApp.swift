import SwiftUI
import SwiftData

@main
struct ShakedownAIApp: App {
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
        }
    }
}

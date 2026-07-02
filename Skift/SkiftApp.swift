import SwiftUI

@main
struct SkiftApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Standard macOS Settings window (⌘,): rider weight, trainer difficulty.
        Settings {
            SettingsView()
        }
    }
}

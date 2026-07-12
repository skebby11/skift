import SwiftUI

@main
struct SkiftApp: App {
    /// Shared by the main window (upload from summary/history) and the
    /// Settings window (connect/disconnect) so connection state stays in
    /// sync across both (docs/strava-upload.md).
    @StateObject private var stravaAccount = StravaAccount()

    var body: some Scene {
        WindowGroup {
            ContentView(strava: stravaAccount)
        }
        // Standard macOS Settings window (⌘,): rider weight, trainer
        // difficulty, Strava connection.
        Settings {
            SettingsView(strava: stravaAccount)
        }
    }
}

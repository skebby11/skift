import SwiftUI

/// Title screen — the first thing the player sees. Deliberately game-like:
/// big wordmark on a dark gradient, three actions, no chrome.
struct MenuView: View {
    let onRide: () -> Void

    var body: some View {
        ZStack {
            // Night-ride gradient backdrop. REVIEW: replace with a rendered
            // shot of the island once the art pass lands.
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.1, blue: 0.2), Color(red: 0.1, green: 0.25, blue: 0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Spacer()
                Text("SKIFT")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .kerning(6)
                Text("Ride real watts in a virtual world")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()

                VStack(spacing: 10) {
                    Button {
                        onRide()
                    } label: {
                        Label("Ride", systemImage: "bicycle")
                            .font(.title2.bold())
                            .frame(width: 220)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                    // SettingsLink opens the standard macOS Settings window (⌘,).
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                            .frame(width: 220)
                    }
                    .controlSize(.large)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                            .frame(width: 220)
                    }
                    .controlSize(.large)
                }
                Spacer()

                Text("Open source · Apache-2.0")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 12)
            }
            .padding(32)
        }
    }
}

#Preview {
    MenuView(onRide: {})
        .frame(width: 760, height: 620)
}

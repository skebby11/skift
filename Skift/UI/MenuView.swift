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
                colors: [Color(red: 0.025, green: 0.055, blue: 0.1), Color(red: 0.06, green: 0.18, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(.orange.opacity(0.12))
                .frame(width: 520, height: 520)
                .blur(radius: 80)
                .offset(x: 300, y: 260)

            VStack(spacing: 12) {
                Spacer()
                Text("SKIFT")
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .kerning(6)
                Text("Ride real watts in a virtual world")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.78))
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
                    .tint(.orange)
                    .foregroundStyle(.black)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)

                    // SettingsLink opens the standard macOS Settings window (⌘,).
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 220)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Label("Quit", systemImage: "power")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 220)
                            .padding(.vertical, 9)
                            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
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

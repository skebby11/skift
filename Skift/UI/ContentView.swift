import SwiftUI
import SkiftKit

/// Which screen the game is on. One linear flow, no hidden states:
/// menu → pairing → ride setup → riding → summary → menu.
enum GamePhase {
    case menu
    case pairing
    case rideSetup
    case riding
    case summary
}

/// Root view: owns the long-lived objects (trainer, engine) and drives the
/// game flow. Each screen is its own view; this file only does wiring.
struct ContentView: View {
    @StateObject private var trainer = TrainerManager()
    @StateObject private var engine = RideEngine(route: .island)
    @StateObject private var demoPower = DemoPowerSource()

    @State private var phase: GamePhase = .menu
    @State private var isDemoMode = false

    // Rider settings (editable in the Settings window, applied at ride start).
    @AppStorage(RiderSettings.riderKgKey)
    private var riderKg = RiderSettings.defaultRiderKg
    @AppStorage(RiderSettings.bikeKgKey)
    private var bikeKg = RiderSettings.defaultBikeKg
    @AppStorage(RiderSettings.trainerDifficultyKey)
    private var trainerDifficulty = RiderSettings.defaultTrainerDifficulty

    var body: some View {
        Group {
            switch phase {
            case .menu:
                MenuView {
                    // Skip pairing when the trainer is already good to go.
                    isDemoMode = false
                    phase = trainer.hasControl ? .rideSetup : .pairing
                }
            case .pairing:
                PairingView(
                    trainer: trainer,
                    onReady: { phase = .rideSetup },
                    onDemo: {
                        isDemoMode = true
                        phase = .rideSetup
                    },
                    onBack: { phase = .menu }
                )
            case .rideSetup:
                RideSetupView(
                    route: engine.route,
                    isDemo: isDemoMode,
                    onStart: { target in startRide(targetMeters: target) },
                    onBack: { phase = .menu }
                )
            case .riding:
                ridingScreen
            case .summary:
                RideSummaryView(recorder: engine.recorder) {
                    phase = .menu
                }
            }
        }
        .frame(minWidth: 780, minHeight: 640)
        // The engine completes target rides on its own (finish line crossed);
        // the flow reacts here rather than the engine knowing about screens.
        .onChange(of: engine.isCompleted) { _, completed in
            if completed && phase == .riding {
                endRide()
            }
        }
    }

    // MARK: - Riding screen

    private var ridingScreen: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                RideView(engine: engine)

                if !isDemoMode, case let .reconnecting(_, attempt) = trainer.state {
                    reconnectingBadge(attempt: attempt)
                        .padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 16) {
                if isDemoMode {
                    Label("Demo power", systemImage: "slider.horizontal.3")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                    Slider(value: $demoPower.watts, in: 0...400)
                        .frame(maxWidth: 420)
                    Text("\(Int(demoPower.watts)) W")
                        .font(.callout.bold())
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                Spacer()
                Button {
                    endRide()
                } label: {
                    Label("End ride", systemImage: "flag.checkered")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(Color(red: 0.035, green: 0.055, blue: 0.08))
        }
    }

    // Matches RideView's HUD panel style (dark panel, orange accent) so it
    // reads as part of the same HUD rather than a separate alert.
    private func reconnectingBadge(attempt: Int) -> some View {
        Label("Reconnecting… (attempt \(attempt))", systemImage: "wifi.exclamationmark")
            .font(.callout.bold())
            .foregroundStyle(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.68), in: Capsule())
            .overlay {
                Capsule().stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }

    // MARK: - Flow actions

    private func startRide(targetMeters: Double?) {
        engine.trainerDifficulty = trainerDifficulty

        // Demo and real rides go through the same engine API: only the data
        // source and the control sink differ (see docs/game-flow.md).
        let dataSource: () -> FTMS.IndoorBikeData = isDemoMode
            ? { [demoPower] in demoPower.currentData() }
            : { [weak trainer] in trainer?.liveData ?? FTMS.IndoorBikeData() }

        engine.start(
            dataSource: dataSource,
            control: isDemoMode ? nil : trainer,
            profile: RiderProfile(riderKg: riderKg, bikeKg: bikeKg),
            targetDistanceMeters: targetMeters
        )
        phase = .riding
    }

    private func endRide() {
        engine.stop()
        if !isDemoMode {
            trainer.setGrade(percent: 0) // release the resistance
        }
        phase = .summary
    }
}

#Preview {
    ContentView()
}

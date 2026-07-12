import SwiftUI
import SkiftKit

/// Which screen the game is on. One linear flow, no hidden states:
/// menu → pairing → ride setup → riding → summary → menu. `.history` is a
/// side branch off the menu (menu → history → menu), not part of the ride flow.
enum GamePhase {
    case menu
    case pairing
    case rideSetup
    case riding
    case summary
    case history
}

/// Root view: owns the long-lived objects (trainer, engine) and drives the
/// game flow. Each screen is its own view; this file only does wiring.
struct ContentView: View {
    @StateObject private var trainer = TrainerManager()
    @StateObject private var hrMonitor = HeartRateMonitor()
    @StateObject private var engine = RideEngine(route: .island)
    @StateObject private var demoPower = DemoPowerSource()
    private let rideStore = RideStore()

    @State private var phase: GamePhase = .menu
    @State private var isDemoMode = false
    @State private var saveError: String?

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
                MenuView(
                    onRide: {
                        // Skip pairing when the trainer is already good to go.
                        isDemoMode = false
                        phase = trainer.hasControl ? .rideSetup : .pairing
                    },
                    onHistory: { phase = .history }
                )
            case .pairing:
                PairingView(
                    trainer: trainer,
                    hrMonitor: hrMonitor,
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
                RideSummaryView(recorder: engine.recorder, saveError: saveError) {
                    phase = .menu
                }
            case .history:
                HistoryView(rideStore: rideStore) {
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
        let baseSource: () -> FTMS.IndoorBikeData = isDemoMode
            ? { [demoPower] in demoPower.currentData() }
            : { [weak trainer] in trainer?.liveData ?? FTMS.IndoorBikeData() }
        // The heart-rate strap, if paired, overrides any HR the trainer
        // itself reports — dedicated straps are the accurate source (see
        // docs/hr-strap.md).
        let dataSource: () -> FTMS.IndoorBikeData = { [weak hrMonitor] in
            var data = baseSource()
            if let bpm = hrMonitor?.bpm { data.heartRateBpm = bpm }
            return data
        }

        saveError = nil
        engine.start(
            dataSource: dataSource,
            control: isDemoMode ? nil : trainer,
            profile: RiderProfile(riderKg: riderKg, bikeKg: bikeKg),
            targetDistanceMeters: targetMeters
        )
        phase = .riding
    }

    /// Stops the ride, saves it, and shows the summary. Reached from two
    /// places — the "End ride" button and the auto-completion `onChange`
    /// below — so it must be idempotent: the `phase == .riding` guard makes
    /// a second call (e.g. the button tapped the same instant the ride
    /// auto-completes) a no-op, guaranteeing the ride is saved exactly once.
    private func endRide() {
        guard phase == .riding else { return }
        engine.stop()
        if !isDemoMode {
            trainer.setGrade(percent: 0) // release the resistance
        }
        // Best-effort: a save failure is surfaced in the summary sheet but
        // never blocks showing it (docs/ride-history.md).
        saveError = saveCompletedRide()
        phase = .summary
    }

    private func saveCompletedRide() -> String? {
        do {
            try rideStore.save(recorder: engine.recorder)
            return nil
        } catch RideStoreError.nothingToSave {
            // Ride was too short to summarize — nothing to persist, not a failure.
            return nil
        } catch {
            return "Couldn't save this ride to History: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}

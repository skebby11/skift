import SwiftUI
import SkiftKit

/// Pre-ride screen: route card + ride-mode picker, like picking a route in
/// Zwift. Three modes (docs/erg-mode.md): "Free ride" (no finish line),
/// "Distance" (target distance, auto-finish) and "Workout" (structured ERG
/// intervals from the saved-workout library, with a minimal builder).
struct RideSetupView: View {

    /// How the ride is driven / ends. Free ride and Distance are exactly
    /// the pre-ERG behaviors, just split into two segments.
    enum SetupMode: String, CaseIterable, Identifiable {
        case freeRide = "Free ride"
        case distance = "Distance"
        case workout = "Workout"

        var id: String { rawValue }
    }

    /// The selectable ride lengths for Distance mode. Raw value = meters.
    enum Target: Double, CaseIterable, Identifiable {
        case km5 = 5000
        case km10 = 10000
        case km20 = 20000
        case km40 = 40000

        var id: Double { rawValue }

        var label: String { "\(Int(rawValue / 1000)) km" }
    }

    let route: Route
    let isDemo: Bool
    @ObservedObject var hrMonitor: HeartRateMonitor
    /// Saved-workout library, owned by ContentView (same lifetime as RideStore).
    let workoutStore: WorkoutStore
    let onStart: (Double?) -> Void
    let onStartWorkout: (Workout) -> Void
    let onBack: () -> Void

    // Distance stays the default so the pre-ERG "10 km" quick start is
    // unchanged; Free ride is one segment away.
    @State private var mode: SetupMode = .distance
    @State private var target: Target = .km10
    @State private var workouts: [Workout] = []
    @State private var selectedWorkoutID: UUID?
    @State private var pendingDelete: Workout?
    @State private var isBuilderPresented = false
    @State private var workoutError: String?
    // Collapsed by default: HR pairing is optional here too, it's just no
    // longer hidden — see docs/hr-strap.md "Discoverability".
    @State private var isHRExpanded = false

    @AppStorage(RiderSettings.hrStrapIDKey)
    private var hrStrapID: String?
    // Pre-fills the builder's watts fields (50% / 105% / 55% / 40% of FTP).
    @AppStorage(RiderSettings.ftpKey)
    private var ftp = RiderSettings.defaultFTP

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: onBack)
                Spacer()
                if isDemo {
                    Label("Demo mode — no trainer", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(route.name)
                .font(.largeTitle.bold())

            // Route card: the numbers a cyclist wants before clipping in.
            HStack(spacing: 24) {
                routeStat("Lap length", String(format: "%.1f km", route.lengthMeters / 1000))
                routeStat("Climb", String(format: "%.0f m", lapClimbMeters))
                routeStat("Max gradient", String(format: "%.0f %%", maxGradientPercent))
            }

            ElevationProfileView(route: route, positionMeters: 0)
                .frame(height: 120)

            heartRateBox

            Text("How do you want to ride?")
                .font(.headline)
            Picker("Ride mode", selection: $mode) {
                ForEach(SetupMode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            modeDetails

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button {
                    start()
                } label: {
                    Label(mode == .workout ? "Start workout" : "Start ride", systemImage: "flag.checkered")
                        .font(.title3.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(mode == .workout && selectedWorkout == nil)
            }
        }
        .padding(28)
        .onAppear {
            loadWorkouts()
            // Silently reconnect to a remembered strap; never blocks Start.
            // Guarded to `.idle` so this is a no-op if PairingView already
            // started (or finished) the same reconnect — pairing skips
            // straight here when the trainer already has control, and demo
            // mode leaves pairing immediately, so this screen needs its own
            // entry point too (see docs/hr-strap.md "Discoverability").
            if case .idle = hrMonitor.state, let stored = hrStrapID, let id = UUID(uuidString: stored) {
                hrMonitor.connectRemembered(id: id)
            }
        }
        .sheet(isPresented: $isBuilderPresented) {
            WorkoutBuilderSheet(
                ftp: ftp,
                onSave: { workout in
                    save(workout)
                    isBuilderPresented = false
                },
                onCancel: { isBuilderPresented = false }
            )
        }
        .confirmationDialog(
            "Delete this workout?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { isPresented in if !isPresented { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { workout in
            Button("Delete “\(workout.name)”", role: .destructive) { delete(workout) }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    // MARK: - Ride mode

    /// The per-mode block under the segmented picker: one caption for Free
    /// ride, the distance picker for Distance, the workout library for Workout.
    @ViewBuilder
    private var modeDetails: some View {
        switch mode {
        case .freeRide:
            Text("No finish line — ride until you quit.")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .distance:
            // Longer than a lap simply loops the island again.
            Picker("Target distance", selection: $target) {
                ForEach(Target.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        case .workout:
            workoutSection
        }
    }

    private var selectedWorkout: Workout? {
        workouts.first { $0.id == selectedWorkoutID }
    }

    private func start() {
        switch mode {
        case .freeRide:
            onStart(nil) // nil target = no finish line
        case .distance:
            onStart(target.rawValue)
        case .workout:
            guard let selectedWorkout else { return }
            onStartWorkout(selectedWorkout)
        }
    }

    // MARK: - Workout library

    @ViewBuilder
    private var workoutSection: some View {
        if let workoutError {
            Text(workoutError)
                .font(.caption)
                .foregroundStyle(.red)
        }

        if workouts.isEmpty {
            Text("No saved workouts yet — create one to get started.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(workouts) { workout in
                        workoutRow(workout)
                    }
                }
            }
            .frame(maxHeight: 170)
        }

        Button("New workout…", systemImage: "plus") {
            isBuilderPresented = true
        }
    }

    private func workoutRow(_ workout: Workout) -> some View {
        let isSelected = workout.id == selectedWorkoutID
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.headline)
                Text("\(formatWorkoutDuration(workout.totalDurationSeconds)) · \(stepCountLabel(workout))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                pendingDelete = workout
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.accentColor.opacity(0.14) : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedWorkoutID = workout.id }
    }

    private func stepCountLabel(_ workout: Workout) -> String {
        workout.steps.count == 1 ? "1 step" : "\(workout.steps.count) steps"
    }

    private func loadWorkouts() {
        do {
            workouts = try workoutStore.list()
            workoutError = nil
        } catch {
            workouts = []
            workoutError = "Couldn't load workouts: \(error.localizedDescription)"
        }
        // Keep a valid selection: fall back to the first workout so Start is
        // one click after picking the Workout segment.
        if !workouts.contains(where: { $0.id == selectedWorkoutID }) {
            selectedWorkoutID = workouts.first?.id
        }
    }

    private func save(_ workout: Workout) {
        do {
            try workoutStore.save(workout)
            workoutError = nil
        } catch {
            workoutError = "Couldn't save workout: \(error.localizedDescription)"
        }
        loadWorkouts()
        selectedWorkoutID = workout.id
    }

    private func delete(_ workout: Workout) {
        pendingDelete = nil
        do {
            try workoutStore.delete(id: workout.id)
            workoutError = nil
        } catch {
            workoutError = "Couldn't delete workout: \(error.localizedDescription)"
        }
        loadWorkouts()
    }

    // MARK: - Heart rate (optional)

    /// Compact HR box: connected straps get a one-line summary + Disconnect;
    /// everything else collapses behind a disclosure revealing the full
    /// picker. Never gates "Start ride".
    @ViewBuilder
    private var heartRateBox: some View {
        if case .connected(let name) = hrMonitor.state {
            HStack {
                Text("❤️ \(hrMonitor.bpm.map { "\($0)" } ?? "--") bpm — \(name)")
                    .font(.callout.bold())
                Spacer()
                Button("Disconnect") {
                    hrMonitor.disconnect()
                    hrStrapID = nil
                }
            }
        } else {
            DisclosureGroup("Connect heart-rate strap (optional)", isExpanded: $isHRExpanded) {
                HeartRatePicker(hrMonitor: hrMonitor)
                    .padding(.top, 8)
            }
        }
    }

    private func routeStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
        }
    }

    /// Total ascent over one lap (sum of positive elevation deltas).
    private var lapClimbMeters: Double {
        var gain = 0.0
        for index in 1..<route.points.count {
            let delta = route.points[index].elevationMeters - route.points[index - 1].elevationMeters
            if delta > 0 { gain += delta }
        }
        return gain
    }

    private var maxGradientPercent: Double {
        var maxGradient = 0.0
        for distance in stride(from: 0.0, to: route.lengthMeters, by: 50) {
            maxGradient = max(maxGradient, abs(route.gradient(atMeters: distance)))
        }
        return maxGradient
    }
}

// MARK: - Workout builder

/// "New workout…" sheet: the minimal interval builder from docs/erg-mode.md —
/// warmup / N × (work + recovery) / cooldown, minutes + absolute watts.
/// Watts pre-fill from the rider's FTP setting (50% / 105% / 55% / 40%);
/// steps stay absolute watts once saved (no %FTP re-scaling in v1).
struct WorkoutBuilderSheet: View {
    let onSave: (Workout) -> Void
    let onCancel: () -> Void

    @State private var name = "Intervals"
    @State private var warmupMinutes: Int
    @State private var warmupWatts: Int
    @State private var repeats: Int
    @State private var workMinutes: Int
    @State private var workWatts: Int
    @State private var recoveryMinutes: Int
    @State private var recoveryWatts: Int
    @State private var cooldownMinutes: Int
    @State private var cooldownWatts: Int

    init(ftp: Double, onSave: @escaping (Workout) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        // A classic 45-minute session as the starting point: 10' warmup,
        // 5 × (3' work / 2' recovery), 10' cooldown.
        _warmupMinutes = State(initialValue: 10)
        _warmupWatts = State(initialValue: Int((ftp * 0.5).rounded()))
        _repeats = State(initialValue: 5)
        _workMinutes = State(initialValue: 3)
        _workWatts = State(initialValue: Int((ftp * 1.05).rounded()))
        _recoveryMinutes = State(initialValue: 2)
        _recoveryWatts = State(initialValue: Int((ftp * 0.55).rounded()))
        _cooldownMinutes = State(initialValue: 10)
        _cooldownWatts = State(initialValue: Int((ftp * 0.4).rounded()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New workout")
                .font(.title2.bold())

            Form {
                TextField("Name", text: $name)
                Section("Warmup") {
                    partRow("Warmup", minutes: $warmupMinutes, watts: $warmupWatts)
                }
                Section("Intervals") {
                    Stepper("Repeats: \(repeats)", value: $repeats, in: 0...50)
                        .monospacedDigit()
                    partRow("Work", minutes: $workMinutes, watts: $workWatts)
                    partRow("Recovery", minutes: $recoveryMinutes, watts: $recoveryWatts)
                }
                Section("Cooldown") {
                    partRow("Cooldown", minutes: $cooldownMinutes, watts: $cooldownWatts)
                }
            }
            .formStyle(.grouped)

            HStack {
                // Live preview: recomputed from the fields on every change.
                Text("Total: \(formatWorkoutDuration(preview.totalDurationSeconds)) · \(preview.steps.count == 1 ? "1 step" : "\(preview.steps.count) steps")")
                    .font(.callout.bold())
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(preview)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(preview.steps.isEmpty || trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The workout the current fields describe — drives both the live total
    /// preview and Save (zero-duration parts are skipped by the factory).
    private var preview: Workout {
        Workout.intervals(
            name: trimmedName,
            warmup: (max(0, warmupWatts), TimeInterval(max(0, warmupMinutes) * 60)),
            repeats: max(0, repeats),
            work: (max(0, workWatts), TimeInterval(max(0, workMinutes) * 60)),
            recovery: (max(0, recoveryWatts), TimeInterval(max(0, recoveryMinutes) * 60)),
            cooldown: (max(0, cooldownWatts), TimeInterval(max(0, cooldownMinutes) * 60))
        )
    }

    private func partRow(_ label: String, minutes: Binding<Int>, watts: Binding<Int>) -> some View {
        HStack(spacing: 12) {
            Stepper(value: minutes, in: 0...180) {
                Text("\(label): \(minutes.wrappedValue) min")
                    .monospacedDigit()
            }
            Spacer()
            TextField("Watts", value: watts, format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Text("W")
                .foregroundStyle(.secondary)
        }
    }
}

/// "45 min" / "1 h 12 min" — the granularity a workout list needs.
private func formatWorkoutDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = Int(seconds) / 60
    guard totalMinutes >= 60 else { return "\(totalMinutes) min" }
    return "\(totalMinutes / 60) h \(String(format: "%02d", totalMinutes % 60)) min"
}

#Preview {
    RideSetupView(
        route: .island,
        isDemo: true,
        hrMonitor: HeartRateMonitor(),
        workoutStore: WorkoutStore(),
        onStart: { _ in },
        onStartWorkout: { _ in },
        onBack: {}
    )
    .frame(width: 760, height: 680)
}

#Preview("Builder") {
    WorkoutBuilderSheet(ftp: 200, onSave: { _ in }, onCancel: {})
}

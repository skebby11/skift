import SwiftUI

/// Keys and defaults for the rider's persisted settings (`UserDefaults`).
/// Shared between the Settings window and ContentView (which reads them when
/// a ride starts — changing settings mid-ride applies to the NEXT ride).
enum RiderSettings {
    static let riderKgKey = "riderKg"
    static let bikeKgKey = "bikeKg"
    static let trainerDifficultyKey = "trainerDifficulty"

    static let defaultRiderKg = 75.0
    static let defaultBikeKg = 8.0
    static let defaultTrainerDifficulty = 0.5
}

/// The standard macOS Settings window (⌘,).
struct SettingsView: View {
    @AppStorage(RiderSettings.riderKgKey)
    private var riderKg = RiderSettings.defaultRiderKg
    @AppStorage(RiderSettings.bikeKgKey)
    private var bikeKg = RiderSettings.defaultBikeKg
    @AppStorage(RiderSettings.trainerDifficultyKey)
    private var trainerDifficulty = RiderSettings.defaultTrainerDifficulty

    var body: some View {
        Form {
            Section("Rider") {
                // Weight drives the physics: heavier riders are slower uphill.
                Slider(value: $riderKg, in: 40...130, step: 1) {
                    Text("Rider weight: \(Int(riderKg)) kg")
                }
                Slider(value: $bikeKg, in: 5...15, step: 0.5) {
                    Text("Bike weight: \(bikeKg, specifier: "%.1f") kg")
                }
            }
            Section("Trainer") {
                // Fraction of the real gradient sent to the trainer. Speed is
                // unaffected — this only changes how hard climbs FEEL.
                Slider(value: $trainerDifficulty, in: 0...1, step: 0.05) {
                    Text("Trainer difficulty: \(Int(trainerDifficulty * 100)) %")
                }
                Text("At 100% an 8% climb feels like 8%; at 50% it feels like 4%. Your avatar's speed is not affected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}

#Preview {
    SettingsView()
}

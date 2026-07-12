import SwiftUI

/// Keys and defaults for the rider's persisted settings (`UserDefaults`).
/// Shared between the Settings window and ContentView (which reads them when
/// a ride starts — changing settings mid-ride applies to the NEXT ride).
enum RiderSettings {
    static let riderKgKey = "riderKg"
    static let bikeKgKey = "bikeKg"
    static let trainerDifficultyKey = "trainerDifficulty"
    static let ftpKey = "ftpWatts"
    /// Remembered heart-rate strap (UUID string), set on successful connect
    /// and cleared on user disconnect — see PairingView's HR section.
    static let hrStrapIDKey = "hrStrapID"
    /// The user's own Strava API application client ID (public, so
    /// `@AppStorage` is fine — the client secret and OAuth tokens live in
    /// the Keychain instead, see `StravaAccount` and docs/strava-upload.md).
    static let stravaClientIDKey = "stravaClientID"
    /// Upload completed rides to Strava automatically, without a tap.
    static let stravaAutoUploadKey = "stravaAutoUpload"

    static let defaultRiderKg = 75.0
    static let defaultBikeKg = 8.0
    static let defaultTrainerDifficulty = 0.5
    /// Functional Threshold Power — drives the HUD's power-zone chip.
    static let defaultFTP = 200.0
    static let defaultStravaAutoUpload = false
}

/// The standard macOS Settings window (⌘,).
struct SettingsView: View {
    @ObservedObject var strava: StravaAccount

    @AppStorage(RiderSettings.riderKgKey)
    private var riderKg = RiderSettings.defaultRiderKg
    @AppStorage(RiderSettings.bikeKgKey)
    private var bikeKg = RiderSettings.defaultBikeKg
    @AppStorage(RiderSettings.trainerDifficultyKey)
    private var trainerDifficulty = RiderSettings.defaultTrainerDifficulty
    @AppStorage(RiderSettings.ftpKey)
    private var ftp = RiderSettings.defaultFTP
    @AppStorage(RiderSettings.stravaClientIDKey)
    private var stravaClientID = ""
    @AppStorage(RiderSettings.stravaAutoUploadKey)
    private var stravaAutoUpload = RiderSettings.defaultStravaAutoUpload

    /// Local draft of the client secret; committed to Keychain on field
    /// submit or Connect — never stored in UserDefaults.
    @State private var clientSecretDraft = ""
    @State private var isConnecting = false
    @State private var stravaError: String?

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
                // FTP only affects the zone display, not the physics.
                Slider(value: $ftp, in: 80...400, step: 5) {
                    Text("FTP: \(Int(ftp)) W")
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
            Section("Strava") {
                stravaSection
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .onAppear {
            clientSecretDraft = strava.clientSecret
        }
    }

    // MARK: - Strava

    /// BYO API app: Skift is open source, so it can't ship a shared client
    /// secret — the user creates their own Strava API application and pastes
    /// its credentials here (docs/strava-upload.md).
    @ViewBuilder
    private var stravaSection: some View {
        TextField("Client ID", text: $stravaClientID)
            .disableAutocorrection(true)
        SecureField("Client secret", text: $clientSecretDraft)
            .onSubmit { strava.clientSecret = clientSecretDraft }

        Toggle("Auto-upload completed rides", isOn: $stravaAutoUpload)

        HStack {
            if strava.isConnected {
                Label(
                    strava.athleteName.map { "Connected as \($0)" } ?? "Connected",
                    systemImage: "checkmark.circle.fill"
                )
                .foregroundStyle(.green)
                Spacer()
                Button("Disconnect") { strava.disconnect() }
            } else {
                Text("Not connected")
                    .foregroundStyle(.secondary)
                Spacer()
                if isConnecting {
                    ProgressView()
                        .controlSize(.small)
                    Button("Cancel") { strava.cancelConnect() }
                } else {
                    Button("Connect Strava…") { connectStrava() }
                        .disabled(stravaClientID.isEmpty || clientSecretDraft.isEmpty)
                }
            }
        }

        if let stravaError {
            Text(stravaError)
                .font(.caption)
                .foregroundStyle(.red)
        }

        Text("Create an API app at strava.com/settings/api with callback domain 127.0.0.1")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func connectStrava() {
        // Connect implies commit: whatever is in the secret field is what
        // the flow should use (and what Keychain should keep).
        strava.clientSecret = clientSecretDraft
        isConnecting = true
        stravaError = nil
        Task {
            do {
                try await strava.connect()
            } catch is CancellationError {
                // Window closed mid-flow — no error worth surfacing.
            } catch {
                stravaError = error.localizedDescription
            }
            isConnecting = false
        }
    }
}

#Preview {
    SettingsView(strava: StravaAccount())
}

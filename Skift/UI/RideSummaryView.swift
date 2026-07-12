import SwiftUI
import SkiftKit
import UniformTypeIdentifiers

/// Post-ride sheet: summary stats plus TCX export (Strava-compatible) and,
/// when a Strava account is connected, direct upload (docs/strava-upload.md).
struct RideSummaryView: View {
    let recorder: RideRecorder
    @ObservedObject var strava: StravaAccount
    /// The ride as saved to History, nil when saving failed or the ride was
    /// too short to persist. Uploads are keyed on it: markUploaded needs the
    /// stored id, and auto-upload must not re-upload a ride that already
    /// carries an activity id.
    var savedRide: StoredRide?
    let rideStore: RideStore
    /// Non-nil when the automatic save to History failed. Failure never
    /// blocks the summary — this just surfaces it (docs/ride-history.md).
    var saveError: String? = nil
    let onDone: () -> Void

    @AppStorage(RiderSettings.stravaAutoUploadKey)
    private var stravaAutoUpload = RiderSettings.defaultStravaAutoUpload

    private enum UploadState: Equatable {
        case idle
        case uploading
        case uploaded(activityID: Int64)
        case failed(String)
    }

    @State private var exportMessage: String?
    @State private var uploadState: UploadState = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ride complete")
                .font(.title2.bold())

            if let summary = recorder.summary {
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 10) {
                    GridRow {
                        stat("Time", formatDuration(summary.durationSeconds))
                        stat("Distance", String(format: "%.2f km", summary.distanceMeters / 1000))
                        stat("Elevation", String(format: "%.0f m", summary.elevationGainMeters))
                    }
                    GridRow {
                        stat("Avg power", String(format: "%.0f W", summary.averagePowerWatts))
                        stat("Max power", "\(summary.maxPowerWatts) W")
                        stat("Energy", String(format: "%.0f kJ", summary.energyKilojoules))
                    }
                    GridRow {
                        stat("Avg cadence", summary.averageCadenceRpm.map { String(format: "%.0f rpm", $0) } ?? "—")
                        stat("Avg heart rate", summary.averageHeartRateBpm.map { String(format: "%.0f bpm", $0) } ?? "—")
                        stat("", "")
                    }
                }
            } else {
                Text("The ride was too short to record anything.")
                    .foregroundStyle(.secondary)
            }

            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let exportMessage {
                Text(exportMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            stravaStatusLine

            HStack {
                Button("Export TCX…") { exportTCX() }
                    .disabled(recorder.summary == nil)
                if strava.isConnected {
                    Button("Upload to Strava") { uploadToStrava() }
                        .disabled(recorder.summary == nil || uploadState == .uploading || isUploaded)
                }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 460)
        .onAppear {
            // Auto-upload: same path as the button, only when the toggle is
            // on, the account is connected, the ride made it into History,
            // and it doesn't already carry an activity id.
            if stravaAutoUpload, strava.isConnected,
               savedRide != nil, !isUploaded, uploadState == .idle {
                uploadToStrava()
            }
        }
    }

    // MARK: - Strava upload

    private var isUploaded: Bool {
        if case .uploaded = uploadState { return true }
        return savedRide?.stravaActivityID != nil
    }

    @ViewBuilder
    private var stravaStatusLine: some View {
        switch uploadState {
        case .idle:
            if let activityID = savedRide?.stravaActivityID {
                stravaLink(activityID: activityID)
            }
        case .uploading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Uploading to Strava…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case let .uploaded(activityID):
            stravaLink(activityID: activityID)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    private func stravaLink(activityID: Int64) -> some View {
        Link(destination: URL(string: "https://www.strava.com/activities/\(activityID)")!) {
            Label("View on Strava", systemImage: "checkmark.circle.fill")
        }
        .font(.callout)
    }

    private func uploadToStrava() {
        guard let tcx = TCXExporter.export(recorder: recorder) else { return }
        uploadState = .uploading
        Task {
            do {
                let activityID = try await strava.upload(
                    tcxData: Data(tcx.utf8),
                    name: "Skift virtual ride"
                )
                // Best-effort bookkeeping: the upload itself succeeded even
                // if this local write fails — the next History visit simply
                // offers upload again, and Strava dedupes.
                if let savedRide {
                    try? rideStore.markUploaded(id: savedRide.id, activityID: activityID)
                }
                uploadState = .uploaded(activityID: activityID)
            } catch {
                uploadState = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Stats

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    /// Writes the TCX file where the user chooses. Strava: "Upload activity"
    /// → "File" accepts .tcx directly.
    private func exportTCX() {
        guard let tcx = TCXExporter.export(recorder: recorder) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "tcx") ?? .xml]
        panel.nameFieldStringValue = "skift-ride.tcx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tcx.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Saved to \(url.lastPathComponent) — upload it on Strava via “Upload activity → File”."
        } catch {
            exportMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

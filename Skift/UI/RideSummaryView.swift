import SwiftUI
import SkiftKit
import UniformTypeIdentifiers

/// Post-ride sheet: summary stats plus TCX export (Strava-compatible).
struct RideSummaryView: View {
    let recorder: RideRecorder
    /// Non-nil when the automatic save to History failed. Failure never
    /// blocks the summary — this just surfaces it (docs/ride-history.md).
    var saveError: String? = nil
    let onDone: () -> Void

    @State private var exportMessage: String?

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

            HStack {
                Button("Export TCX…") { exportTCX() }
                    .disabled(recorder.summary == nil)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 460)
    }

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

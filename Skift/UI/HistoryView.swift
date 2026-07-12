import SwiftUI
import SkiftKit
import UniformTypeIdentifiers

/// Browse past rides: newest first, re-export any ride to TCX, upload it to
/// Strava (when connected), or delete it. Loads from `RideStore` on appear;
/// deleting or uploading refreshes the list (docs/ride-history.md,
/// docs/strava-upload.md).
struct HistoryView: View {
    let rideStore: RideStore
    @ObservedObject var strava: StravaAccount
    let onBack: () -> Void

    @State private var rides: [StoredRide] = []
    @State private var statusMessage: String?
    @State private var pendingDelete: StoredRide?
    /// The ride currently uploading, nil when none — one at a time keeps
    /// the UI (and Strava's rate limits) simple.
    @State private var uploadingRideID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: onBack)
                Spacer()
            }

            Text("History")
                .font(.largeTitle.bold())

            if let statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if rides.isEmpty {
                Spacer()
                Text("No rides yet — go ride the island!")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rides) { ride in
                            rideRow(ride)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(28)
        .onAppear(perform: load)
        .confirmationDialog(
            "Delete this ride?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { isPresented in if !isPresented { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { ride in
            Button("Delete", role: .destructive) { delete(ride) }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    private func rideRow(_ ride: StoredRide) -> some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.dateFormatter.string(from: ride.startDate))
                    .font(.headline)
                Text("\(String(format: "%.2f km", ride.distanceMeters / 1000)) · \(formatDuration(ride.durationSeconds)) · \(String(format: "%.0f W avg", ride.averagePowerWatts))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            stravaControl(ride)
            Button("Export TCX…") { export(ride) }
            Button(role: .destructive) {
                pendingDelete = ride
            } label: {
                Image(systemName: "trash")
            }
        }
        .padding(.vertical, 10)
    }

    /// Per-row Strava state: an "On Strava" badge linking to the activity
    /// once uploaded; otherwise an upload button when an account is
    /// connected (docs/strava-upload.md).
    @ViewBuilder
    private func stravaControl(_ ride: StoredRide) -> some View {
        if let activityID = ride.stravaActivityID {
            Link(destination: URL(string: "https://www.strava.com/activities/\(activityID)")!) {
                Label("On Strava", systemImage: "checkmark.circle.fill")
                    .font(.caption)
            }
            .foregroundStyle(.green)
        } else if strava.isConnected {
            if uploadingRideID == ride.id {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("Upload to Strava") { upload(ride) }
                    .disabled(uploadingRideID != nil)
            }
        }
    }

    // MARK: - Store operations

    private func load() {
        do {
            rides = try rideStore.list()
        } catch {
            rides = []
            statusMessage = "Couldn't load ride history: \(error.localizedDescription)"
        }
    }

    private func delete(_ ride: StoredRide) {
        pendingDelete = nil
        do {
            try rideStore.delete(id: ride.id)
            load()
        } catch {
            statusMessage = "Couldn't delete ride: \(error.localizedDescription)"
        }
    }

    /// Uploads a stored ride to Strava, records the activity id, and
    /// reloads so the row flips to its "On Strava" badge. Errors surface in
    /// the status line and never block the list (docs/strava-upload.md).
    private func upload(_ ride: StoredRide) {
        guard let tcx = tcxDocument(for: ride) else { return }
        uploadingRideID = ride.id
        statusMessage = nil
        Task {
            do {
                let activityID = try await strava.upload(
                    tcxData: Data(tcx.utf8),
                    name: "Skift virtual ride"
                )
                try? rideStore.markUploaded(id: ride.id, activityID: activityID)
                load()
            } catch {
                statusMessage = "Upload failed: \(error.localizedDescription)"
            }
            uploadingRideID = nil
        }
    }

    /// Rebuilds a recorder from the stored samples so exports and uploads
    /// produce exactly what the post-ride export would.
    private func tcxDocument(for ride: StoredRide) -> String? {
        let recorder = RideRecorder()
        recorder.begin(at: ride.startDate)
        ride.samples.forEach(recorder.append)
        return TCXExporter.export(recorder: recorder)
    }

    /// Writes the TCX file where the user chooses, mirroring
    /// RideSummaryView's export flow.
    private func export(_ ride: StoredRide) {
        guard let tcx = tcxDocument(for: ride) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "tcx") ?? .xml]
        panel.nameFieldStringValue = "skift-ride-\(Self.fileDateFormatter.string(from: ride.startDate)).tcx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tcx.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Saved to \(url.lastPathComponent) — upload it on Strava via “Upload activity → File”."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Formatting

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    /// Filesystem-safe timestamp (no colons) for the default export filename.
    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}

#Preview {
    HistoryView(rideStore: RideStore(), strava: StravaAccount(), onBack: {})
        .frame(width: 760, height: 620)
}

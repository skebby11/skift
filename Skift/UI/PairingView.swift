import SwiftUI
import SkiftKit

/// Guided trainer connection screen. Exits either with a trainer that has
/// SIM control ("Continue") or into demo mode (no hardware needed).
struct PairingView: View {
    @ObservedObject var trainer: TrainerManager
    @ObservedObject var hrMonitor: HeartRateMonitor
    let onReady: () -> Void
    let onDemo: () -> Void
    let onBack: () -> Void

    // Collapsed by default: pairing a strap is optional and must never
    // block or distract from getting the trainer connected.
    @State private var isHRSectionExpanded = false
    // The strap this screen is trying to connect, remembered so a
    // successful connect can be persisted under the right id (state only
    // carries the resolved name, not the id).
    @State private var pendingHRStrapID: UUID?

    @AppStorage(RiderSettings.hrStrapIDKey)
    private var hrStrapID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: onBack)
                Spacer()
            }

            Text("Connect your trainer")
                .font(.largeTitle.bold())

            connectionSection

            if let error = trainer.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            DisclosureGroup("Heart rate (optional)", isExpanded: $isHRSectionExpanded) {
                heartRateSection
                    .padding(.top, 8)
            }

            Spacer()

            // Escape hatch: the game is fully playable without hardware —
            // power comes from a slider instead of the trainer.
            HStack {
                Button("Try without a trainer (demo mode)", systemImage: "slider.horizontal.3", action: onDemo)
                Spacer()
                Button("Continue", action: onReady)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!trainer.hasControl)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .onAppear {
            // Silently reconnect to a remembered strap; never blocks Continue.
            if case .idle = hrMonitor.state, let stored = hrStrapID, let id = UUID(uuidString: stored) {
                pendingHRStrapID = id
                hrMonitor.connectRemembered(id: id)
            }
        }
        .onChange(of: hrMonitor.state) { _, newState in
            if case .connected = newState, let id = pendingHRStrapID {
                hrStrapID = id.uuidString
            }
        }
    }

    // MARK: - Connection states

    @ViewBuilder
    private var connectionSection: some View {
        switch trainer.state {
        case .bluetoothUnavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)

        case .idle:
            // Guided first-run flow: most "it doesn't connect" cases are a
            // sleeping trainer or another app holding it, so say it upfront.
            VStack(alignment: .leading, spacing: 8) {
                Label("Power the trainer and spin the pedals to wake it", systemImage: "1.circle")
                Label("Close other trainer apps (Zwift, MyWhoosh…) — only one can control it", systemImage: "2.circle")
                Label("Scan and pick it from the list", systemImage: "3.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            Button("Scan for trainers", systemImage: "antenna.radiowaves.left.and.right") {
                trainer.startScan()
            }
            deviceList

        case .scanning:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning for FTMS trainers…")
                Spacer()
                Button("Stop") { trainer.stopScan() }
            }
            if trainer.discovered.isEmpty {
                Text("Nothing yet? Spin the pedals — most trainers only advertise when awake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            deviceList

        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
            }

        case .reconnecting(let name, let attempt):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reconnecting to \(name)… (attempt \(attempt))")
            }

        case .connected(let name):
            HStack {
                Label(name, systemImage: "bicycle")
                    .font(.headline)
                if trainer.hasControl {
                    Label("SIM control active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("Requesting control…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Disconnect") { trainer.disconnect() }
            }
            // Live data preview doubles as a "it really works" confirmation:
            // pedal and watch the numbers move before starting a ride.
            liveDataPreview
        }
    }

    // MARK: - Heart rate (optional)

    @ViewBuilder
    private var heartRateSection: some View {
        switch hrMonitor.state {
        case .bluetoothUnavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)

        case .idle:
            Button("Scan for heart rate straps", systemImage: "antenna.radiowaves.left.and.right") {
                hrMonitor.startScan()
            }
            hrDeviceList

        case .scanning:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning for heart rate straps…")
                Spacer()
                Button("Stop") { hrMonitor.stopScan() }
            }
            hrDeviceList

        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
            }

        case .reconnecting(let name):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reconnecting to \(name)…")
            }

        case .connected(let name):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(name, systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Disconnect") {
                        hrMonitor.disconnect()
                        hrStrapID = nil
                    }
                }
                if let bpm = hrMonitor.bpm {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(bpm)")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("bpm")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Waiting for a reading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var hrDeviceList: some View {
        ForEach(hrMonitor.discovered) { sensor in
            HStack {
                Text(sensor.name)
                Text("\(sensor.rssi) dBm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Connect") {
                    pendingHRStrapID = sensor.id
                    hrMonitor.connect(sensor)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        ForEach(trainer.discovered) { device in
            HStack {
                Text(device.name)
                Text("\(device.rssi) dBm")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Connect") { trainer.connect(device) }
            }
            .padding(.vertical, 2)
        }
    }

    private var liveDataPreview: some View {
        Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 8) {
            GridRow {
                metric("Power", trainer.liveData.powerWatts.map { "\($0)" }, unit: "W")
                metric("Cadence", trainer.liveData.cadenceRpm.map { String(format: "%.0f", $0) }, unit: "rpm")
                metric("Speed", trainer.liveData.speedKmh.map { String(format: "%.1f", $0) }, unit: "km/h")
                metric("Heart rate", trainer.liveData.heartRateBpm.map { "\($0)" }, unit: "bpm")
            }
        }
        .padding(.top, 8)
    }

    private func metric(_ label: String, _ value: String?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "—")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    PairingView(trainer: TrainerManager(), hrMonitor: HeartRateMonitor(), onReady: {}, onDemo: {}, onBack: {})
        .frame(width: 760, height: 620)
}

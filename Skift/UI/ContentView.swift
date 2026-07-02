import SwiftUI
import SkiftKit

struct ContentView: View {
    @StateObject private var trainer = TrainerManager()
    @State private var grade = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            connectionSection
            if case .connected = trainer.state {
                Divider()
                metricsSection
                Divider()
                slopeSection
            }
            if let error = trainer.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(minWidth: 440, minHeight: 420)
    }

    // MARK: - Connection

    @ViewBuilder
    private var connectionSection: some View {
        switch trainer.state {
        case .bluetoothUnavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .idle:
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
            deviceList
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
            }
        case .connected(let name):
            HStack {
                Label(name, systemImage: "bicycle")
                    .font(.headline)
                if trainer.hasControl {
                    Text("SIM control active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Disconnect") { trainer.disconnect() }
            }
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

    // MARK: - Live metrics

    private var metricsSection: some View {
        Grid(alignment: .leading, horizontalSpacing: 32, verticalSpacing: 8) {
            GridRow {
                metric("Power", trainer.liveData.powerWatts.map { "\($0)" }, unit: "W")
                metric("Cadence", trainer.liveData.cadenceRpm.map { String(format: "%.0f", $0) }, unit: "rpm")
            }
            GridRow {
                metric("Speed", trainer.liveData.speedKmh.map { String(format: "%.1f", $0) }, unit: "km/h")
                metric("Heart rate", trainer.liveData.heartRateBpm.map { "\($0)" }, unit: "bpm")
            }
        }
    }

    private func metric(_ label: String, _ value: String?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "—")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Slope control

    private var slopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Slope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%+.1f %%", grade))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Slider(value: $grade, in: -10...15, step: 0.5) {
                Text("Slope")
            } minimumValueLabel: {
                Text("-10%")
            } maximumValueLabel: {
                Text("+15%")
            } onEditingChanged: { editing in
                if !editing {
                    trainer.setGrade(percent: grade)
                }
            }
            Text("Release the slider to send the gradient to the trainer.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!trainer.hasControl)
    }
}

#Preview {
    ContentView()
}

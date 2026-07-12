import SwiftUI
import SkiftKit

/// Reusable heart-rate strap pairing UI: scan, list of discovered straps,
/// connect, live bpm preview, disconnect. Shared by `PairingView`'s
/// "Heart rate (optional)" section and `RideSetupView`'s compact HR box —
/// see docs/hr-strap.md "Discoverability".
///
/// Owns only the bookkeeping needed to persist a *newly* connected strap's
/// id (`pendingHRStrapID` below, set when the user taps "Connect" in the
/// device list). Remembered-strap auto-reconnect (`connectRemembered`) is
/// triggered by whichever screen hosts this view, on that screen's own
/// `onAppear` — not by this component — so it fires even when this view is
/// hidden behind a collapsed disclosure.
struct HeartRatePicker: View {
    @ObservedObject var hrMonitor: HeartRateMonitor

    // The strap this view is trying to connect, remembered so a
    // successful connect can be persisted under the right id (state only
    // carries the resolved name, not the id).
    @State private var pendingHRStrapID: UUID?

    @AppStorage(RiderSettings.hrStrapIDKey)
    private var hrStrapID: String?

    var body: some View {
        Group {
            switch hrMonitor.state {
            case .bluetoothUnavailable(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)

            case .idle:
                Button("Scan for heart rate straps", systemImage: "antenna.radiowaves.left.and.right") {
                    hrMonitor.startScan()
                }
                deviceList

            case .scanning:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning for heart rate straps…")
                    Spacer()
                    Button("Stop") { hrMonitor.stopScan() }
                }
                deviceList

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
        .onChange(of: hrMonitor.state) { _, newState in
            if case .connected = newState, let id = pendingHRStrapID {
                hrStrapID = id.uuidString
            }
        }
    }

    @ViewBuilder
    private var deviceList: some View {
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
}

#Preview {
    HeartRatePicker(hrMonitor: HeartRateMonitor())
        .padding(28)
        .frame(width: 500)
}

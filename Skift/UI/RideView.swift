import SwiftUI
import SkiftKit

/// Full-bleed ride canvas with a compact, high-contrast training HUD.
struct RideView: View {
    @ObservedObject var engine: RideEngine

    @AppStorage(RiderSettings.ftpKey)
    private var ftp = RiderSettings.defaultFTP

    var body: some View {
        ZStack {
            RideSceneView(
                layout: engine.layout,
                distanceMeters: engine.distanceMeters,
                speedKmh: engine.speedKmh,
                cadenceRpm: engine.cadenceRpm ?? 0
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    // ERG panel sits right under the power panel so target
                    // and actual watts read as one column (docs/erg-mode.md).
                    VStack(alignment: .leading, spacing: 12) {
                        powerPanel
                        ergPanel
                    }
                    journeyPanel
                    Spacer(minLength: 12)
                    routePanel
                }

                if engine.isAutoPaused {
                    Label("Paused — start pedaling", systemImage: "pause.fill")
                        .font(.callout.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.72), in: Capsule())
                }

                Spacer(minLength: 100)
                elevationPanel
            }
            .padding(16)
        }
        .background(.black)
    }

    private var powerPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("POWER")
                .hudLabel()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(engine.powerWatts)")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("W")
                    .font(.title3.bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)

            HStack(spacing: 12) {
                Label(engine.cadenceRpm.map { String(format: "%.0f rpm", $0) } ?? "— rpm", systemImage: "metronome")
                if let heartRate = engine.heartRateBpm {
                    Label("\(heartRate) bpm", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                }
            }
            .font(.caption.bold())
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.82))

            HStack(spacing: 8) {
                zoneChip
                Text(String(format: "%.1f W/kg", Double(engine.powerWatts) / engine.riderProfile.riderKg))
                    .monospacedDigit()
            }
            .font(.caption.bold())
        }
        .hudPanel()
    }

    /// ERG panel, shown only during workout rides (`workoutState` is nil in
    /// SIM mode): the target the trainer is holding, the current step and its
    /// countdown, the next step, and the ±5 W / Skip controls — the classic
    /// head-unit workout strip (docs/erg-mode.md).
    @ViewBuilder
    private var ergPanel: some View {
        if let state = engine.workoutState {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("TARGET").hudLabel()
                    Spacer()
                    Text(state.currentStep.label.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.orange)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(state.currentStep.targetWatts)")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                    Text("W")
                        .font(.title3.bold())
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer(minLength: 16)
                    Text(formatCountdown(state.secondsLeftInStep))
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                Text(nextStepLine(state))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 8) {
                    ergButton("−5 W") { engine.adjustWorkoutWatts(by: -5) }
                    ergButton("+5 W") { engine.adjustWorkoutWatts(by: 5) }
                    Spacer()
                    ergButton("Skip") { engine.skipWorkoutStep() }
                }
            }
            .hudPanel()
            .frame(maxWidth: 210)
        }
    }

    private func ergButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .monospacedDigit()
        }
        .buttonStyle(.bordered)
        .tint(.orange)
    }

    /// mm:ss left in the current step, rounded up so a fresh 3-minute step
    /// reads 3:00, not 2:59.
    private func formatCountdown(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func nextStepLine(_ state: TrackerState) -> String {
        guard let next = state.nextStep else { return "Last step" }
        return "Next: \(next.label) · \(next.targetWatts) W"
    }

    private var journeyPanel: some View {
        HStack(spacing: 20) {
            hudMetric("SPEED", String(format: "%.1f", engine.speedKmh), "km/h")
            hudMetric("DISTANCE", String(format: "%.2f", engine.totalDistanceMeters / 1000), "km")
            hudMetric("TIME", formatTime(engine.elapsedSeconds), "")
        }
        .hudPanel()
    }

    private var routePanel: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text("GRADIENT").hudLabel()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Image(systemName: engine.gradientPercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.title3.bold())
                        .foregroundStyle(.orange)
                    Text(String(format: "%+.1f", engine.gradientPercent))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("%")
                        .foregroundStyle(.white.opacity(0.65))
                }
                Text(String(format: "%.0f m elevation", engine.elevationMeters))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            MiniMapView(layout: engine.layout, positionMeters: engine.distanceMeters)
                .frame(width: 112, height: 96)
        }
        .foregroundStyle(.white)
        .hudPanel(padding: 10)
    }

    private var elevationPanel: some View {
        VStack(spacing: 7) {
            HStack {
                Label("ROUTE PROFILE", systemImage: "mountain.2.fill")
                    .hudLabel()
                Spacer()
                if let target = engine.targetDistanceMeters {
                    Text(String(format: "%.1f / %.0f km", engine.totalDistanceMeters / 1000, target / 1000))
                        .font(.caption.bold())
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            ElevationProfileView(route: engine.route, positionMeters: engine.distanceMeters)
                .frame(height: 48)
            if let target = engine.targetDistanceMeters {
                ProgressView(value: min(engine.totalDistanceMeters / target, 1))
                    .tint(.orange)
            }
        }
        .hudPanel(padding: 10)
    }

    private var zoneChip: some View {
        let zone = PowerZone.zone(forPower: engine.powerWatts, ftp: ftp)
        return Text("Z\(zone.rawValue) · \(zone.name)")
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(zoneColor(zone).opacity(0.28), in: Capsule())
            .foregroundStyle(zoneColor(zone))
    }

    private func hudMetric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).hudLabel()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit).font(.caption).foregroundStyle(.white.opacity(0.65))
                }
            }
            .foregroundStyle(.white)
        }
    }

    private func zoneColor(_ zone: PowerZone) -> Color {
        switch zone {
        case .recovery: return .gray
        case .endurance: return .blue
        case .tempo: return .green
        case .threshold: return .yellow
        case .vo2max: return .orange
        case .anaerobic: return .red
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }
}

private extension View {
    func hudPanel(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }

    func hudLabel() -> some View {
        self.font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.65))
    }
}

/// Draws the route's elevation profile and the rider's position.
struct ElevationProfileView: View {
    let route: Route
    let positionMeters: Double
    private static let sampleCount = 300

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                profilePath(in: size, closed: true).fill(.orange.opacity(0.18))
                profilePath(in: size, closed: false).stroke(.orange, lineWidth: 2)
                Circle().fill(.white).frame(width: 8, height: 8)
                    .shadow(color: .orange, radius: 4)
                    .position(point(atMeters: positionMeters, in: size))
            }
        }
    }

    private func profilePath(in size: CGSize, closed: Bool) -> Path {
        Path { path in
            for sample in 0...Self.sampleCount {
                let distance = route.lengthMeters * Double(sample) / Double(Self.sampleCount)
                let point = point(atMeters: distance, in: size)
                sample == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            if closed {
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.closeSubpath()
            }
        }
    }

    private func point(atMeters distance: Double, in size: CGSize) -> CGPoint {
        let elevations = route.points.map(\.elevationMeters)
        let low = elevations.min() ?? 0
        let span = max((elevations.max() ?? 1) - low, 1)
        let normalized = (route.elevation(atMeters: distance) - low) / span
        return CGPoint(x: distance / route.lengthMeters * size.width, y: size.height * (0.9 - normalized * 0.75))
    }
}

#Preview {
    RideView(engine: RideEngine(route: .island))
        .frame(width: 1100, height: 700)
}

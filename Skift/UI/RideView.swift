import SwiftUI
import SkiftKit

/// The ride screen: 3D world, HUD numbers, and the elevation profile with
/// the rider's position.
struct RideView: View {
    @ObservedObject var engine: RideEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // The layout comes from the engine: building a TrackLayout means
            // sampling the whole spline, far too heavy for a per-frame call.
            RideSceneView(
                layout: engine.layout,
                distanceMeters: engine.distanceMeters,
                speedKmh: engine.speedKmh,
                cadenceRpm: engine.cadenceRpm ?? 0
            )
            .frame(minHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            // Zwift-style overlay: top-down mini map in the corner.
            .overlay(alignment: .topTrailing) {
                MiniMapView(layout: engine.layout, positionMeters: engine.distanceMeters)
                    .frame(width: 130, height: 130)
                    .padding(10)
            }
            // Auto-pause badge: the clock is stopped, say so.
            .overlay(alignment: .top) {
                if engine.isAutoPaused {
                    Label("Paused — start pedaling", systemImage: "pause.circle.fill")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(.top, 12)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                GridRow {
                    // Power leads: training is power-based, it's THE number.
                    metric("Power", "\(engine.powerWatts)", unit: "W", emphasized: true)
                    metric("Cadence", engine.cadenceRpm.map { String(format: "%.0f", $0) } ?? "—", unit: "rpm")
                    metric("Speed", String(format: "%.1f", engine.speedKmh), unit: "km/h")
                    metric("Distance", String(format: "%.2f", engine.totalDistanceMeters / 1000), unit: "km")
                    metric("Time", formatTime(engine.elapsedSeconds), unit: "")
                    metric("Gradient", String(format: "%+.1f", engine.gradientPercent), unit: "%")
                    metric("Elevation", String(format: "%.0f", engine.elevationMeters), unit: "m")
                }
            }

            // Training context row: power zone (Coggan, from the FTP set in
            // Settings), W/kg, heart rate when a strap is paired.
            HStack(spacing: 16) {
                zoneChip
                Text(String(format: "%.1f W/kg", Double(engine.powerWatts) / engine.riderProfile.riderKg))
                    .font(.callout)
                    .monospacedDigit()
                if let heartRate = engine.heartRateBpm {
                    Label("\(heartRate) bpm", systemImage: "heart.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
                Spacer()
            }

            // Finish-line progress, only on target rides (not free rides).
            if let target = engine.targetDistanceMeters {
                ProgressView(value: min(engine.totalDistanceMeters / target, 1)) {
                    Text(String(
                        format: "%.1f / %.0f km",
                        engine.totalDistanceMeters / 1000,
                        target / 1000
                    ))
                    .font(.caption)
                    .monospacedDigit()
                }
            }
            ElevationProfileView(route: engine.route, positionMeters: engine.distanceMeters)
                .frame(height: 140)
        }
    }

    // FTP from Settings drives the zone chip.
    @AppStorage(RiderSettings.ftpKey)
    private var ftp = RiderSettings.defaultFTP

    /// Colored capsule with the current Coggan zone (Z1 gray … Z6 red).
    private var zoneChip: some View {
        let zone = PowerZone.zone(forPower: engine.powerWatts, ftp: ftp)
        return Text("Z\(zone.rawValue) · \(zone.name)")
            .font(.callout.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(zoneColor(zone).opacity(0.25), in: Capsule())
            .foregroundStyle(zoneColor(zone))
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

    /// h:mm:ss ride clock for the HUD.
    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    private func metric(_ label: String, _ value: String, unit: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: emphasized ? 32 : 24, weight: emphasized ? .bold : .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(emphasized ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                Text(unit)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Draws the route's elevation profile and a dot at the rider's position.
struct ElevationProfileView: View {
    let route: Route
    let positionMeters: Double

    private static let sampleCount = 300

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                profilePath(in: size, closed: true)
                    .fill(.blue.opacity(0.15))
                profilePath(in: size, closed: false)
                    .stroke(.blue, lineWidth: 2)
                Circle()
                    .fill(.orange)
                    .frame(width: 10, height: 10)
                    .position(point(atMeters: positionMeters, in: size))
            }
        }
    }

    private func profilePath(in size: CGSize, closed: Bool) -> Path {
        Path { path in
            for sample in 0...Self.sampleCount {
                let distance = route.lengthMeters * Double(sample) / Double(Self.sampleCount)
                let p = point(atMeters: distance, in: size)
                if sample == 0 {
                    path.move(to: p)
                } else {
                    path.addLine(to: p)
                }
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
        let minElevation = elevations.min() ?? 0
        let maxElevation = elevations.max() ?? 1
        let span = max(maxElevation - minElevation, 1)
        let x = distance / route.lengthMeters * size.width
        // Leave headroom above and below so the line isn't glued to the edges.
        let normalized = (route.elevation(atMeters: distance) - minElevation) / span
        let y = size.height * (0.9 - normalized * 0.75)
        return CGPoint(x: x, y: y)
    }
}

#Preview {
    RideView(engine: RideEngine(route: .island))
        .padding()
}

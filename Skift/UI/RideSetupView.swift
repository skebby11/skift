import SwiftUI
import SkiftKit

/// Pre-ride screen: route card + target distance selector, like picking a
/// route in Zwift. "Free ride" means no finish line — ride until you quit.
struct RideSetupView: View {

    /// The selectable ride lengths. Raw value = target in meters (0 = free).
    enum Target: Double, CaseIterable, Identifiable {
        case freeRide = 0
        case km5 = 5000
        case km10 = 10000
        case km20 = 20000
        case km40 = 40000

        var id: Double { rawValue }

        var label: String {
            self == .freeRide ? "Free ride" : "\(Int(rawValue / 1000)) km"
        }

        /// nil target = no finish line.
        var meters: Double? { self == .freeRide ? nil : rawValue }
    }

    let route: Route
    let isDemo: Bool
    let onStart: (Double?) -> Void
    let onBack: () -> Void

    @State private var target: Target = .km10

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Button("Back", systemImage: "chevron.left", action: onBack)
                Spacer()
                if isDemo {
                    Label("Demo mode — no trainer", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(route.name)
                .font(.largeTitle.bold())

            // Route card: the numbers a cyclist wants before clipping in.
            HStack(spacing: 24) {
                routeStat("Lap length", String(format: "%.1f km", route.lengthMeters / 1000))
                routeStat("Climb", String(format: "%.0f m", lapClimbMeters))
                routeStat("Max gradient", String(format: "%.0f %%", maxGradientPercent))
            }

            ElevationProfileView(route: route, positionMeters: 0)
                .frame(height: 120)

            Text("How far do you want to ride?")
                .font(.headline)
            // Longer than a lap simply loops the island again.
            Picker("Target distance", selection: $target) {
                ForEach(Target.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Spacer()

            HStack {
                Spacer()
                Button {
                    onStart(target.meters)
                } label: {
                    Label("Start ride", systemImage: "flag.checkered")
                        .font(.title3.bold())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }

    private func routeStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
        }
    }

    /// Total ascent over one lap (sum of positive elevation deltas).
    private var lapClimbMeters: Double {
        var gain = 0.0
        for index in 1..<route.points.count {
            let delta = route.points[index].elevationMeters - route.points[index - 1].elevationMeters
            if delta > 0 { gain += delta }
        }
        return gain
    }

    private var maxGradientPercent: Double {
        var maxGradient = 0.0
        for distance in stride(from: 0.0, to: route.lengthMeters, by: 50) {
            maxGradient = max(maxGradient, abs(route.gradient(atMeters: distance)))
        }
        return maxGradient
    }
}

#Preview {
    RideSetupView(route: .island, isDemo: true, onStart: { _ in }, onBack: {})
        .frame(width: 760, height: 620)
}

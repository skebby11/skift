import SwiftUI
import SkiftKit

/// Top-down mini map of the route: the track outline with a dot at the
/// rider's position. Overlaid on a corner of the 3D scene, Zwift-style.
struct MiniMapView: View {
    let layout: TrackLayout
    let positionMeters: Double

    /// Track outline resolution; 256 points is smooth at mini-map sizes.
    private static let sampleCount = 256

    var body: some View {
        GeometryReader { geometry in
            let points = mapPoints(in: geometry.size)
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                    path.closeSubpath()
                }
                .stroke(.white.opacity(0.9), lineWidth: 2)

                Circle()
                    .fill(.orange)
                    .frame(width: 8, height: 8)
                    .position(riderPoint(in: geometry.size))
            }
        }
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Projects the track's XZ shape into the view, preserving aspect ratio.
    private func project(_ world: SIMD3<Float>, bounds: (min: CGPoint, max: CGPoint), size: CGSize) -> CGPoint {
        let worldWidth = max(bounds.max.x - bounds.min.x, 1)
        let worldHeight = max(bounds.max.y - bounds.min.y, 1)
        // Uniform scale with 10% padding so the loop isn't distorted.
        let scale = min(size.width / worldWidth, size.height / worldHeight) * 0.85
        let offsetX = (size.width - worldWidth * scale) / 2
        let offsetY = (size.height - worldHeight * scale) / 2
        return CGPoint(
            x: offsetX + (CGFloat(world.x) - bounds.min.x) * scale,
            y: offsetY + (CGFloat(world.z) - bounds.min.y) * scale
        )
    }

    private func trackBounds() -> (min: CGPoint, max: CGPoint) {
        var minX = CGFloat.greatestFiniteMagnitude, minZ = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxZ = -CGFloat.greatestFiniteMagnitude
        for sample in 0..<Self.sampleCount {
            let d = layout.route.lengthMeters * Double(sample) / Double(Self.sampleCount)
            let p = layout.position(atMeters: d)
            minX = min(minX, CGFloat(p.x)); maxX = max(maxX, CGFloat(p.x))
            minZ = min(minZ, CGFloat(p.z)); maxZ = max(maxZ, CGFloat(p.z))
        }
        return (CGPoint(x: minX, y: minZ), CGPoint(x: maxX, y: maxZ))
    }

    private func mapPoints(in size: CGSize) -> [CGPoint] {
        let bounds = trackBounds()
        return (0..<Self.sampleCount).map { sample in
            let d = layout.route.lengthMeters * Double(sample) / Double(Self.sampleCount)
            return project(layout.position(atMeters: d), bounds: bounds, size: size)
        }
    }

    private func riderPoint(in size: CGSize) -> CGPoint {
        project(layout.position(atMeters: positionMeters), bounds: trackBounds(), size: size)
    }
}

import Foundation
import simd

/// Maps 1D route distance to 3D world coordinates (meters; Y is up).
///
/// The horizontal shape of the track is a hand-authored closed loop (control
/// points below) smoothed with a Catmull-Rom spline, then uniformly scaled so
/// the path length exactly matches the route length — one meter ridden is one
/// meter through the world. Elevation comes from the `Route` profile and
/// becomes Y.
///
/// How it works:
/// 1. The closed spline is sampled densely into a polyline.
/// 2. Cumulative arc lengths are computed per sample.
/// 3. `position(atMeters:)` binary-searches the arc-length table and
///    interpolates within the matching segment.
///
/// REVIEW: the loop shape is a first draft drawn blind — reshape the control
/// points once the island can be seen in-app (M3 art pass).
public struct TrackLayout {

    public let route: Route

    /// Densely sampled spline points (XZ plane, already scaled to meters).
    private let samples: [SIMD2<Double>]
    /// samples[i] is at cumulativeLengths[i] meters from the start.
    private let cumulativeLengths: [Double]

    /// Hand-drawn island loop in arbitrary units (scaled to fit the route
    /// length at init). Roughly: a long seaside straight, a hairpin cape at
    /// the south, the climb zig-zagging up the east side, a ridge at the top
    /// and a sweeping descent back west.
    private static let controlPoints: [SIMD2<Double>] = [
        SIMD2(0, 0), SIMD2(4, -1), SIMD2(7, 1), SIMD2(9, 4),
        SIMD2(8, 7), SIMD2(5, 8), SIMD2(3, 11), SIMD2(0, 12),
        SIMD2(-3, 10), SIMD2(-5, 7), SIMD2(-6, 4), SIMD2(-4, 1),
    ]

    /// Spline samples per control-point segment. 100 keeps the worst-case
    /// polyline error well under 10 cm at this scale.
    private static let samplesPerSegment = 100

    public init(route: Route) {
        self.route = route

        // 1. Sample the unscaled closed spline.
        var raw: [SIMD2<Double>] = []
        let n = Self.controlPoints.count
        for segment in 0..<n {
            // Catmull-Rom needs the two neighbours on each side; wrap around
            // because the loop is closed.
            let p0 = Self.controlPoints[(segment + n - 1) % n]
            let p1 = Self.controlPoints[segment]
            let p2 = Self.controlPoints[(segment + 1) % n]
            let p3 = Self.controlPoints[(segment + 2) % n]
            for step in 0..<Self.samplesPerSegment {
                let t = Double(step) / Double(Self.samplesPerSegment)
                raw.append(Self.catmullRom(p0, p1, p2, p3, t))
            }
        }
        raw.append(raw[0]) // close the polyline

        // 2. Scale so the polyline length equals the route length.
        var unscaledLength = 0.0
        for i in 1..<raw.count {
            unscaledLength += simd_distance(raw[i - 1], raw[i])
        }
        let scale = route.lengthMeters / unscaledLength
        let scaled = raw.map { $0 * scale }

        // 3. Precompute the arc-length table used by position(atMeters:).
        var lengths = [0.0]
        lengths.reserveCapacity(scaled.count)
        for i in 1..<scaled.count {
            lengths.append(lengths[i - 1] + simd_distance(scaled[i - 1], scaled[i]))
        }
        self.samples = scaled
        self.cumulativeLengths = lengths
    }

    public func position(atMeters distance: Double) -> SIMD3<Float> {
        var wrapped = distance.truncatingRemainder(dividingBy: route.lengthMeters)
        if wrapped < 0 { wrapped += route.lengthMeters }

        // Binary search: first sample index whose arc length exceeds `wrapped`.
        var low = 1
        var high = cumulativeLengths.count - 1
        while low < high {
            let mid = (low + high) / 2
            if cumulativeLengths[mid] < wrapped {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let segmentLength = cumulativeLengths[low] - cumulativeLengths[low - 1]
        let fraction = segmentLength > 0 ? (wrapped - cumulativeLengths[low - 1]) / segmentLength : 0
        let point = simd_mix(samples[low - 1], samples[low], SIMD2(repeating: fraction))

        return SIMD3(
            Float(point.x),
            Float(route.elevation(atMeters: wrapped)),
            Float(point.y)
        )
    }

    /// Unit vector pointing down the road in the direction of travel
    /// (includes the vertical component, so it also encodes the slope).
    public func tangent(atMeters distance: Double) -> SIMD3<Float> {
        // Central difference smooths the corner between polyline segments.
        let behind = position(atMeters: distance - 1)
        let ahead = position(atMeters: distance + 1)
        return simd_normalize(ahead - behind)
    }

    /// Standard Catmull-Rom interpolation between p1 and p2 (t in 0...1).
    private static func catmullRom(
        _ p0: SIMD2<Double>, _ p1: SIMD2<Double>,
        _ p2: SIMD2<Double>, _ p3: SIMD2<Double>,
        _ t: Double
    ) -> SIMD2<Double> {
        let t2 = t * t
        let t3 = t2 * t
        let a = 2 * p1
        let b = (p2 - p0) * t
        let c = (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
        let d = (3 * p1 - p0 - 3 * p2 + p3) * t3
        return 0.5 * (a + b + c + d)
    }
}

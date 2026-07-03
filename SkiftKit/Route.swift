import Foundation

public struct RoutePoint: Equatable {
    public let distanceMeters: Double
    public let elevationMeters: Double

    public init(distanceMeters: Double, elevationMeters: Double) {
        self.distanceMeters = distanceMeters
        self.elevationMeters = elevationMeters
    }
}

/// A looped route as a piecewise-linear elevation profile. Elevation is
/// interpolated within segments; the gradient is each segment's slope.
/// Distances outside [0, length) wrap around, so riding past the end starts
/// the next lap.
public struct Route: Equatable {
    public let name: String
    public let points: [RoutePoint]

    /// - Parameter points: sorted by distance, starting at 0, at least two.
    public init(name: String, points: [RoutePoint]) {
        precondition(points.count >= 2, "A route needs at least two points")
        self.name = name
        self.points = points
    }

    public var lengthMeters: Double {
        points[points.count - 1].distanceMeters
    }

    public func elevation(atMeters distance: Double) -> Double {
        let (from, to, fraction) = segment(atMeters: distance)
        return from.elevationMeters + (to.elevationMeters - from.elevationMeters) * fraction
    }

    /// Gradient in percent (rise/run × 100) of the segment containing `distance`.
    /// Steps at segment boundaries — use `smoothedGradient` for anything the
    /// rider feels (trainer resistance, physics).
    public func gradient(atMeters distance: Double) -> Double {
        let (from, to, _) = segment(atMeters: distance)
        let run = to.distanceMeters - from.distanceMeters
        guard run > 0 else { return 0 }
        return (to.elevationMeters - from.elevationMeters) / run * 100
    }

    /// Gradient as a central difference of elevation over ±`windowMeters`.
    /// Continuous everywhere (elevation is continuous and the loop closes),
    /// so the trainer's resistance ramps smoothly through profile corners
    /// instead of stepping; converges to the raw segment slope in the middle
    /// of segments longer than the window.
    public func smoothedGradient(atMeters distance: Double, windowMeters: Double = 30) -> Double {
        let ahead = elevation(atMeters: distance + windowMeters)
        let behind = elevation(atMeters: distance - windowMeters)
        return (ahead - behind) / (2 * windowMeters) * 100
    }

    private func segment(atMeters distance: Double) -> (RoutePoint, RoutePoint, Double) {
        var wrapped = distance.truncatingRemainder(dividingBy: lengthMeters)
        if wrapped < 0 { wrapped += lengthMeters }

        for index in 1..<points.count where points[index].distanceMeters >= wrapped {
            let from = points[index - 1]
            let to = points[index]
            let run = to.distanceMeters - from.distanceMeters
            let fraction = run > 0 ? (wrapped - from.distanceMeters) / run : 0
            return (from, to, fraction)
        }
        return (points[points.count - 2], points[points.count - 1], 1)
    }
}

extension Route {
    /// Placeholder elevation profile of the planned v1 map (Plan.md §6, M3):
    /// an 8.2 km island loop — flat start, rolling section, ~1.8 km climb at
    /// ~5% up to 110 m, descent, rolling return to the start elevation.
    ///
    /// REVIEW: gradient is constant within each segment, so the trainer's
    /// resistance changes in steps at segment boundaries. If that feels
    /// abrupt on hardware, either add more points or smooth the gradient
    /// (e.g. Catmull-Rom on elevation) — the 3D world already smooths
    /// visually via TrackLayout.
    public static let island = Route(name: "Skift Island", points: [
        RoutePoint(distanceMeters: 0, elevationMeters: 10),
        RoutePoint(distanceMeters: 800, elevationMeters: 12),
        RoutePoint(distanceMeters: 1500, elevationMeters: 10),
        RoutePoint(distanceMeters: 2000, elevationMeters: 18),
        RoutePoint(distanceMeters: 2500, elevationMeters: 14),
        RoutePoint(distanceMeters: 3000, elevationMeters: 20),
        RoutePoint(distanceMeters: 3600, elevationMeters: 50),
        RoutePoint(distanceMeters: 4200, elevationMeters: 80),
        RoutePoint(distanceMeters: 4800, elevationMeters: 110),
        RoutePoint(distanceMeters: 5400, elevationMeters: 80),
        RoutePoint(distanceMeters: 6000, elevationMeters: 45),
        RoutePoint(distanceMeters: 6300, elevationMeters: 30),
        RoutePoint(distanceMeters: 7000, elevationMeters: 18),
        RoutePoint(distanceMeters: 7600, elevationMeters: 12),
        RoutePoint(distanceMeters: 8200, elevationMeters: 10),
    ])
}

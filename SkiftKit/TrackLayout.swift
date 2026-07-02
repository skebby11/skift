import Foundation
import simd

/// Maps 1D route distance to 3D world coordinates (meters; Y is up).
///
/// Placeholder layout for the first M3 slice: the loop is laid out as a
/// circle whose circumference equals the route length, so speed on the road
/// matches speed through the world 1:1; the route's elevation becomes Y.
/// An authored 2D spline replaces the circle later — consumers only use
/// `position(atMeters:)` and `tangent(atMeters:)`.
public struct TrackLayout {

    public let route: Route
    private let radius: Double

    public init(route: Route) {
        self.route = route
        self.radius = route.lengthMeters / (2 * .pi)
    }

    public func position(atMeters distance: Double) -> SIMD3<Float> {
        let angle = distance / radius // arc length = r·θ
        return SIMD3(
            Float(radius * cos(angle)),
            Float(route.elevation(atMeters: distance)),
            Float(radius * sin(angle))
        )
    }

    /// Unit vector pointing down the road in the direction of travel.
    public func tangent(atMeters distance: Double) -> SIMD3<Float> {
        let here = position(atMeters: distance)
        let ahead = position(atMeters: distance + 1)
        return simd_normalize(ahead - here)
    }
}

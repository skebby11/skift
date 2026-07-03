import XCTest
@testable import SkiftKit

final class RouteTests: XCTestCase {

    private let ramp = Route(name: "Ramp", points: [
        RoutePoint(distanceMeters: 0, elevationMeters: 0),
        RoutePoint(distanceMeters: 100, elevationMeters: 10),
        RoutePoint(distanceMeters: 200, elevationMeters: 10),
        RoutePoint(distanceMeters: 400, elevationMeters: 0),
    ])

    func testInterpolatesElevationWithinSegments() {
        XCTAssertEqual(ramp.elevation(atMeters: 0), 0)
        XCTAssertEqual(ramp.elevation(atMeters: 50), 5, accuracy: 0.001)
        XCTAssertEqual(ramp.elevation(atMeters: 150), 10, accuracy: 0.001)
        XCTAssertEqual(ramp.elevation(atMeters: 300), 5, accuracy: 0.001)
    }

    func testGradientIsSegmentSlope() {
        XCTAssertEqual(ramp.gradient(atMeters: 50), 10, accuracy: 0.001)   // +10 m / 100 m
        XCTAssertEqual(ramp.gradient(atMeters: 150), 0, accuracy: 0.001)
        XCTAssertEqual(ramp.gradient(atMeters: 300), -5, accuracy: 0.001)  // -10 m / 200 m
    }

    func testDistanceWrapsAroundTheLoop() {
        XCTAssertEqual(ramp.elevation(atMeters: 450), ramp.elevation(atMeters: 50), accuracy: 0.001)
        XCTAssertEqual(ramp.gradient(atMeters: 850), ramp.gradient(atMeters: 50), accuracy: 0.001)
        XCTAssertEqual(ramp.elevation(atMeters: -50), ramp.elevation(atMeters: 350), accuracy: 0.001)
    }

    func testSmoothedGradientMatchesRawSlopeMidSegment() {
        // In the middle of a segment much longer than the window the central
        // difference must recover the raw slope.
        XCTAssertEqual(ramp.smoothedGradient(atMeters: 50), 10, accuracy: 0.001)
        XCTAssertEqual(ramp.smoothedGradient(atMeters: 300), -5, accuracy: 0.001)
    }

    func testSmoothedGradientHasNoSteps() {
        // Raw gradient jumps 10 → 0 at 100 m; smoothed must ramp through it:
        // no two points 1 m apart may differ by more than ~1 % of gradient.
        let island = Route.island
        var previous = island.smoothedGradient(atMeters: 0)
        for distance in stride(from: 1.0, through: island.lengthMeters, by: 1) {
            let current = island.smoothedGradient(atMeters: distance)
            XCTAssertLessThan(abs(current - previous), 1.0, "step at \(distance) m")
            previous = current
        }
    }
        let island = Route.island
        XCTAssertEqual(island.lengthMeters, 8200)
        // The loop closes: same elevation at start and end.
        XCTAssertEqual(island.elevation(atMeters: 0), island.elevation(atMeters: island.lengthMeters - 0.001), accuracy: 0.1)
        // The climb is a real climb.
        XCTAssertEqual(island.gradient(atMeters: 4000), 5, accuracy: 0.5)
        // No absurd gradients anywhere.
        for distance in stride(from: 0.0, to: island.lengthMeters, by: 10) {
            XCTAssertLessThan(abs(island.gradient(atMeters: distance)), 10)
        }
    }
}

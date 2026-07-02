import XCTest
import simd
@testable import SkiftKit

final class TrackLayoutTests: XCTestCase {

    private let layout = TrackLayout(route: .island)

    func testLoopCloses() {
        let start = layout.position(atMeters: 0)
        let end = layout.position(atMeters: layout.route.lengthMeters)
        XCTAssertLessThan(simd_distance(start, end), 0.01)
    }

    func testHorizontalDistanceFromCenterIsTheRadius() {
        let expectedRadius = Float(layout.route.lengthMeters / (2 * .pi))
        for distance in stride(from: 0.0, to: layout.route.lengthMeters, by: 500) {
            let p = layout.position(atMeters: distance)
            let horizontal = simd_length(SIMD2(p.x, p.z))
            XCTAssertEqual(horizontal, expectedRadius, accuracy: 0.01)
        }
    }

    func testHeightMatchesRouteElevation() {
        for distance in stride(from: 0.0, to: layout.route.lengthMeters, by: 500) {
            XCTAssertEqual(
                Double(layout.position(atMeters: distance).y),
                layout.route.elevation(atMeters: distance),
                accuracy: 0.01
            )
        }
    }

    func testTangentIsUnitLengthAndFollowsTravel() {
        for distance in stride(from: 0.0, to: layout.route.lengthMeters, by: 500) {
            let t = layout.tangent(atMeters: distance)
            XCTAssertEqual(simd_length(t), 1, accuracy: 0.001)
            // Moving forward along the tangent should be moving along the track.
            let here = layout.position(atMeters: distance)
            let ahead = layout.position(atMeters: distance + 10)
            XCTAssertGreaterThan(simd_dot(t, simd_normalize(ahead - here)), 0.99)
        }
    }

    func testWorldArcLengthMatchesRouteDistance() {
        // 100 m along the route ≈ 100 m through the world (flat-ish segment).
        let a = layout.position(atMeters: 1000)
        let b = layout.position(atMeters: 1100)
        XCTAssertEqual(simd_distance(a, b), 100, accuracy: 1.5)
    }
}

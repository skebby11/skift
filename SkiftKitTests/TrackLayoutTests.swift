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

    func testHeightMatchesRouteElevation() {
        for distance in stride(from: 0.0, to: layout.route.lengthMeters, by: 250) {
            XCTAssertEqual(
                Double(layout.position(atMeters: distance).y),
                layout.route.elevation(atMeters: distance),
                accuracy: 0.01
            )
        }
    }

    func testWorldArcLengthMatchesRouteDistance() {
        // Summing short chords around the whole loop must recover the route
        // length: one meter ridden is one meter through the world (±1%).
        var total = 0.0
        let step = 10.0
        var distance = 0.0
        while distance < layout.route.lengthMeters {
            let a = layout.position(atMeters: distance)
            let b = layout.position(atMeters: distance + step)
            total += Double(simd_distance(SIMD2(a.x, a.z), SIMD2(b.x, b.z)))
            distance += step
        }
        XCTAssertEqual(total, layout.route.lengthMeters, accuracy: layout.route.lengthMeters * 0.01)
    }

    func testTangentIsUnitLengthAndFollowsTravel() {
        for distance in stride(from: 0.0, to: layout.route.lengthMeters, by: 250) {
            let t = layout.tangent(atMeters: distance)
            XCTAssertEqual(simd_length(t), 1, accuracy: 0.001)
            // Moving forward along the tangent should be moving along the track.
            let here = layout.position(atMeters: distance)
            let ahead = layout.position(atMeters: distance + 5)
            XCTAssertGreaterThan(simd_dot(t, simd_normalize(ahead - here)), 0.95)
        }
    }

    func testTrackDoesNotWanderAbsurdlyFar() {
        // The island should fit in a sensible bounding box (a few km), not
        // degenerate because of a spline/scale bug.
        for distance in stride(from: 0.0, to: layout.route.lengthMeters, by: 100) {
            let p = layout.position(atMeters: distance)
            XCTAssertLessThan(simd_length(SIMD2(p.x, p.z)), 5000)
        }
    }

    func testNegativeAndOverflowDistancesWrap() {
        let wrapped = layout.position(atMeters: layout.route.lengthMeters + 500)
        let direct = layout.position(atMeters: 500)
        XCTAssertLessThan(simd_distance(wrapped, direct), 0.01)

        let negative = layout.position(atMeters: -500)
        let equivalent = layout.position(atMeters: layout.route.lengthMeters - 500)
        XCTAssertLessThan(simd_distance(negative, equivalent), 0.01)
    }
}

import XCTest
@testable import SkiftKit

final class PhysicsTests: XCTestCase {

    func testConvergesToSteadyStateOnFlat() {
        var engine = PhysicsEngine()
        for _ in 0..<6000 { // 10 simulated minutes at 10 Hz
            engine.step(powerWatts: 250, gradePercent: 0, dt: 0.1)
        }
        // At terminal speed the drive power equals the resistive power.
        let residual = engine.requiredPower(atSpeedMS: engine.speedMS, gradePercent: 0)
        XCTAssertEqual(residual, 250, accuracy: 5)
        // Sanity: 250 W on the flat is roughly 36–39 km/h for the default profile.
        XCTAssertEqual(engine.speedMS * 3.6, 37.5, accuracy: 2.5)
    }

    func testClimbingIsSlowerThanFlat() {
        var flat = PhysicsEngine()
        var climb = PhysicsEngine()
        for _ in 0..<6000 {
            flat.step(powerWatts: 200, gradePercent: 0, dt: 0.1)
            climb.step(powerWatts: 200, gradePercent: 8, dt: 0.1)
        }
        XCTAssertLessThan(climb.speedMS, flat.speedMS / 2)
    }

    func testCoastsDownhillFromStandstill() {
        var engine = PhysicsEngine()
        for _ in 0..<1200 { // 2 minutes
            engine.step(powerWatts: 0, gradePercent: -5, dt: 0.1)
        }
        // Gravity alone should reach a healthy descent speed (~50 km/h region).
        XCTAssertGreaterThan(engine.speedMS, 10)
        XCTAssertLessThan(engine.speedMS, 20)
    }

    func testDeceleratesToStopUphillWithoutPower() {
        var engine = PhysicsEngine()
        for _ in 0..<300 { // get up to speed on the flat
            engine.step(powerWatts: 300, gradePercent: 0, dt: 0.1)
        }
        for _ in 0..<600 { // then 0 W into an 8% wall
            engine.step(powerWatts: 0, gradePercent: 8, dt: 0.1)
        }
        XCTAssertEqual(engine.speedMS, 0)
    }

    func testSpeedIsNeverNegative() {
        var engine = PhysicsEngine()
        for _ in 0..<100 {
            engine.step(powerWatts: 0, gradePercent: 15, dt: 0.5)
            XCTAssertGreaterThanOrEqual(engine.speedMS, 0)
        }
    }

    func testHeavierRiderIsSlowerUphill() {
        var light = PhysicsEngine(profile: RiderProfile(riderKg: 60))
        var heavy = PhysicsEngine(profile: RiderProfile(riderKg: 90))
        for _ in 0..<3000 {
            light.step(powerWatts: 220, gradePercent: 6, dt: 0.1)
            heavy.step(powerWatts: 220, gradePercent: 6, dt: 0.1)
        }
        XCTAssertGreaterThan(light.speedMS, heavy.speedMS)
    }
}

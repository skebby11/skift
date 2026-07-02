import XCTest
@testable import SkiftKit

private final class FakeTrainer: TrainerControlling {
    var receivedGrades: [Double] = []
    func setGrade(percent: Double) {
        receivedGrades.append(percent)
    }
}

final class RideEngineTests: XCTestCase {

    private func makeEngine(route: Route = .island) -> (RideEngine, FakeTrainer) {
        let engine = RideEngine(route: route)
        let trainer = FakeTrainer()
        engine.start(powerSource: { 200 }, control: trainer)
        engine.stop() // kill the timer; tests drive step(dt:) manually
        return (engine, trainer)
    }

    func testAdvancesAlongTheRouteUnderPower() {
        let (engine, _) = makeEngine()
        for _ in 0..<600 { // one simulated minute at 200 W
            engine.step(dt: 0.1)
        }
        XCTAssertGreaterThan(engine.speedKmh, 20)
        XCTAssertGreaterThan(engine.distanceMeters, 300)
        XCTAssertEqual(engine.gradientPercent, engine.route.gradient(atMeters: engine.distanceMeters), accuracy: 0.001)
    }

    func testSendsScaledGradeToTrainer() {
        let (engine, trainer) = makeEngine()
        engine.trainerDifficulty = 0.5
        engine.step(dt: 0.1)
        let expected = engine.route.gradient(atMeters: 0) * 0.5
        XCTAssertEqual(trainer.receivedGrades.first ?? .nan, expected, accuracy: 0.001)
    }

    func testDoesNotSpamTrainerWhileGradientIsStable() {
        // A perfectly flat loop: the gradient never changes after the first send.
        let flat = Route(name: "Flat", points: [
            RoutePoint(distanceMeters: 0, elevationMeters: 0),
            RoutePoint(distanceMeters: 5000, elevationMeters: 0),
        ])
        let (engine, trainer) = makeEngine(route: flat)
        for _ in 0..<300 { // 30 simulated seconds
            engine.step(dt: 0.1)
        }
        XCTAssertEqual(trainer.receivedGrades.count, 1)
    }

    func testLapWrapsDistanceButKeepsTotal() {
        let shortLoop = Route(name: "Short", points: [
            RoutePoint(distanceMeters: 0, elevationMeters: 0),
            RoutePoint(distanceMeters: 100, elevationMeters: 0),
        ])
        let (engine, _) = makeEngine(route: shortLoop)
        for _ in 0..<600 {
            engine.step(dt: 0.1)
        }
        XCTAssertGreaterThan(engine.totalDistanceMeters, 100)
        XCTAssertLessThan(engine.distanceMeters, 100)
    }
}

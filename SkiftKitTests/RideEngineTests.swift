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
        engine.start(
            dataSource: { FTMS.IndoorBikeData(cadenceRpm: 90, powerWatts: 200, heartRateBpm: 150) },
            control: trainer
        )
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
        XCTAssertEqual(engine.gradientPercent, engine.route.smoothedGradient(atMeters: engine.distanceMeters), accuracy: 0.001)
    }

    func testSendsScaledGradeToTrainer() {
        let (engine, trainer) = makeEngine()
        engine.trainerDifficulty = 0.5
        engine.step(dt: 0.1)
        // The engine sends the SMOOTHED gradient (what the rider feels).
        let expected = engine.route.smoothedGradient(atMeters: engine.distanceMeters) * 0.5
        XCTAssertEqual(trainer.receivedGrades.first ?? .nan, expected, accuracy: 0.05)
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

    func testRecordsOneSamplePerSimulatedSecond() {
        let (engine, _) = makeEngine()
        for _ in 0..<50 { // 5 simulated seconds
            engine.step(dt: 0.1)
        }
        XCTAssertEqual(engine.recorder.samples.count, 5)
        let sample = engine.recorder.samples[0]
        XCTAssertEqual(sample.powerWatts, 200)
        XCTAssertEqual(sample.cadenceRpm, 90)
        XCTAssertEqual(sample.heartRateBpm, 150)
    }

    func testRepublishesLiveTrainerMetricsForTheHUD() {
        let (engine, _) = makeEngine()
        engine.step(dt: 0.1)
        XCTAssertEqual(engine.powerWatts, 200)
        XCTAssertEqual(engine.cadenceRpm, 90)
        XCTAssertEqual(engine.heartRateBpm, 150)
    }

    func testCompletesWhenTargetDistanceReached() {
        let flat = Route(name: "Flat", points: [
            RoutePoint(distanceMeters: 0, elevationMeters: 0),
            RoutePoint(distanceMeters: 1000, elevationMeters: 0),
        ])
        let engine = RideEngine(route: flat)
        engine.start(
            dataSource: { FTMS.IndoorBikeData(powerWatts: 300) },
            control: nil,
            targetDistanceMeters: 100
        )
        engine.stop() // kill the timer; drive manually
        for _ in 0..<2000 where !engine.isCompleted {
            engine.step(dt: 0.1)
        }
        XCTAssertTrue(engine.isCompleted)
        XCTAssertFalse(engine.isRiding)
        XCTAssertGreaterThanOrEqual(engine.totalDistanceMeters, 100)
    }

    func testFreeRideNeverCompletes() {
        let (engine, _) = makeEngine()
        for _ in 0..<600 {
            engine.step(dt: 0.1)
        }
        XCTAssertFalse(engine.isCompleted)
        XCTAssertNil(engine.targetDistanceMeters)
    }

    func testElapsedClockTracksSimulatedTime() {
        let (engine, _) = makeEngine()
        for _ in 0..<300 { // 30 simulated seconds
            engine.step(dt: 0.1)
        }
        XCTAssertEqual(engine.elapsedSeconds, 30, accuracy: 0.001)
    }

    func testAutoPausesAtStandstillWithNoPower() {
        let engine = RideEngine(route: .island)
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 0) }, control: nil)
        engine.stop() // drive manually
        for _ in 0..<100 {
            engine.step(dt: 0.1)
        }
        XCTAssertTrue(engine.isAutoPaused)
        XCTAssertEqual(engine.elapsedSeconds, 0) // dead time not counted
        XCTAssertTrue(engine.recorder.samples.isEmpty)
    }

    func testDoesNotPauseWhileCoastingDownhill() {
        // 0 W but rolling: a downhill stretch keeps the rider moving without
        // power. The loop must close (equal start/end elevation) or the wrap
        // seam becomes a fake vertical wall.
        let descent = Route(name: "Descent", points: [
            RoutePoint(distanceMeters: 0, elevationMeters: 50),
            RoutePoint(distanceMeters: 1000, elevationMeters: 0),
            RoutePoint(distanceMeters: 2000, elevationMeters: 50),
        ])
        // Mutable power source: pedal for 5 s to get rolling, then coast.
        final class PowerBox { var watts = 150 }
        let box = PowerBox()
        let engine = RideEngine(route: descent)
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: box.watts) }, control: nil)
        engine.stop() // drive manually
        for step in 0..<600 {
            if step == 50 { box.watts = 0 }
            engine.step(dt: 0.1)
        }
        XCTAssertFalse(engine.isAutoPaused) // rolling downhill at 0 W ≠ paused
        XCTAssertGreaterThan(engine.elapsedSeconds, 50)
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

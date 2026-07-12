import XCTest
@testable import SkiftKit

private final class FakeTrainer: TrainerControlling {
    var receivedGrades: [Double] = []
    var receivedTargetPowers: [Int] = []
    func setGrade(percent: Double) {
        receivedGrades.append(percent)
    }
    func setTargetPower(watts: Int) {
        receivedTargetPowers.append(watts)
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

    // MARK: - ERG / workout mode

    /// Real `Timer.scheduledTimer` callbacks never fire during a synchronous
    /// XCTest method (nothing pumps the run loop), so — unlike the `makeEngine`
    /// helper above — these workout tests don't need a defensive `stop()`
    /// right after `start()`; doing so here would trigger the "send 0 W on
    /// stop" behavior before the test even begins driving `step(dt:)`.

    func testWorkoutModeNeverSendsGrade() {
        let workout = Workout(name: "W", steps: [
            WorkoutStep(label: "Only", targetWatts: 200, durationSeconds: 100),
        ])
        let engine = RideEngine(route: .island)
        let trainer = FakeTrainer()
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 200) }, control: trainer, mode: .workout(workout))

        for _ in 0..<300 { // 30 simulated seconds
            engine.step(dt: 0.1)
        }

        XCTAssertTrue(trainer.receivedGrades.isEmpty)
    }

    func testWorkoutModeSendsTargetPowerThrottledOnChange() {
        let workout = Workout(name: "W", steps: [
            WorkoutStep(label: "A", targetWatts: 150, durationSeconds: 2),
            WorkoutStep(label: "B", targetWatts: 250, durationSeconds: 2),
        ])
        let engine = RideEngine(route: .island)
        let trainer = FakeTrainer()
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 200) }, control: trainer, mode: .workout(workout))

        for _ in 0..<30 { // 3 simulated seconds: crosses the A→B boundary at t=2s, stays under total (4s)
            engine.step(dt: 0.1)
        }

        XCTAssertEqual(trainer.receivedTargetPowers, [150, 250])
    }

    func testWorkoutModeCompletesWhenTrackerFinishes() {
        let workout = Workout(name: "W", steps: [
            WorkoutStep(label: "Only", targetWatts: 200, durationSeconds: 2),
        ])
        let engine = RideEngine(route: .island)
        let trainer = FakeTrainer()
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 200) }, control: trainer, mode: .workout(workout))

        for _ in 0..<30 where !engine.isCompleted { // workout is 2 s long
            engine.step(dt: 0.1)
        }

        XCTAssertTrue(engine.isCompleted)
        XCTAssertFalse(engine.isRiding)
        XCTAssertEqual(trainer.receivedTargetPowers.last, 0) // stop() sends 0 W once
    }

    func testWorkoutModeAutoPauseFreezesWorkoutClock() {
        let workout = Workout(name: "W", steps: [
            WorkoutStep(label: "Only", targetWatts: 200, durationSeconds: 100),
        ])
        let engine = RideEngine(route: .island)
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 0) }, control: nil, mode: .workout(workout))

        for _ in 0..<50 { // 5 simulated seconds at 0 W / 0 speed → auto-paused throughout
            engine.step(dt: 0.1)
        }

        XCTAssertTrue(engine.isAutoPaused)
        XCTAssertEqual(engine.workoutState?.secondsLeftInStep, 100) // never counted down
    }

    func testWorkoutModeWithNilControlIsSafe() {
        let workout = Workout(name: "W", steps: [
            WorkoutStep(label: "Only", targetWatts: 200, durationSeconds: 2),
        ])
        let engine = RideEngine(route: .island)
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 200) }, control: nil, mode: .workout(workout))

        for _ in 0..<30 {
            engine.step(dt: 0.1)
        }

        XCTAssertTrue(engine.isCompleted)
    }

    func testStopInWorkoutModeSendsZeroWattsOnce() {
        let workout = Workout(name: "W", steps: [
            WorkoutStep(label: "Only", targetWatts: 200, durationSeconds: 100),
        ])
        let engine = RideEngine(route: .island)
        let trainer = FakeTrainer()
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 200) }, control: trainer, mode: .workout(workout))
        engine.step(dt: 0.1) // sends 200 W

        engine.stop()
        engine.stop() // idempotent: must not send a second 0 W

        XCTAssertEqual(trainer.receivedTargetPowers, [200, 0])
    }

    func testSimModeWorkoutStateStaysNil() {
        let (engine, _) = makeEngine()
        engine.step(dt: 0.1)
        XCTAssertNil(engine.workoutState)
    }

    func testWorkoutStateReflectsCurrentAndNextStep() {
        let workout = Workout(name: "W", steps: [
            WorkoutStep(label: "A", targetWatts: 150, durationSeconds: 2),
            WorkoutStep(label: "B", targetWatts: 250, durationSeconds: 2),
        ])
        let engine = RideEngine(route: .island)
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 200) }, control: nil, mode: .workout(workout))
        engine.step(dt: 0.1)

        XCTAssertEqual(engine.workoutState?.currentStep.label, "A")
        XCTAssertEqual(engine.workoutState?.nextStep?.label, "B")
    }

    func testSkipWorkoutStepAdvancesToNextStep() {
        let workout = Workout(name: "W", steps: [
            WorkoutStep(label: "A", targetWatts: 150, durationSeconds: 100),
            WorkoutStep(label: "B", targetWatts: 250, durationSeconds: 100),
        ])
        let engine = RideEngine(route: .island)
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 200) }, control: nil, mode: .workout(workout))
        engine.step(dt: 0.1) // rideClock = 0.1, inside step A

        engine.skipWorkoutStep()
        engine.step(dt: 0.1) // rideClock = 0.2

        XCTAssertEqual(engine.workoutState?.currentStep.label, "B")
    }

    func testAdjustWorkoutWattsBumpsReportedTarget() {
        let workout = Workout(name: "W", steps: [
            WorkoutStep(label: "A", targetWatts: 150, durationSeconds: 100),
        ])
        let engine = RideEngine(route: .island)
        engine.start(dataSource: { FTMS.IndoorBikeData(powerWatts: 200) }, control: nil, mode: .workout(workout))

        engine.adjustWorkoutWatts(by: 5)
        engine.step(dt: 0.1)

        XCTAssertEqual(engine.workoutState?.currentStep.targetWatts, 155)
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

import XCTest
@testable import SkiftKit

final class WorkoutTrackerTests: XCTestCase {

    private func makeWorkout() -> Workout {
        Workout(name: "Test", steps: [
            WorkoutStep(label: "Warmup", targetWatts: 100, durationSeconds: 60),
            WorkoutStep(label: "Work 1/1", targetWatts: 250, durationSeconds: 30),
            WorkoutStep(label: "Cooldown", targetWatts: 80, durationSeconds: 20),
        ])
    }

    // MARK: - Step lookup

    func testInitialStateAtElapsedZero() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        let state = tracker.state(atElapsed: 0)

        XCTAssertEqual(state.currentStepIndex, 0)
        XCTAssertEqual(state.currentStep.label, "Warmup")
        XCTAssertEqual(state.secondsLeftInStep, 60)
        XCTAssertEqual(state.nextStep?.label, "Work 1/1")
        XCTAssertFalse(state.isFinished)
    }

    func testMidStepReportsRemainingSeconds() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        let state = tracker.state(atElapsed: 40)

        XCTAssertEqual(state.currentStepIndex, 0)
        XCTAssertEqual(state.secondsLeftInStep, 20)
    }

    /// Exact boundary: elapsed == step end belongs to the NEXT step, not the
    /// one that just ended.
    func testExactStepBoundaryBelongsToNextStep() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        let state = tracker.state(atElapsed: 60)

        XCTAssertEqual(state.currentStepIndex, 1)
        XCTAssertEqual(state.currentStep.label, "Work 1/1")
        XCTAssertEqual(state.secondsLeftInStep, 30) // fresh, full duration of step 1
        XCTAssertEqual(state.nextStep?.label, "Cooldown")
    }

    func testLastStepBoundaryBelongsToFinished() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        // total duration = 60 + 30 + 20 = 110
        let state = tracker.state(atElapsed: 110)

        XCTAssertTrue(state.isFinished)
        XCTAssertNil(state.nextStep)
        XCTAssertEqual(state.secondsLeftInStep, 0)
    }

    func testWellPastTotalDurationStaysFinished() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        let state = tracker.state(atElapsed: 500)

        XCTAssertTrue(state.isFinished)
        XCTAssertEqual(state.currentStep.label, "Cooldown")
    }

    func testJustBeforeFinishIsNotFinished() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        let state = tracker.state(atElapsed: 109.999)

        XCTAssertFalse(state.isFinished)
        XCTAssertEqual(state.currentStepIndex, 2)
        XCTAssertEqual(state.secondsLeftInStep, 0.001, accuracy: 0.0001)
    }

    // MARK: - Skip

    func testSkipCurrentStepRebasesToStartOfNextStep() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        tracker.skipCurrentStep(atElapsed: 10) // 10 s into Warmup (60 s)

        let immediately = tracker.state(atElapsed: 10)
        XCTAssertEqual(immediately.currentStepIndex, 1)
        XCTAssertEqual(immediately.currentStep.label, "Work 1/1")
        XCTAssertEqual(immediately.secondsLeftInStep, 30) // full duration, just started

        let fiveSecondsLater = tracker.state(atElapsed: 15)
        XCTAssertEqual(fiveSecondsLater.secondsLeftInStep, 25)
    }

    func testSkipOnLastStepFinishesWorkoutImmediately() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        tracker.skipCurrentStep(atElapsed: 100) // inside Cooldown (90...110)

        let state = tracker.state(atElapsed: 100)
        XCTAssertTrue(state.isFinished)
    }

    func testMultipleSkipsAdvanceThroughEachStep() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        tracker.skipCurrentStep(atElapsed: 5) // out of Warmup
        tracker.skipCurrentStep(atElapsed: 5) // out of Work (same wall-clock instant)

        let state = tracker.state(atElapsed: 5)
        XCTAssertEqual(state.currentStep.label, "Cooldown")
        XCTAssertEqual(state.secondsLeftInStep, 20)
    }

    // MARK: - Watt adjustment

    func testAdjustWattsAppliesToCurrentAndNextStep() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        tracker.adjustWatts(by: 5)

        let state = tracker.state(atElapsed: 0)
        XCTAssertEqual(state.currentStep.targetWatts, 105)
        XCTAssertEqual(state.nextStep?.targetWatts, 255)
    }

    func testAdjustWattsAccumulatesAcrossCalls() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        tracker.adjustWatts(by: 5)
        tracker.adjustWatts(by: 5)

        let state = tracker.state(atElapsed: 0)
        XCTAssertEqual(state.currentStep.targetWatts, 110)
    }

    func testAdjustWattsClampsAtZero() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        tracker.adjustWatts(by: -1000)

        let state = tracker.state(atElapsed: 0)
        XCTAssertEqual(state.currentStep.targetWatts, 0)
        XCTAssertEqual(state.nextStep?.targetWatts, 0)
    }

    func testAdjustWattsSurvivesStepTransitions() {
        let tracker = WorkoutTracker(workout: makeWorkout())
        tracker.adjustWatts(by: 10)

        let afterBoundary = tracker.state(atElapsed: 60)
        XCTAssertEqual(afterBoundary.currentStep.targetWatts, 260) // 250 + 10
    }
}

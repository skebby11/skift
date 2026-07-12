import XCTest
@testable import SkiftKit

final class WorkoutTests: XCTestCase {

    // MARK: - Factory flattening

    func testIntervalsFlattensWarmupRepeatsAndCooldown() {
        let workout = Workout.intervals(
            name: "FTP repeats",
            warmup: (watts: 100, seconds: 300),
            repeats: 3,
            work: (watts: 250, seconds: 60),
            recovery: (watts: 120, seconds: 30),
            cooldown: (watts: 80, seconds: 300)
        )

        XCTAssertEqual(workout.steps.count, 8) // warmup + 3×(work+recovery) + cooldown
        XCTAssertEqual(workout.steps.map(\.label), [
            "Warmup",
            "Work 1/3", "Recovery 1/3",
            "Work 2/3", "Recovery 2/3",
            "Work 3/3", "Recovery 3/3",
            "Cooldown",
        ])
        XCTAssertEqual(workout.steps.map(\.targetWatts), [100, 250, 120, 250, 120, 250, 120, 80])
        XCTAssertEqual(workout.steps.map(\.durationSeconds), [300, 60, 30, 60, 30, 60, 30, 300])
    }

    func testZeroDurationWarmupAndCooldownAreSkipped() {
        let workout = Workout.intervals(
            name: "No warmup/cooldown",
            warmup: (watts: 100, seconds: 0),
            repeats: 2,
            work: (watts: 250, seconds: 60),
            recovery: (watts: 120, seconds: 30),
            cooldown: (watts: 80, seconds: 0)
        )

        XCTAssertEqual(workout.steps.map(\.label), [
            "Work 1/2", "Recovery 1/2",
            "Work 2/2", "Recovery 2/2",
        ])
    }

    func testZeroDurationRecoveryIsSkippedButLabelsKeepTotalCount() {
        // FTP-test style: no recovery between reps, but the label still
        // reflects the full repeat count, not a renumbered sequence.
        let workout = Workout.intervals(
            name: "No recovery",
            warmup: (watts: 100, seconds: 300),
            repeats: 3,
            work: (watts: 250, seconds: 60),
            recovery: (watts: 120, seconds: 0),
            cooldown: (watts: 80, seconds: 300)
        )

        XCTAssertEqual(workout.steps.map(\.label), [
            "Warmup", "Work 1/3", "Work 2/3", "Work 3/3", "Cooldown",
        ])
    }

    func testZeroRepeatsProducesOnlyWarmupAndCooldown() {
        let workout = Workout.intervals(
            name: "Empty",
            warmup: (watts: 100, seconds: 300),
            repeats: 0,
            work: (watts: 250, seconds: 60),
            recovery: (watts: 120, seconds: 30),
            cooldown: (watts: 80, seconds: 300)
        )

        XCTAssertEqual(workout.steps.map(\.label), ["Warmup", "Cooldown"])
    }

    // MARK: - Total duration

    func testTotalDurationSecondsSumsAllSteps() {
        let workout = Workout.intervals(
            name: "FTP repeats",
            warmup: (watts: 100, seconds: 300),
            repeats: 3,
            work: (watts: 250, seconds: 60),
            recovery: (watts: 120, seconds: 30),
            cooldown: (watts: 80, seconds: 300)
        )
        // 300 + 3*(60+30) + 300 = 870
        XCTAssertEqual(workout.totalDurationSeconds, 870)
    }

    func testTotalDurationSecondsOnEmptyStepsIsZero() {
        let workout = Workout(name: "Empty", steps: [])
        XCTAssertEqual(workout.totalDurationSeconds, 0)
    }

    // MARK: - Identity, Equatable, Codable

    func testDefaultInitAssignsUniqueIDs() {
        let a = Workout(name: "A", steps: [])
        let b = Workout(name: "A", steps: [])
        XCTAssertNotEqual(a.id, b.id)
        XCTAssertNotEqual(a, b)
    }

    func testWorkoutCodableRoundTrip() throws {
        let original = Workout.intervals(
            name: "FTP repeats",
            warmup: (watts: 100, seconds: 300),
            repeats: 2,
            work: (watts: 250, seconds: 60),
            recovery: (watts: 120, seconds: 30),
            cooldown: (watts: 80, seconds: 300)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Workout.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}

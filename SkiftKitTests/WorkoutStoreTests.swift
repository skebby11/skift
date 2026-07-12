import XCTest
@testable import SkiftKit

final class WorkoutStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: WorkoutStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkoutStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = WorkoutStore(directory: tempDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeWorkout(name: String) -> Workout {
        Workout.intervals(
            name: name,
            warmup: (watts: 100, seconds: 300),
            repeats: 3,
            work: (watts: 250, seconds: 60),
            recovery: (watts: 120, seconds: 30),
            cooldown: (watts: 80, seconds: 300)
        )
    }

    // MARK: - Save / list round trip

    func testSaveThenListRoundTripsWorkout() throws {
        let workout = makeWorkout(name: "FTP repeats")
        try store.save(workout)

        let listed = try store.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first, workout)
    }

    // MARK: - Ordering

    func testListOrdersByName() throws {
        try store.save(makeWorkout(name: "Zone 2"))
        try store.save(makeWorkout(name: "Anaerobic repeats"))
        try store.save(makeWorkout(name: "Mid-week intervals"))

        let listed = try store.list()
        XCTAssertEqual(listed.map(\.name), ["Anaerobic repeats", "Mid-week intervals", "Zone 2"])
    }

    // MARK: - Delete

    func testDeleteRemovesExactlyOneWorkout() throws {
        let a = makeWorkout(name: "A")
        let b = makeWorkout(name: "B")
        let c = makeWorkout(name: "C")
        try store.save(a)
        try store.save(b)
        try store.save(c)

        try store.delete(id: b.id)

        let listed = try store.list()
        XCTAssertEqual(Set(listed.map(\.id)), Set([a.id, c.id]))
    }

    func testDeleteUnknownIDThrowsWorkoutNotFound() throws {
        try store.save(makeWorkout(name: "A"))

        XCTAssertThrowsError(try store.delete(id: UUID())) { error in
            XCTAssertEqual(error as? WorkoutStoreError, .workoutNotFound)
        }
    }

    // MARK: - Corrupt files

    func testListSkipsCorruptFileButReturnsHealthyOnes() throws {
        let workout = makeWorkout(name: "Healthy")
        try store.save(workout)

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let corruptURL = tempDirectory.appendingPathComponent("corrupt-\(UUID().uuidString).json")
        try "not valid json {{{".write(to: corruptURL, atomically: true, encoding: .utf8)

        let listed = try store.list()
        XCTAssertEqual(listed.map(\.id), [workout.id])
    }

    // MARK: - Empty store

    func testListOnEmptyStoreReturnsEmptyArray() throws {
        XCTAssertEqual(try store.list(), [])
    }

    // MARK: - Overwrite

    func testSavingSameWorkoutIDTwiceOverwritesRatherThanDuplicates() throws {
        let workout = makeWorkout(name: "Original")
        try store.save(workout)

        let renamed = Workout(id: workout.id, name: "Renamed", steps: workout.steps)
        try store.save(renamed)

        let listed = try store.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.name, "Renamed")
    }
}

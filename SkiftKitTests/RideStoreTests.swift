import XCTest
@testable import SkiftKit

final class RideStoreTests: XCTestCase {

    private var tempDirectory: URL!
    private var store: RideStore!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RideStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = RideStore(directory: tempDirectory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeRecorder(startingAt seconds: TimeInterval = 1_750_000_000, sampleCount: Int = 5) -> RideRecorder {
        let recorder = RideRecorder()
        recorder.begin(at: Date(timeIntervalSince1970: seconds))
        for second in 0..<sampleCount {
            recorder.append(RideSample(
                timeOffset: TimeInterval(second),
                powerWatts: 200 + second,
                cadenceRpm: 90,
                heartRateBpm: 140,
                speedKmh: 30,
                distanceMeters: Double(second) * 8.33,
                elevationMeters: 10 + Double(second)
            ))
        }
        return recorder
    }

    // MARK: - Save / list round trip

    func testSaveThenListRoundTripsSummaryAndSamples() throws {
        let recorder = makeRecorder()
        let saved = try store.save(recorder: recorder)

        let listed = try store.list()
        XCTAssertEqual(listed.count, 1)
        let ride = try XCTUnwrap(listed.first)

        XCTAssertEqual(ride.id, saved.id)
        XCTAssertEqual(ride.startDate.timeIntervalSince1970, recorder.startDate!.timeIntervalSince1970, accuracy: 0.001)
        let summary = try XCTUnwrap(recorder.summary)
        XCTAssertEqual(ride.durationSeconds, summary.durationSeconds)
        XCTAssertEqual(ride.distanceMeters, summary.distanceMeters, accuracy: 0.001)
        XCTAssertEqual(ride.averagePowerWatts, summary.averagePowerWatts, accuracy: 0.001)
        XCTAssertEqual(ride.samples, recorder.samples)
    }

    // MARK: - Ordering

    func testListOrdersNewestFirst() throws {
        let older = makeRecorder(startingAt: 1_750_000_000)
        let middle = makeRecorder(startingAt: 1_750_001_000)
        let newest = makeRecorder(startingAt: 1_750_002_000)

        // Save out of order to prove list() sorts rather than relying on save order.
        try store.save(recorder: older)
        try store.save(recorder: newest)
        try store.save(recorder: middle)

        let listed = try store.list()
        XCTAssertEqual(
            listed.map { $0.startDate.timeIntervalSince1970 },
            [newest, middle, older].map { $0.startDate!.timeIntervalSince1970 }
        )
    }

    // MARK: - Delete

    func testDeleteRemovesExactlyOneRide() throws {
        let a = try store.save(recorder: makeRecorder(startingAt: 1_750_000_000))
        let b = try store.save(recorder: makeRecorder(startingAt: 1_750_001_000))
        let c = try store.save(recorder: makeRecorder(startingAt: 1_750_002_000))

        try store.delete(id: b.id)

        let listed = try store.list()
        XCTAssertEqual(Set(listed.map(\.id)), Set([a.id, c.id]))
    }

    // MARK: - Corrupt files

    func testListSkipsCorruptFileButReturnsHealthyOnes() throws {
        let saved = try store.save(recorder: makeRecorder())

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let corruptURL = tempDirectory.appendingPathComponent("corrupt-\(UUID().uuidString).json")
        try "not valid json {{{".write(to: corruptURL, atomically: true, encoding: .utf8)

        let listed = try store.list()
        XCTAssertEqual(listed.map(\.id), [saved.id])
    }

    // MARK: - Re-export parity

    func testReExportedStoredRideMatchesDirectExport() throws {
        let recorder = makeRecorder()
        let saved = try store.save(recorder: recorder)

        // Rebuild a recorder from the stored samples the way HistoryView will
        // when re-exporting — must produce byte-identical TCX.
        let rebuilt = RideRecorder()
        rebuilt.begin(at: saved.startDate)
        saved.samples.forEach(rebuilt.append)

        let directTCX = try XCTUnwrap(TCXExporter.export(recorder: recorder))
        let reExportedTCX = try XCTUnwrap(TCXExporter.export(recorder: rebuilt))
        XCTAssertEqual(reExportedTCX, directTCX)
    }

    // MARK: - Empty store

    func testListOnEmptyStoreReturnsEmptyArray() throws {
        XCTAssertEqual(try store.list(), [])
    }

    // MARK: - Strava activity id

    func testNewlySavedRideHasNoStravaActivityID() throws {
        let saved = try store.save(recorder: makeRecorder())
        XCTAssertNil(saved.stravaActivityID)

        let listed = try store.list()
        XCTAssertNil(listed.first?.stravaActivityID)
    }

    func testMarkUploadedPersistsActivityID() throws {
        let saved = try store.save(recorder: makeRecorder())

        try store.markUploaded(id: saved.id, activityID: 998_877)

        let listed = try store.list()
        let ride = try XCTUnwrap(listed.first { $0.id == saved.id })
        XCTAssertEqual(ride.stravaActivityID, 998_877)
    }

    func testMarkUploadedOnUnknownIDThrowsRideNotFound() throws {
        _ = try store.save(recorder: makeRecorder())

        XCTAssertThrowsError(try store.markUploaded(id: UUID(), activityID: 1)) { error in
            XCTAssertEqual(error as? RideStoreError, .rideNotFound)
        }
    }

    // MARK: - Backward compatibility (JSON written before stravaActivityID existed)

    func testListDecodesOldJSONWithoutStravaActivityIDKey() throws {
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let oldJSON = """
        {
          "id": "8C7C2B7A-4B1B-4F7A-9C2A-000000000001",
          "startDate": "2025-06-15T12:00:00Z",
          "durationSeconds": 5,
          "distanceMeters": 41.65,
          "averagePowerWatts": 202,
          "samples": []
        }
        """
        let url = tempDirectory.appendingPathComponent("old-ride.json")
        try oldJSON.write(to: url, atomically: true, encoding: .utf8)

        let listed = try store.list()
        XCTAssertEqual(listed.count, 1)
        XCTAssertNil(listed.first?.stravaActivityID)
    }
}

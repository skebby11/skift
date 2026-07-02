import XCTest
@testable import SkiftKit

final class RideRecorderTests: XCTestCase {

    private func makeRecorder() -> RideRecorder {
        let recorder = RideRecorder()
        recorder.begin(at: Date(timeIntervalSince1970: 1_750_000_000))
        // 10 minutes at steady 200 W / 90 rpm, climbing 1 m every 2 s for the
        // first half, then descending back (gain must only count the ups).
        for second in 0...600 {
            let elevation = second <= 300 ? 10.0 + Double(second) / 2 : 160.0 - Double(second - 300) / 2
            recorder.append(RideSample(
                timeOffset: TimeInterval(second),
                powerWatts: 200,
                cadenceRpm: 90,
                heartRateBpm: 150,
                speedKmh: 30,
                distanceMeters: Double(second) * 8.33,
                elevationMeters: elevation
            ))
        }
        return recorder
    }

    func testSummaryStats() throws {
        let summary = try XCTUnwrap(makeRecorder().summary)
        XCTAssertEqual(summary.durationSeconds, 600)
        XCTAssertEqual(summary.distanceMeters, 600 * 8.33, accuracy: 0.5)
        XCTAssertEqual(summary.averagePowerWatts, 200, accuracy: 0.001)
        XCTAssertEqual(summary.maxPowerWatts, 200)
        XCTAssertEqual(summary.averageCadenceRpm ?? 0, 90, accuracy: 0.001)
        XCTAssertEqual(summary.averageHeartRateBpm ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(summary.elevationGainMeters, 150, accuracy: 0.01)
        // 200 W × 600 s = 120 kJ
        XCTAssertEqual(summary.energyKilojoules, 120, accuracy: 0.5)
    }

    func testSummaryNeedsAtLeastTwoSamples() {
        let recorder = RideRecorder()
        recorder.begin()
        XCTAssertNil(recorder.summary)
        recorder.append(RideSample(
            timeOffset: 0, powerWatts: 100, cadenceRpm: nil, heartRateBpm: nil,
            speedKmh: 20, distanceMeters: 0, elevationMeters: 10
        ))
        XCTAssertNil(recorder.summary)
    }

    func testBeginDiscardsPreviousRecording() {
        let recorder = makeRecorder()
        recorder.begin()
        XCTAssertTrue(recorder.samples.isEmpty)
    }
}

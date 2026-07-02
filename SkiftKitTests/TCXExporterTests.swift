import XCTest
@testable import SkiftKit

final class TCXExporterTests: XCTestCase {

    private func makeRecorder() -> RideRecorder {
        let recorder = RideRecorder()
        recorder.begin(at: Date(timeIntervalSince1970: 1_750_000_000))
        for second in [0, 1, 2] {
            recorder.append(RideSample(
                timeOffset: TimeInterval(second),
                powerWatts: 250,
                cadenceRpm: 88,
                heartRateBpm: 142,
                speedKmh: 36,
                distanceMeters: Double(second) * 10,
                elevationMeters: 12.5
            ))
        }
        return recorder
    }

    func testExportsWellFormedXMLWithExpectedFields() throws {
        let tcx = try XCTUnwrap(TCXExporter.export(recorder: makeRecorder()))

        // Well-formed XML (XMLDocument throws on syntax errors).
        XCTAssertNoThrow(try XMLDocument(xmlString: tcx))

        XCTAssertTrue(tcx.contains(#"<Activity Sport="Biking">"#))
        XCTAssertTrue(tcx.contains("<TotalTimeSeconds>2.00</TotalTimeSeconds>"))
        XCTAssertTrue(tcx.contains("<DistanceMeters>20.00</DistanceMeters>"))
        XCTAssertTrue(tcx.contains("<Cadence>88</Cadence>"))
        XCTAssertTrue(tcx.contains("<HeartRateBpm><Value>142</Value></HeartRateBpm>"))
        XCTAssertTrue(tcx.contains("<ns3:Watts>250</ns3:Watts>"))
        // 36 km/h = 10 m/s
        XCTAssertTrue(tcx.contains("<ns3:Speed>10.00</ns3:Speed>"))
        XCTAssertEqual(tcx.components(separatedBy: "<Trackpoint>").count - 1, 3)
    }

    func testEmptyRecordingExportsNothing() {
        let recorder = RideRecorder()
        recorder.begin()
        XCTAssertNil(TCXExporter.export(recorder: recorder))
    }
}

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

    // MARK: - Namespace-aware helpers

    private static let tcxNamespace = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
    private static let extensionNamespace = "http://www.garmin.com/xmlschemas/ActivityExtension/v2"

    /// All `<Trackpoint>` elements in document order, regardless of namespace prefix.
    private func trackpoints(in doc: XMLDocument) throws -> [XMLElement] {
        let nodes = try doc.nodes(forXPath: "//*[local-name()='Trackpoint']")
        return nodes.compactMap { $0 as? XMLElement }
    }

    /// All elements anywhere in the document matching a local name, regardless of namespace prefix.
    private func elements(in doc: XMLDocument, localName: String) throws -> [XMLElement] {
        let nodes = try doc.nodes(forXPath: "//*[local-name()='\(localName)']")
        return nodes.compactMap { $0 as? XMLElement }
    }

    // MARK: - Nil-field omission

    func testNilCadenceAndHeartRateOmitElementsPerTrackpoint() throws {
        let recorder = RideRecorder()
        recorder.begin(at: Date(timeIntervalSince1970: 1_750_000_000))
        // Neither cadence nor heart rate.
        recorder.append(RideSample(
            timeOffset: 0, powerWatts: 200, cadenceRpm: nil, heartRateBpm: nil,
            speedKmh: 30, distanceMeters: 0, elevationMeters: 10
        ))
        // Cadence only.
        recorder.append(RideSample(
            timeOffset: 1, powerWatts: 210, cadenceRpm: 80, heartRateBpm: nil,
            speedKmh: 31, distanceMeters: 8, elevationMeters: 10
        ))
        // Heart rate only.
        recorder.append(RideSample(
            timeOffset: 2, powerWatts: 220, cadenceRpm: nil, heartRateBpm: 140,
            speedKmh: 32, distanceMeters: 17, elevationMeters: 10
        ))

        let tcx = try XCTUnwrap(TCXExporter.export(recorder: recorder))
        let doc = try XMLDocument(xmlString: tcx)
        let points = try trackpoints(in: doc)
        XCTAssertEqual(points.count, 3)

        XCTAssertTrue(points[0].elements(forName: "Cadence").isEmpty)
        XCTAssertTrue(points[0].elements(forName: "HeartRateBpm").isEmpty)

        XCTAssertEqual(points[1].elements(forName: "Cadence").first?.stringValue, "80")
        XCTAssertTrue(points[1].elements(forName: "HeartRateBpm").isEmpty)

        XCTAssertTrue(points[2].elements(forName: "Cadence").isEmpty)
        XCTAssertEqual(
            points[2].elements(forName: "HeartRateBpm").first?.elements(forName: "Value").first?.stringValue,
            "140"
        )
    }

    // MARK: - Timestamp format

    func testTimestampsAreStrictISO8601UTCAndMonotonic() throws {
        let recorder = makeRecorder()
        let tcx = try XCTUnwrap(TCXExporter.export(recorder: recorder))
        let doc = try XMLDocument(xmlString: tcx)

        let iso8601Regex = try NSRegularExpression(
            pattern: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$"#
        )
        func matches(_ string: String) -> Bool {
            iso8601Regex.firstMatch(in: string, range: NSRange(string.startIndex..., in: string)) != nil
        }

        let idText = try XCTUnwrap(elements(in: doc, localName: "Id").first?.stringValue)
        XCTAssertTrue(matches(idText), "Id \(idText) is not strict ISO8601 UTC")

        let timeTexts = try elements(in: doc, localName: "Time").compactMap(\.stringValue)
        XCTAssertEqual(timeTexts.count, 3)
        for time in timeTexts {
            XCTAssertTrue(matches(time), "Time \(time) is not strict ISO8601 UTC")
        }

        // Trackpoint times must increase monotonically (strictly, since
        // samples are one simulated second apart).
        let formatter = ISO8601DateFormatter()
        let dates = timeTexts.map { formatter.date(from: $0)! }
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertEqual(Set(dates).count, dates.count, "trackpoint times must be strictly increasing")
    }

    // MARK: - Schema shape

    func testRootNamespaceIsTCXv2() throws {
        let tcx = try XCTUnwrap(TCXExporter.export(recorder: makeRecorder()))
        let doc = try XMLDocument(xmlString: tcx)
        let root = try XCTUnwrap(doc.rootElement())
        XCTAssertEqual(root.name, "TrainingCenterDatabase")
        XCTAssertEqual(root.uri, Self.tcxNamespace)
    }

    func testPowerExtensionUsesActivityExtensionNamespace() throws {
        let tcx = try XCTUnwrap(TCXExporter.export(recorder: makeRecorder()))
        let doc = try XMLDocument(xmlString: tcx)
        let wattsElements = try elements(in: doc, localName: "Watts")
        XCTAssertEqual(wattsElements.count, 3)
        for watts in wattsElements {
            XCTAssertEqual(watts.uri, Self.extensionNamespace)
        }
    }

    func testActivitySportAttributeIsBiking() throws {
        let tcx = try XCTUnwrap(TCXExporter.export(recorder: makeRecorder()))
        let doc = try XMLDocument(xmlString: tcx)
        let activity = try XCTUnwrap(elements(in: doc, localName: "Activity").first)
        XCTAssertEqual(activity.attribute(forName: "Sport")?.stringValue, "Biking")
    }

    /// TCX's Trackpoint_t sequence is Time, Position?, AltitudeMeters?,
    /// DistanceMeters?, HeartRateBpm?, Cadence?, SensorState?, Extensions? —
    /// HeartRateBpm comes before Cadence. Every trackpoint's child elements
    /// that are present must appear in that relative order.
    func testTrackpointChildElementOrderFollowsTCXSequence() throws {
        let recorder = RideRecorder()
        recorder.begin(at: Date(timeIntervalSince1970: 1_750_000_000))
        recorder.append(RideSample(
            timeOffset: 0, powerWatts: 200, cadenceRpm: 85, heartRateBpm: 140,
            speedKmh: 30, distanceMeters: 0, elevationMeters: 10
        ))
        recorder.append(RideSample(
            timeOffset: 1, powerWatts: 210, cadenceRpm: 86, heartRateBpm: 141,
            speedKmh: 31, distanceMeters: 8, elevationMeters: 11
        ))
        let tcx = try XCTUnwrap(TCXExporter.export(recorder: recorder))
        let doc = try XMLDocument(xmlString: tcx)
        let points = try trackpoints(in: doc)
        XCTAssertFalse(points.isEmpty)

        let schemaOrder = ["Time", "AltitudeMeters", "DistanceMeters", "HeartRateBpm", "Cadence", "Extensions"]
        for point in points {
            let childNames = (point.children ?? []).compactMap { $0.name }
            let relevant = childNames.filter { schemaOrder.contains($0) }
            let expectedOrder = schemaOrder.filter { relevant.contains($0) }
            XCTAssertEqual(relevant, expectedOrder, "Trackpoint children \(relevant) violate TCX element order")
        }
    }

    // MARK: - Mixed recording fixture

    func testMixedRecordingExportsPerTrackpointCorrectness() throws {
        let recorder = RideRecorder()
        recorder.begin(at: Date(timeIntervalSince1970: 1_750_000_000))
        // Full data.
        recorder.append(RideSample(
            timeOffset: 0, powerWatts: 180, cadenceRpm: 78, heartRateBpm: 130,
            speedKmh: 25.2, distanceMeters: 0, elevationMeters: 5
        ))
        // No power, no cadence, no heart rate — only speed/distance/elevation.
        recorder.append(RideSample(
            timeOffset: 1, powerWatts: nil, cadenceRpm: nil, heartRateBpm: nil,
            speedKmh: 0, distanceMeters: 7, elevationMeters: 5.2
        ))
        // Full data again, different values.
        recorder.append(RideSample(
            timeOffset: 2, powerWatts: 260, cadenceRpm: 95, heartRateBpm: 155,
            speedKmh: 34.8, distanceMeters: 16.5, elevationMeters: 6
        ))

        let tcx = try XCTUnwrap(TCXExporter.export(recorder: recorder))
        let doc = try XMLDocument(xmlString: tcx)
        let points = try trackpoints(in: doc)
        XCTAssertEqual(points.count, 3)

        // Trackpoint 0: full data.
        XCTAssertEqual(points[0].elements(forName: "Cadence").first?.stringValue, "78")
        XCTAssertEqual(
            points[0].elements(forName: "HeartRateBpm").first?.elements(forName: "Value").first?.stringValue,
            "130"
        )
        let watts0 = try elements(in: doc, localName: "Watts")
        XCTAssertEqual(watts0[0].stringValue, "180")

        // Trackpoint 1: everything optional is absent.
        XCTAssertTrue(points[1].elements(forName: "Cadence").isEmpty)
        XCTAssertTrue(points[1].elements(forName: "HeartRateBpm").isEmpty)
        XCTAssertTrue((try elements(in: doc, localName: "TPX"))[1].elements(forName: "Watts").isEmpty)

        // Trackpoint 2: full data again.
        XCTAssertEqual(points[2].elements(forName: "Cadence").first?.stringValue, "95")
        XCTAssertEqual(
            points[2].elements(forName: "HeartRateBpm").first?.elements(forName: "Value").first?.stringValue,
            "155"
        )
        XCTAssertEqual(watts0[1].stringValue, "260")
    }
}

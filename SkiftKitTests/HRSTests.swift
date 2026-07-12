import XCTest
@testable import SkiftKit

final class HRSTests: XCTestCase {

    // MARK: - Assigned numbers

    func testAssignedUUIDs() {
        XCTAssertEqual(HRS.serviceUUID, "180D")
        XCTAssertEqual(HRS.measurementUUID, "2A37")
    }

    // MARK: - Heart Rate Measurement (0x2A37) parsing

    func testParsesUInt8Format() {
        // flags 0x00: bit 0 clear → bpm is a single uint8 byte.
        let payload = Data([0x00, 0x4B]) // 75 bpm
        XCTAssertEqual(HRS.parseHeartRateMeasurement(payload), 75)
    }

    func testParsesUInt16Format() {
        // flags 0x01: bit 0 set → bpm is a uint16 LE value.
        let payload = Data([0x01, 0x90, 0x00]) // 144 bpm
        XCTAssertEqual(HRS.parseHeartRateMeasurement(payload), 144)
    }

    func testParsesWithEnergyExpended() {
        // flags 0x08: bit 3 set → 2 bytes of energy expended follow (skipped).
        let payload = Data([0x08, 0x4B, 0x10, 0x00]) // 75 bpm, energy skipped
        XCTAssertEqual(HRS.parseHeartRateMeasurement(payload), 75)
    }

    func testParsesWithRRIntervals() {
        // flags 0x10: bit 4 set → one or more uint16 RR intervals follow (skipped).
        let payload = Data([0x10, 0x4B, 0xE8, 0x03]) // 75 bpm, one RR interval skipped
        XCTAssertEqual(HRS.parseHeartRateMeasurement(payload), 75)
    }

    func testParsesWithMultipleRRIntervals() {
        // Two RR intervals present — all trailing bytes must be consumed, not
        // just the first two.
        let payload = Data([0x10, 0x4B, 0xE8, 0x03, 0xD0, 0x02])
        XCTAssertEqual(HRS.parseHeartRateMeasurement(payload), 75)
    }

    func testParsesWithEverything() {
        // flags 0x1F: uint16 bpm (bit 0) + sensor contact bits (1-2, ignored)
        // + energy expended (bit 3) + RR intervals (bit 4).
        let payload = Data([
            0x1F,
            0x8A, 0x00, // bpm: 138
            0x64, 0x00, // energy expended (skipped)
            0xE8, 0x03, // RR interval 1 (skipped)
            0xD0, 0x02, // RR interval 2 (skipped)
        ])
        XCTAssertEqual(HRS.parseHeartRateMeasurement(payload), 138)
    }

    func testSensorContactBitsAreIgnored() {
        // flags 0x06: sensor contact bits (1-2) set, everything else clear.
        let payload = Data([0x06, 0x4B])
        XCTAssertEqual(HRS.parseHeartRateMeasurement(payload), 75)
    }

    func testEmptyPayloadReturnsNil() {
        XCTAssertNil(HRS.parseHeartRateMeasurement(Data()))
    }

    func testUInt16FormatWithOnlyOneByteReturnsNil() {
        // Flags promise a uint16 bpm but only one byte follows.
        XCTAssertNil(HRS.parseHeartRateMeasurement(Data([0x01, 0x4B])))
    }

    func testUInt8FormatWithNoBpmByteReturnsNil() {
        XCTAssertNil(HRS.parseHeartRateMeasurement(Data([0x00])))
    }

    func testEnergyExpendedFlagWithoutEnoughBytesReturnsNil() {
        // flags 0x08 promises 2 bytes of energy expended after bpm; only 1 given.
        XCTAssertNil(HRS.parseHeartRateMeasurement(Data([0x08, 0x4B, 0x10])))
    }
}

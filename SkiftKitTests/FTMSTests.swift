import XCTest
@testable import SkiftKit

final class FTMSTests: XCTestCase {

    // MARK: - Indoor Bike Data parsing

    func testParsesSpeedCadenceAndPower() {
        // flags 0x0044: speed present (bit 0 clear), cadence (bit 2), power (bit 6)
        let payload = Data([
            0x44, 0x00,
            0xC4, 0x09, // 2500 → 25.00 km/h
            0xB4, 0x00, // 180 → 90.0 rpm
            0xFA, 0x00, // 250 W
        ])
        let parsed = FTMS.parseIndoorBikeData(payload)
        XCTAssertEqual(parsed, FTMS.IndoorBikeData(speedKmh: 25.0, cadenceRpm: 90.0, powerWatts: 250))
    }

    func testParsesPowerAndHeartRateWithoutSpeed() {
        // flags 0x0241: More Data set (no speed), power (bit 6), heart rate (bit 9)
        let payload = Data([
            0x41, 0x02,
            0xC8, 0x00, // 200 W
            0x96,       // 150 bpm
        ])
        let parsed = FTMS.parseIndoorBikeData(payload)
        XCTAssertEqual(parsed, FTMS.IndoorBikeData(powerWatts: 200, heartRateBpm: 150))
        XCTAssertNil(parsed?.speedKmh)
    }

    func testParsesNegativePower() {
        // flags 0x0041: no speed, power only
        let payload = Data([0x41, 0x00, 0xFE, 0xFF]) // -2 W
        XCTAssertEqual(FTMS.parseIndoorBikeData(payload)?.powerWatts, -2)
    }

    func testSkipsUnusedFieldsToReachLaterOnes() {
        // flags 0x0853: More Data set (no instantaneous speed), average speed
        // (0x02), total distance (0x10), power (0x40), elapsed time (0x800)
        let payload = Data([
            0x53, 0x08,
            0x10, 0x27,       // average speed (skipped)
            0xE8, 0x03, 0x00, // 1000 m total distance
            0x2C, 0x01,       // 300 W
            0x3C, 0x00,       // 60 s elapsed
        ])
        let parsed = FTMS.parseIndoorBikeData(payload)
        XCTAssertEqual(parsed?.totalDistanceMeters, 1000)
        XCTAssertEqual(parsed?.powerWatts, 300)
        XCTAssertEqual(parsed?.elapsedTimeSeconds, 60)
        XCTAssertNil(parsed?.speedKmh)
    }

    func testTruncatedPayloadReturnsNil() {
        // Flags promise speed but only one byte of it follows.
        XCTAssertNil(FTMS.parseIndoorBikeData(Data([0x44, 0x00, 0xC4])))
        XCTAssertNil(FTMS.parseIndoorBikeData(Data([0x44])))
        XCTAssertNil(FTMS.parseIndoorBikeData(Data()))
    }

    // MARK: - Simulation parameters encoding

    func testEncodesClimbSimulation() {
        let command = FTMS.setIndoorBikeSimulation(gradePercent: 5.5)
        XCTAssertEqual(command, Data([
            0x11,
            0x00, 0x00, // wind 0 m/s
            0x26, 0x02, // 550 → 5.50%
            0x28,       // Crr 0.004
            0x33,       // Cw 0.51 kg/m
        ]))
    }

    func testEncodesDescentWithNegativeGrade() {
        let command = FTMS.setIndoorBikeSimulation(gradePercent: -3.0)
        XCTAssertEqual(command[3...4], Data([0xD4, 0xFE])) // -300 → 0xFED4 LE
    }

    func testClampsOutOfRangeValues() {
        let command = FTMS.setIndoorBikeSimulation(gradePercent: 0, crr: 1.0, windResistanceKgM: 99)
        XCTAssertEqual(command[5], 0xFF) // Crr clamped to UInt8 max
        XCTAssertEqual(command[6], 0xFF) // Cw clamped to UInt8 max
    }

    // MARK: - Control Point responses

    func testParsesSuccessResponse() {
        let response = FTMS.parseControlPointResponse(Data([0x80, 0x00, 0x01]))
        XCTAssertEqual(response?.requestOpCode, FTMS.OpCode.requestControl.rawValue)
        XCTAssertEqual(response?.result, .success)
    }

    func testParsesFailureResponse() {
        let response = FTMS.parseControlPointResponse(Data([0x80, 0x11, 0x05]))
        XCTAssertEqual(response?.requestOpCode, FTMS.OpCode.setIndoorBikeSimulation.rawValue)
        XCTAssertEqual(response?.result, .controlNotPermitted)
    }

    func testRejectsNonResponsePayloads() {
        XCTAssertNil(FTMS.parseControlPointResponse(Data([0x00, 0x00, 0x01])))
        XCTAssertNil(FTMS.parseControlPointResponse(Data([0x80, 0x00])))
    }
}

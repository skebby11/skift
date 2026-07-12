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

    // MARK: - Realistic trainer fixtures

    /// "Wahoo KICKR-style": flags 0x0244 = speed present (bit 0 clear),
    /// instantaneous cadence (bit 2), instantaneous power (bit 6),
    /// heart rate (bit 9). No distance/elapsed time in this notification.
    func testWahooKICKRStyleFixture() {
        let payload = Data([
            0x44, 0x02,       // flags
            0xA8, 0x0C,       // speed: 3240 → 32.40 km/h
            0xAB, 0x00,       // cadence: 171 × 0.5 → 85.5 rpm
            0xD2, 0x00,       // power: 210 W
            0x8A,             // heart rate: 138 bpm
        ])
        let parsed = FTMS.parseIndoorBikeData(payload)
        XCTAssertEqual(parsed, FTMS.IndoorBikeData(
            speedKmh: 32.4,
            cadenceRpm: 85.5,
            powerWatts: 210,
            heartRateBpm: 138,
            totalDistanceMeters: nil,
            elapsedTimeSeconds: nil
        ))
    }

    /// "Tacx-style": flags 0x0854 = speed present (bit 0 clear), instantaneous
    /// cadence (bit 2), total distance uint24 (bit 4), instantaneous power
    /// (bit 6), elapsed time (bit 11). No heart rate in this notification.
    func testTacxStyleFixture() {
        let payload = Data([
            0x54, 0x08,       // flags
            0x2C, 0x0B,       // speed: 2860 → 28.60 km/h
            0x90, 0x00,       // cadence: 144 × 0.5 → 72.0 rpm
            0x82, 0x3B, 0x00, // total distance: 15234 m
            0xC3, 0x00,       // power: 195 W
            0x10, 0x0E,       // elapsed time: 3600 s
        ])
        let parsed = FTMS.parseIndoorBikeData(payload)
        XCTAssertEqual(parsed, FTMS.IndoorBikeData(
            speedKmh: 28.6,
            cadenceRpm: 72.0,
            powerWatts: 195,
            heartRateBpm: nil,
            totalDistanceMeters: 15234,
            elapsedTimeSeconds: 3600
        ))
    }

    /// Minimal "power only" fixture: bit 0 SET (More Data — no speed),
    /// bit 6 (instantaneous power). No cadence, heart rate, distance, or time.
    func testPowerOnlyFixture() {
        let payload = Data([
            0x41, 0x00, // flags: bit 0 set (no speed) + bit 6 (power)
            0x2C, 0x01, // power: 300 W
        ])
        let parsed = FTMS.parseIndoorBikeData(payload)
        XCTAssertEqual(parsed, FTMS.IndoorBikeData(
            speedKmh: nil,
            cadenceRpm: nil,
            powerWatts: 300,
            heartRateBpm: nil,
            totalDistanceMeters: nil,
            elapsedTimeSeconds: nil
        ))
    }

    // MARK: - All-known-flags payload and truncation sweep

    /// Every flag bit the spec defines for this characteristic (bits 1..11)
    /// is set, with bit 0 clear so speed is present too. This exercises every
    /// skip branch (average speed/cadence/power, resistance level, expended
    /// energy, metabolic equivalent) alongside every field we surface.
    /// Total length: 2 (flags) + 26 (fields) = 28 bytes.
    private static let allFlagsPayload = Data([
        0xFE, 0x0F,             // flags: bits 1..11 set, bit 0 clear
        0xA0, 0x0F,             // speed: 4000 → 40.00 km/h
        0xAA, 0xAA,             // average speed (skipped, 2 bytes)
        0xBF, 0x00,             // cadence: 191 × 0.5 → 95.5 rpm
        0xAA, 0xAA,             // average cadence (skipped, 2 bytes)
        0x39, 0x30, 0x00,       // total distance: 12345 m (uint24)
        0xAA, 0xAA,             // resistance level (skipped, 2 bytes)
        0x13, 0x01,             // power: 275 W
        0xAA, 0xAA,             // average power (skipped, 2 bytes)
        0xAA, 0xAA, 0xAA, 0xAA, 0xAA, // expended energy (skipped, 5 bytes)
        0x96,                   // heart rate: 150 bpm
        0xAA,                   // metabolic equivalent (skipped, 1 byte)
        0x94, 0x11,             // elapsed time: 4500 s
    ])

    func testAllKnownFlagsPayloadParsesEveryField() {
        let parsed = FTMS.parseIndoorBikeData(Self.allFlagsPayload)
        XCTAssertEqual(parsed, FTMS.IndoorBikeData(
            speedKmh: 40.0,
            cadenceRpm: 95.5,
            powerWatts: 275,
            heartRateBpm: 150,
            totalDistanceMeters: 12345,
            elapsedTimeSeconds: 4500
        ))
    }

    /// Every truncation length from just after the flags field up to
    /// full-length-minus-one must fail to parse: any field promised by the
    /// flags but missing its bytes should be rejected, not silently dropped.
    func testAllKnownFlagsPayloadTruncationSweep() {
        let full = Self.allFlagsPayload
        for length in 2..<full.count {
            let truncated = full.prefix(length)
            XCTAssertNil(
                FTMS.parseIndoorBikeData(truncated),
                "expected nil at truncated length \(length) (full length \(full.count))"
            )
        }
    }

    /// FTMS 1.0 also defines bit 12 (Remaining Time, uint16) which this app
    /// doesn't surface. A payload that sets bit 12 and carries two trailing
    /// bytes for it must still parse the fields we do care about — unknown
    /// trailing bytes are tolerated, not treated as corruption.
    func testTrailingExtraBytesForUnsupportedFlagAreTolerated() {
        let payload = Data([
            0x41, 0x10, // flags: bit 0 (no speed) + bit 6 (power) + bit 12 (remaining time)
            0xDC, 0x00, // power: 220 W
            0x2C, 0x01, // remaining time: 300 s (unsurfaced, must not break parsing)
        ])
        let parsed = FTMS.parseIndoorBikeData(payload)
        XCTAssertEqual(parsed, FTMS.IndoorBikeData(powerWatts: 220))
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

    // MARK: - Set Target Power encoding

    func testEncodesSetTargetPower() {
        let command = FTMS.setTargetPower(watts: 220)
        XCTAssertEqual(command, Data([0x05, 0xDC, 0x00])) // 220 → 0x00DC LE
    }

    func testSetTargetPowerClampsToUpperBound() {
        let command = FTMS.setTargetPower(watts: 5000)
        XCTAssertEqual(command, Data([0x05, 0xD0, 0x07])) // clamped to 2000 → 0x07D0 LE
    }

    func testSetTargetPowerClampsToLowerBound() {
        let command = FTMS.setTargetPower(watts: -500)
        XCTAssertEqual(command, Data([0x05, 0x00, 0x00])) // clamped to 0
    }

    func testSetTargetPowerRejectsNegativeInputButDoesNotUnderflow() {
        let command = FTMS.setTargetPower(watts: -1)
        XCTAssertEqual(command, Data([0x05, 0x00, 0x00]))
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

    func testParsesAllFailureResultsForSetIndoorBikeSimulation() {
        let cases: [(UInt8, FTMS.ControlPointResponse.Result)] = [
            (0x02, .notSupported),
            (0x03, .invalidParameter),
            (0x04, .operationFailed),
            (0x05, .controlNotPermitted),
        ]
        for (resultByte, expected) in cases {
            let response = FTMS.parseControlPointResponse(Data([
                0x80, FTMS.OpCode.setIndoorBikeSimulation.rawValue, resultByte,
            ]))
            XCTAssertEqual(response?.requestOpCode, FTMS.OpCode.setIndoorBikeSimulation.rawValue)
            XCTAssertEqual(response?.result, expected)
        }
    }

    func testParsesUnknownRequestOpCodeWithoutRejecting() {
        // requestOpCode is a raw UInt8, not validated against known OpCodes —
        // the trainer is the source of truth, not our enum.
        let response = FTMS.parseControlPointResponse(Data([0x80, 0x99, 0x01]))
        XCTAssertEqual(response?.requestOpCode, 0x99)
        XCTAssertEqual(response?.result, .success)
    }

    func testUnknownResultCodeYieldsNilResultButKeepsOpCode() {
        let response = FTMS.parseControlPointResponse(Data([0x80, 0x00, 0xEE]))
        XCTAssertEqual(response?.requestOpCode, FTMS.OpCode.requestControl.rawValue)
        XCTAssertNil(response?.result)
    }

    func testZeroLengthAndShortControlPointResponsesReturnNil() {
        XCTAssertNil(FTMS.parseControlPointResponse(Data()))
        XCTAssertNil(FTMS.parseControlPointResponse(Data([0x80])))
        XCTAssertNil(FTMS.parseControlPointResponse(Data([0x80, 0x00])))
    }
}

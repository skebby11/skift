import Foundation

/// Pure encoding/decoding for the Bluetooth Fitness Machine Service (FTMS),
/// the Bluetooth SIG standard implemented by modern smart trainers.
/// No CoreBluetooth dependency, so everything here is unit-testable.
///
/// Payload layouts follow the FTMS 1.0 specification. All multi-byte fields
/// are little-endian, per Bluetooth convention.
///
/// REVIEW: field layouts are spec-correct, but real trainers differ in WHICH
/// optional fields they include — verify against the Van Rysel D500's actual
/// notifications (log a few raw payloads on first hardware test).
public enum FTMS {

    // MARK: - Assigned numbers (16-bit UUIDs as hex strings)

    public static let serviceUUID = "1826"
    public static let indoorBikeDataUUID = "2AD2"
    public static let controlPointUUID = "2AD9"

    // MARK: - Indoor Bike Data (0x2AD2)

    public struct IndoorBikeData: Equatable {
        public var speedKmh: Double?
        public var cadenceRpm: Double?
        public var powerWatts: Int?
        public var heartRateBpm: Int?
        public var totalDistanceMeters: Int?
        public var elapsedTimeSeconds: Int?

        public init(
            speedKmh: Double? = nil,
            cadenceRpm: Double? = nil,
            powerWatts: Int? = nil,
            heartRateBpm: Int? = nil,
            totalDistanceMeters: Int? = nil,
            elapsedTimeSeconds: Int? = nil
        ) {
            self.speedKmh = speedKmh
            self.cadenceRpm = cadenceRpm
            self.powerWatts = powerWatts
            self.heartRateBpm = heartRateBpm
            self.totalDistanceMeters = totalDistanceMeters
            self.elapsedTimeSeconds = elapsedTimeSeconds
        }
    }

    /// Parses an Indoor Bike Data notification. Returns nil on malformed
    /// payloads (fields promised by the flags but missing bytes).
    public static func parseIndoorBikeData(_ data: Data) -> IndoorBikeData? {
        var reader = Reader(data)
        guard let flags = reader.uint16() else { return nil }
        var result = IndoorBikeData()

        // Bit 0 is "More Data" and is inverted with respect to every other
        // flag: instantaneous speed is present when the bit is NOT set.
        if flags & 0x0001 == 0 {
            guard let raw = reader.uint16() else { return nil }
            result.speedKmh = Double(raw) * 0.01
        }
        if flags & 0x0002 != 0 { // average speed
            guard reader.skip(2) else { return nil }
        }
        if flags & 0x0004 != 0 { // instantaneous cadence, resolution 0.5 rpm
            guard let raw = reader.uint16() else { return nil }
            result.cadenceRpm = Double(raw) * 0.5
        }
        if flags & 0x0008 != 0 { // average cadence
            guard reader.skip(2) else { return nil }
        }
        if flags & 0x0010 != 0 { // total distance, uint24 meters
            guard let raw = reader.uint24() else { return nil }
            result.totalDistanceMeters = raw
        }
        if flags & 0x0020 != 0 { // resistance level
            guard reader.skip(2) else { return nil }
        }
        if flags & 0x0040 != 0 { // instantaneous power, sint16 watts
            guard let raw = reader.int16() else { return nil }
            result.powerWatts = Int(raw)
        }
        if flags & 0x0080 != 0 { // average power
            guard reader.skip(2) else { return nil }
        }
        if flags & 0x0100 != 0 { // expended energy: total + per hour + per minute
            guard reader.skip(5) else { return nil }
        }
        if flags & 0x0200 != 0 { // heart rate, uint8 bpm
            guard let raw = reader.uint8() else { return nil }
            result.heartRateBpm = Int(raw)
        }
        if flags & 0x0400 != 0 { // metabolic equivalent
            guard reader.skip(1) else { return nil }
        }
        if flags & 0x0800 != 0 { // elapsed time, uint16 seconds
            guard let raw = reader.uint16() else { return nil }
            result.elapsedTimeSeconds = Int(raw)
        }
        return result
    }

    // MARK: - Fitness Machine Control Point (0x2AD9)

    public enum OpCode: UInt8 {
        case requestControl = 0x00
        case reset = 0x01
        case startOrResume = 0x07
        case stopOrPause = 0x08
        case setIndoorBikeSimulation = 0x11
        case response = 0x80
    }

    public static func requestControl() -> Data {
        Data([OpCode.requestControl.rawValue])
    }

    public static func startOrResume() -> Data {
        Data([OpCode.startOrResume.rawValue])
    }

    /// Builds a "Set Indoor Bike Simulation Parameters" command — the SIM-mode
    /// message that makes the trainer reproduce a slope.
    ///
    /// - Parameters:
    ///   - gradePercent: road gradient, e.g. 5.5 for a 5.5% climb (resolution 0.01%)
    ///   - windSpeedMS: headwind positive, tailwind negative (resolution 0.001 m/s)
    ///   - crr: rolling resistance coefficient (resolution 0.0001)
    ///   - windResistanceKgM: 0.5·ρ·CdA in kg/m (resolution 0.01)
    ///
    /// REVIEW: crr/windResistance defaults mirror the physics engine's road
    /// defaults; if `RiderProfile` becomes user-configurable end to end,
    /// thread those values through here too so the trainer and the sim agree.
    public static func setIndoorBikeSimulation(
        gradePercent: Double,
        windSpeedMS: Double = 0,
        crr: Double = 0.004,
        windResistanceKgM: Double = 0.51
    ) -> Data {
        var data = Data([OpCode.setIndoorBikeSimulation.rawValue])
        data.appendLittleEndian(Int16(clamping: Int((windSpeedMS * 1000).rounded())))
        data.appendLittleEndian(Int16(clamping: Int((gradePercent * 100).rounded())))
        data.append(UInt8(clamping: Int((crr * 10000).rounded())))
        data.append(UInt8(clamping: Int((windResistanceKgM * 100).rounded())))
        return data
    }

    public struct ControlPointResponse: Equatable {
        public enum Result: UInt8 {
            case success = 0x01
            case notSupported = 0x02
            case invalidParameter = 0x03
            case operationFailed = 0x04
            case controlNotPermitted = 0x05
        }

        public let requestOpCode: UInt8
        /// nil when the trainer returned a result code outside the spec.
        public let result: Result?
    }

    /// Parses a Control Point response indication (first byte 0x80).
    public static func parseControlPointResponse(_ data: Data) -> ControlPointResponse? {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, bytes[0] == OpCode.response.rawValue else { return nil }
        return ControlPointResponse(
            requestOpCode: bytes[1],
            result: ControlPointResponse.Result(rawValue: bytes[2])
        )
    }
}

// MARK: - Byte-level helpers

private struct Reader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    mutating func uint8() -> UInt8? {
        guard offset + 1 <= bytes.count else { return nil }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func uint16() -> UInt16? {
        guard offset + 2 <= bytes.count else { return nil }
        defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    mutating func int16() -> Int16? {
        uint16().map(Int16.init(bitPattern:))
    }

    mutating func uint24() -> Int? {
        guard offset + 3 <= bytes.count else { return nil }
        defer { offset += 3 }
        return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16
    }

    mutating func skip(_ count: Int) -> Bool {
        guard offset + count <= bytes.count else { return false }
        offset += count
        return true
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: Int16) {
        let raw = UInt16(bitPattern: value)
        append(UInt8(raw & 0xFF))
        append(UInt8(raw >> 8))
    }
}

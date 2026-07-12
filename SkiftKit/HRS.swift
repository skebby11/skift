import Foundation

/// Pure encoding/decoding for the Bluetooth Heart Rate Service (HRS), the
/// Bluetooth SIG standard implemented by chest straps (Garmin HRM, Polar
/// H9/H10, Wahoo TICKR, ...). No CoreBluetooth dependency, so everything
/// here is unit-testable, mirroring `FTMS`.
///
/// Only the Heart Rate Measurement characteristic is modeled: RR intervals,
/// energy expended and sensor-contact status are read-once-and-discard —
/// see docs/hr-strap.md → Scope.
public enum HRS {

    // MARK: - Assigned numbers (16-bit UUIDs as hex strings)

    public static let serviceUUID = "180D"
    public static let measurementUUID = "2A37"

    // MARK: - Heart Rate Measurement (0x2A37)

    /// Parses a Heart Rate Measurement notification, returning the bpm value.
    /// Returns nil on malformed payloads (fields promised by the flags but
    /// missing bytes).
    ///
    /// Flags byte layout:
    /// - bit 0: 0 = bpm is uint8, 1 = bpm is uint16 LE
    /// - bits 1-2: sensor contact status (ignored)
    /// - bit 3: energy expended present, uint16 (skipped)
    /// - bit 4: one or more RR intervals present, uint16 each (skipped;
    ///   however many are present, the rest of the payload is consumed)
    /// - bits 5-7: reserved
    public static func parseHeartRateMeasurement(_ data: Data) -> Int? {
        var reader = Reader(data)
        guard let flags = reader.uint8() else { return nil }

        let bpm: Int
        if flags & 0x01 != 0 {
            guard let raw = reader.uint16() else { return nil }
            bpm = Int(raw)
        } else {
            guard let raw = reader.uint8() else { return nil }
            bpm = Int(raw)
        }

        if flags & 0x08 != 0 { // energy expended, uint16
            guard reader.skip(2) else { return nil }
        }
        if flags & 0x10 != 0 { // one or more RR intervals, uint16 each
            reader.skipToEnd()
        }
        return bpm
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

    mutating func skip(_ count: Int) -> Bool {
        guard offset + count <= bytes.count else { return false }
        offset += count
        return true
    }

    mutating func skipToEnd() {
        offset = bytes.count
    }
}

import XCTest
@testable import SkiftKit

final class HeartRateSessionTests: XCTestCase {

    // MARK: - Happy path

    func testHappyPathScanConnectSubscribeBpm() {
        let session = HeartRateSession()
        var commands: [HeartRateSession.Command] = []
        session.onCommand = { commands.append($0) }
        let id = UUID()

        session.startScan()
        session.handle(.didDiscover(id: id, name: "Polar H10", rssi: -55))
        session.connect(id: id, name: "Polar H10")
        session.handle(.didConnect(name: "Polar H10"))
        session.handle(.didDiscoverMeasurementCharacteristic(found: true))
        session.handle(.didReceiveMeasurement(Data([0x00, 0x4B]))) // 75 bpm, uint8 format

        XCTAssertEqual(commands, [
            .startScan,
            .stopScan,
            .connect(id: id),
            .discoverServices,
            .subscribeMeasurement,
        ])
        XCTAssertEqual(session.state, .connected(name: "Polar H10"))
        XCTAssertEqual(session.bpm, 75)
    }

    // MARK: - Discovery, dedupe, scan semantics

    func testDiscoveredSensorsDeduplicateById() {
        let session = HeartRateSession()
        let id1 = UUID()
        let id2 = UUID()

        session.startScan()
        session.handle(.didDiscover(id: id1, name: "Polar H10", rssi: -60))
        session.handle(.didDiscover(id: id2, name: "Garmin HRM", rssi: -70))
        session.handle(.didDiscover(id: id1, name: "Polar H10", rssi: -40))

        XCTAssertEqual(session.discovered, [
            DiscoveredSensor(id: id1, name: "Polar H10", rssi: -40),
            DiscoveredSensor(id: id2, name: "Garmin HRM", rssi: -70),
        ])
    }

    func testStopScanWhileScanningReturnsToIdle() {
        let session = HeartRateSession()
        session.startScan()
        XCTAssertEqual(session.state, .scanning)

        session.stopScan()

        XCTAssertEqual(session.state, .idle)
    }

    func testStartScanClearsPreviousDiscoveredAndError() {
        let session = HeartRateSession()
        session.startScan()
        session.handle(.didDiscover(id: UUID(), name: "Polar H10", rssi: -60))
        session.handle(.didDiscoverMeasurementCharacteristic(found: false)) // sets lastError

        session.startScan()

        XCTAssertEqual(session.discovered, [])
        XCTAssertNil(session.lastError)
    }

    func testStartScanWhileBluetoothUnavailableIsIgnored() {
        let session = HeartRateSession()
        var commands: [HeartRateSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.handle(.bluetoothDidBecomeUnavailable(reason: "Bluetooth is turned off."))
        let commandCountBefore = commands.count

        session.startScan()

        XCTAssertEqual(session.state, .bluetoothUnavailable(reason: "Bluetooth is turned off."))
        XCTAssertEqual(commands.count, commandCountBefore)
    }

    // MARK: - bpm parsing / malformed data

    func testReceivedMeasurementUpdatesBpm() {
        let session = HeartRateSession()
        session.handle(.didReceiveMeasurement(Data([0x01, 0x90, 0x00]))) // uint16 format, 144 bpm

        XCTAssertEqual(session.bpm, 144)
    }

    func testMalformedMeasurementIsIgnored() {
        let session = HeartRateSession()
        session.handle(.didReceiveMeasurement(Data([0x01, 0x90]))) // truncated uint16

        XCTAssertNil(session.bpm)
    }

    func testMalformedMeasurementDoesNotClearPreviousBpm() {
        let session = HeartRateSession()
        session.handle(.didReceiveMeasurement(Data([0x00, 0x4B]))) // 75 bpm
        session.handle(.didReceiveMeasurement(Data())) // malformed

        XCTAssertEqual(session.bpm, 75)
    }

    // MARK: - Error paths

    func testMissingMeasurementCharacteristicSetsErrorAndCancelsConnection() {
        let session = HeartRateSession()
        var commands: [HeartRateSession.Command] = []
        session.onCommand = { commands.append($0) }
        let id = UUID()
        session.connect(id: id, name: "Polar H10")
        session.handle(.didConnect(name: "Polar H10"))

        session.handle(.didDiscoverMeasurementCharacteristic(found: false))

        XCTAssertEqual(session.lastError, "Connected device does not expose the Heart Rate Measurement characteristic.")
        XCTAssertEqual(commands.last, .cancelConnection)
    }

    func testDidFailToConnectFromInitialConnectResetsToIdleWithError() {
        let session = HeartRateSession()
        let id = UUID()
        session.connect(id: id, name: "Polar H10")

        session.handle(.didFailToConnect(message: "Timed out."))

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastError, "Timed out.")

        let sessionNoMessage = HeartRateSession()
        sessionNoMessage.connect(id: id, name: "Polar H10")
        sessionNoMessage.handle(.didFailToConnect(message: nil))
        XCTAssertEqual(sessionNoMessage.lastError, "Connection failed.")
    }

    func testBluetoothUnavailableSetsStateAndClearsBpm() {
        let session = HeartRateSession()
        let id = UUID()
        session.connect(id: id, name: "Polar H10")
        session.handle(.didConnect(name: "Polar H10"))
        session.handle(.didDiscoverMeasurementCharacteristic(found: true))
        session.handle(.didReceiveMeasurement(Data([0x00, 0x4B])))
        XCTAssertEqual(session.bpm, 75)

        session.handle(.bluetoothDidBecomeUnavailable(reason: "Bluetooth is turned off."))

        XCTAssertEqual(session.state, .bluetoothUnavailable(reason: "Bluetooth is turned off."))
        XCTAssertNil(session.bpm)
    }

    // MARK: - User disconnect vs. immediate pending-connect reconnect

    private func connectedSession(id: UUID = UUID(), name: String = "Polar H10") -> (HeartRateSession, [HeartRateSession.Command]) {
        let session = HeartRateSession()
        var commands: [HeartRateSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.connect(id: id, name: name)
        session.handle(.didConnect(name: name))
        session.handle(.didDiscoverMeasurementCharacteristic(found: true))
        return (session, commands)
    }

    func testUserDisconnectDoesNotReconnect() {
        let id = UUID()
        let (session, _) = connectedSession(id: id)

        session.disconnect()
        session.handle(.didDisconnect(message: nil))

        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(session.bpm)
    }

    func testUnexpectedDisconnectImmediatelyReemitsConnectWithNoTimer() {
        let id = UUID()
        let (session, _) = connectedSession(id: id)
        session.handle(.didReceiveMeasurement(Data([0x00, 0x4B])))
        XCTAssertEqual(session.bpm, 75)

        var commands: [HeartRateSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.handle(.didDisconnect(message: "Connection lost."))

        XCTAssertEqual(session.state, .reconnecting(name: "Polar H10"))
        XCTAssertNil(session.bpm)
        XCTAssertEqual(commands, [.connect(id: id)])
        XCTAssertFalse(commands.contains { if case .startScan = $0 { return true }; return false })
    }

    func testSuccessfulReconnectResubscribes() {
        let id = UUID()
        let (session, _) = connectedSession(id: id)
        session.handle(.didDisconnect(message: "Connection lost."))

        var commands: [HeartRateSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.handle(.didConnect(name: "Polar H10"))
        session.handle(.didDiscoverMeasurementCharacteristic(found: true))

        XCTAssertEqual(commands, [.discoverServices, .subscribeMeasurement])
        XCTAssertEqual(session.state, .connected(name: "Polar H10"))
    }

    func testUserDisconnectDuringReconnectingSuppressesFurtherReconnect() {
        let id = UUID()
        let (session, _) = connectedSession(id: id)
        session.handle(.didDisconnect(message: "Connection lost.")) // now .reconnecting

        var commands: [HeartRateSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.disconnect()
        session.handle(.didFailToConnect(message: "Cancelled."))

        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(commands.contains { if case .connect = $0 { return true }; return false })
    }

    // MARK: - Remembered strap auto-connect intent

    func testConnectIntentWorksWithPlaceholderNameResolvedOnDidConnect() {
        // `HeartRateMonitor.connectRemembered` calls `session.connect` with a
        // placeholder name (the real name isn't known until CoreBluetooth
        // resolves it); the session must not depend on the name being
        // meaningful until `.didConnect` provides the real one.
        let session = HeartRateSession()
        var commands: [HeartRateSession.Command] = []
        session.onCommand = { commands.append($0) }
        let id = UUID()

        session.connect(id: id, name: "Remembered strap")
        XCTAssertEqual(session.state, .connecting)
        session.handle(.didConnect(name: "Polar H10"))

        XCTAssertEqual(session.state, .connected(name: "Polar H10"))
        XCTAssertEqual(commands, [.stopScan, .connect(id: id), .discoverServices])
    }
}

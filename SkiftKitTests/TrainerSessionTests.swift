import XCTest
@testable import SkiftKit

final class TrainerSessionTests: XCTestCase {

    // MARK: - Task 1: happy-path handshake

    func testHappyPathHandshakeEmitsExpectedCommandSequence() {
        let session = TrainerSession()
        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }

        let id = UUID()

        session.startScan()
        session.handle(.didDiscover(id: id, name: "D500", rssi: -50))
        session.connect(id: id, name: "D500")
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))
        // Control-point success response for Request Control (0x00), same byte
        // layout as FTMSTests.testParsesSuccessResponse.
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x01])))

        XCTAssertEqual(commands, [
            .startScan,
            .stopScan,
            .connect(id: id),
            .discoverServices,
            .discoverCharacteristics,
            .subscribeIndoorBikeData,
            .subscribeControlPoint,
            .write(FTMS.requestControl()),
            .write(FTMS.startOrResume()),
        ])
        XCTAssertEqual(session.state, .connected(name: "D500"))
        XCTAssertTrue(session.hasControl)
    }

    // MARK: - Task 2: discovery, live data, scan/stop semantics

    func testDiscoveredTrainersDeduplicateById() {
        let session = TrainerSession()
        let id1 = UUID()
        let id2 = UUID()

        session.startScan()
        session.handle(.didDiscover(id: id1, name: "D500", rssi: -60))
        session.handle(.didDiscover(id: id2, name: "Kickr", rssi: -70))
        session.handle(.didDiscover(id: id1, name: "D500", rssi: -40))

        XCTAssertEqual(session.discovered, [
            DiscoveredTrainer(id: id1, name: "D500", rssi: -40),
            DiscoveredTrainer(id: id2, name: "Kickr", rssi: -70),
        ])
    }

    func testIndoorBikeDataUpdatesLiveData() {
        let session = TrainerSession()
        // Same payload as FTMSTests.testParsesSpeedCadenceAndPower.
        let payload = Data([
            0x44, 0x00,
            0xC4, 0x09,
            0xB4, 0x00,
            0xFA, 0x00,
        ])

        session.handle(.didReceiveIndoorBikeData(payload))

        XCTAssertEqual(session.liveData, FTMS.IndoorBikeData(speedKmh: 25.0, cadenceRpm: 90.0, powerWatts: 250))
    }

    func testMalformedIndoorBikeDataIsIgnored() {
        let session = TrainerSession()
        session.handle(.didReceiveIndoorBikeData(Data([0x44, 0x00, 0xC4]))) // truncated

        XCTAssertEqual(session.liveData, FTMS.IndoorBikeData())
    }

    func testStopScanWhileScanningReturnsToIdle() {
        let session = TrainerSession()
        session.startScan()
        XCTAssertEqual(session.state, .scanning)

        session.stopScan()

        XCTAssertEqual(session.state, .idle)
    }

    func testStartScanClearsPreviousDiscoveredAndError() {
        let session = TrainerSession()
        session.startScan()
        session.handle(.didDiscover(id: UUID(), name: "D500", rssi: -60))
        session.handle(.didDiscoverFTMSService(found: false)) // sets lastError (Task 3), harmless here if not yet wired

        session.startScan()

        XCTAssertEqual(session.discovered, [])
        XCTAssertNil(session.lastError)
    }

    // MARK: - Task 3: error paths

    func testControlRefusedSetsErrorAndNoControl() {
        let session = TrainerSession()
        let id = UUID()
        session.connect(id: id, name: "D500")
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))

        // Control-point failure response for Request Control (0x00).
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x05])))

        XCTAssertFalse(session.hasControl)
        XCTAssertEqual(session.lastError, "Trainer refused control — is another app (e.g. Zwift) connected?")
    }

    func testMissingFTMSServiceCancelsConnection() {
        let session = TrainerSession()
        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        let id = UUID()
        session.connect(id: id, name: "D500")
        session.handle(.didConnect(name: "D500"))

        session.handle(.didDiscoverFTMSService(found: false))

        XCTAssertEqual(session.lastError, "Connected device does not expose the FTMS service.")
        XCTAssertEqual(commands.last, .cancelConnection)
    }

    func testMissingControlPointCharacteristicCancelsConnection() {
        let session = TrainerSession()
        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        let id = UUID()
        session.connect(id: id, name: "D500")
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))

        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: false))

        XCTAssertEqual(session.lastError, "Connected device does not expose the required FTMS characteristics.")
        XCTAssertEqual(commands.last, .cancelConnection)
    }

    func testDidFailToConnectFromInitialConnectResetsToIdleWithError() {
        let session = TrainerSession()
        let id = UUID()
        session.connect(id: id, name: "D500")

        session.handle(.didFailToConnect(message: "Timed out."))

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.lastError, "Timed out.")

        let sessionNoMessage = TrainerSession()
        sessionNoMessage.connect(id: id, name: "D500")
        sessionNoMessage.handle(.didFailToConnect(message: nil))
        XCTAssertEqual(sessionNoMessage.lastError, "Connection failed.")
    }

    func testBluetoothUnavailableSetsStateAndCancelsReconnect() {
        let session = TrainerSession()
        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }

        session.handle(.bluetoothDidBecomeUnavailable(reason: "Bluetooth is turned off."))

        XCTAssertEqual(session.state, .bluetoothUnavailable(reason: "Bluetooth is turned off."))
        XCTAssertTrue(commands.contains(.cancelReconnect))
    }

    func testRejectedNonControlCommandSetsError() {
        let session = TrainerSession()
        let id = UUID()
        session.connect(id: id, name: "D500")
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x01]))) // control granted

        // Same payload as FTMSTests.testParsesFailureResponse: Set Indoor Bike
        // Simulation (0x11) rejected with controlNotPermitted.
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x11, 0x05])))

        XCTAssertEqual(session.lastError, "Trainer rejected command 0x11.")
    }

    // MARK: - Task 4: user disconnect vs auto-reconnect

    private func connectedSession(id: UUID = UUID(), name: String = "D500") -> (TrainerSession, [TrainerSession.Command]) {
        let session = TrainerSession()
        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.connect(id: id, name: name)
        session.handle(.didConnect(name: name))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x01])))
        return (session, commands)
    }

    func testUserDisconnectDoesNotScheduleReconnect() {
        let id = UUID()
        let session = TrainerSession()
        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.connect(id: id, name: "D500")
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x01])))

        session.disconnect()
        XCTAssertEqual(commands.suffix(2), [.cancelReconnect, .cancelConnection])

        session.handle(.didDisconnect(message: nil))

        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(commands.contains { if case .scheduleReconnect = $0 { return true }; return false })
    }

    func testUnexpectedDisconnectSchedulesFirstRetryAfterOneSecond() {
        let (session, commands) = connectedSession()
        var later = commands

        session.onCommand = { later.append($0) }
        session.handle(.didDisconnect(message: "Connection lost."))

        XCTAssertEqual(session.state, .reconnecting(name: "D500", attempt: 1))
        XCTAssertFalse(session.hasControl)
        XCTAssertEqual(session.liveData, FTMS.IndoorBikeData())
        XCTAssertEqual(later.last, .scheduleReconnect(after: 1))
    }

    func testReconnectTimerFiredEmitsConnectToSamePeripheral() {
        let id = UUID()
        let (session, _) = connectedSession(id: id)
        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.handle(.didDisconnect(message: "Connection lost."))

        session.handle(.reconnectTimerFired)

        XCTAssertEqual(commands.last, .connect(id: id))
    }

    // MARK: - Task 5: backoff schedule, cap, reset, grade restore

    func testBackoffScheduleIsExponentialCappedAt30s() {
        let (session, initial) = connectedSession()
        var commands = initial
        session.onCommand = { commands.append($0) }

        session.handle(.didDisconnect(message: "Connection lost.")) // attempt 1

        var delays: [TimeInterval] = []
        func recordLastDelay() {
            if case let .scheduleReconnect(after) = commands.last! { delays.append(after) }
        }
        recordLastDelay()

        for _ in 0..<7 {
            session.handle(.reconnectTimerFired)
            session.handle(.didFailToConnect(message: "Still down."))
            recordLastDelay()
        }

        XCTAssertEqual(delays, [1, 2, 4, 8, 16, 30, 30, 30])
    }

    func testSuccessfulReconnectRunsFullHandshake() {
        let id = UUID()
        let (session, _) = connectedSession(id: id)
        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }

        session.handle(.didDisconnect(message: "Connection lost."))
        session.handle(.reconnectTimerFired)
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x01])))

        XCTAssertEqual(commands, [
            .scheduleReconnect(after: 1),
            .connect(id: id),
            .discoverServices,
            .discoverCharacteristics,
            .subscribeIndoorBikeData,
            .subscribeControlPoint,
            .write(FTMS.requestControl()),
            .write(FTMS.startOrResume()),
        ])
        XCTAssertEqual(session.state, .connected(name: "D500"))
        XCTAssertTrue(session.hasControl)
    }

    func testAttemptCounterResetsAfterSuccessfulReconnect() {
        let id = UUID()
        let (session, _) = connectedSession(id: id)
        session.handle(.didDisconnect(message: "Connection lost."))
        session.handle(.reconnectTimerFired)
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x01])))

        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.handle(.didDisconnect(message: "Connection lost again."))

        XCTAssertEqual(session.state, .reconnecting(name: "D500", attempt: 1))
        XCTAssertEqual(commands.last, .scheduleReconnect(after: 1))
    }

    func testLastGradeIsResentOnceControlRegained() {
        let id = UUID()
        let (session, _) = connectedSession(id: id)
        session.setGrade(percent: 3.5)

        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.handle(.didDisconnect(message: "Connection lost."))
        session.handle(.reconnectTimerFired)
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x01])))

        XCTAssertEqual(commands.suffix(2), [
            .write(FTMS.startOrResume()),
            .write(FTMS.setIndoorBikeSimulation(gradePercent: 3.5)),
        ])
    }

    func testNoGradeResentIfNeverSet() {
        let id = UUID()
        let (session, _) = connectedSession(id: id)

        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.handle(.didDisconnect(message: "Connection lost."))
        session.handle(.reconnectTimerFired)
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))
        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x01])))

        XCTAssertEqual(commands.last, .write(FTMS.startOrResume()))
    }

    func testSetGradeWithoutControlEmitsNothingButRecordsGrade() {
        let session = TrainerSession()
        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        let id = UUID()
        session.connect(id: id, name: "D500")
        session.handle(.didConnect(name: "D500"))
        session.handle(.didDiscoverFTMSService(found: true))
        session.handle(.didDiscoverCharacteristics(indoorBikeData: true, controlPoint: true))

        let countBeforeSetGrade = commands.count
        session.setGrade(percent: 2.0)
        XCTAssertEqual(commands.count, countBeforeSetGrade) // hasControl is still false: no write

        session.handle(.didReceiveControlPointResponse(Data([0x80, 0x00, 0x01]))) // control granted

        XCTAssertEqual(commands.last, .write(FTMS.setIndoorBikeSimulation(gradePercent: 2.0)))
    }

    /// Regression: a user `disconnect()` can race an in-flight reconnect
    /// attempt (backoff timer already fired, `.connect(id)` in progress). The
    /// resulting `didFailToConnect` must not continue the backoff loop.
    func testUserDisconnectDuringReconnectDoesNotContinueBackoff() {
        let (session, _) = connectedSession()
        session.handle(.didDisconnect(message: "Connection lost.")) // now .reconnecting(attempt: 1)
        session.handle(.reconnectTimerFired) // in-flight connect attempt

        var commands: [TrainerSession.Command] = []
        session.onCommand = { commands.append($0) }
        session.disconnect()
        session.handle(.didFailToConnect(message: "Cancelled."))

        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(commands.contains { if case .scheduleReconnect = $0 { return true }; return false })
    }
}

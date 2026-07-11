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
}

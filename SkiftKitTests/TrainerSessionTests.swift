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
}

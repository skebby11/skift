import XCTest
@testable import SkiftKit

final class PowerZonesTests: XCTestCase {

    func testZoneBoundariesAt200FTP() {
        XCTAssertEqual(PowerZone.zone(forPower: 0, ftp: 200), .recovery)
        XCTAssertEqual(PowerZone.zone(forPower: 109, ftp: 200), .recovery)   // 54.5%
        XCTAssertEqual(PowerZone.zone(forPower: 110, ftp: 200), .endurance)  // 55%
        XCTAssertEqual(PowerZone.zone(forPower: 151, ftp: 200), .endurance)  // 75.5%
        XCTAssertEqual(PowerZone.zone(forPower: 152, ftp: 200), .tempo)      // 76%
        XCTAssertEqual(PowerZone.zone(forPower: 181, ftp: 200), .tempo)      // 90.5%
        XCTAssertEqual(PowerZone.zone(forPower: 182, ftp: 200), .threshold)  // 91%
        XCTAssertEqual(PowerZone.zone(forPower: 211, ftp: 200), .threshold)  // 105.5%
        XCTAssertEqual(PowerZone.zone(forPower: 212, ftp: 200), .vo2max)     // 106%
        XCTAssertEqual(PowerZone.zone(forPower: 241, ftp: 200), .vo2max)     // 120.5%
        XCTAssertEqual(PowerZone.zone(forPower: 242, ftp: 200), .anaerobic)  // 121%
    }

    func testDegenerateFTPDoesNotCrash() {
        XCTAssertEqual(PowerZone.zone(forPower: 300, ftp: 0), .recovery)
        XCTAssertEqual(PowerZone.zone(forPower: 300, ftp: -10), .recovery)
    }
}

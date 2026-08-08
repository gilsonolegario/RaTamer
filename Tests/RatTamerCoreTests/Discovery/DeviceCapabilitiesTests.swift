import XCTest
@testable import RatTamerCore

final class DeviceCapabilitiesTests: XCTestCase {
    func testInitStoresValues() {
        let caps = DeviceCapabilities(hasReprogrammableControls: true,
                                      hasBattery: false,
                                      hasDPI: true,
                                      hasSmartShift: true)
        XCTAssertTrue(caps.hasReprogrammableControls)
        XCTAssertFalse(caps.hasBattery)
        XCTAssertTrue(caps.hasDPI)
        XCTAssertTrue(caps.hasSmartShift)
    }

    func testEquatable() {
        let a = DeviceCapabilities(hasReprogrammableControls: false,
                                   hasBattery: false,
                                   hasDPI: false,
                                   hasSmartShift: false)
        let b = DeviceCapabilities(hasReprogrammableControls: false,
                                   hasBattery: false,
                                   hasDPI: false,
                                   hasSmartShift: false)
        XCTAssertEqual(a, b)
    }
}

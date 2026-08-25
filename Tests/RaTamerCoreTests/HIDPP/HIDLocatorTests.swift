import XCTest
@testable import RaTamerCore

final class HIDLocatorTests: XCTestCase {
    func testUsagePairsParsesUsagePageDictionaries() {
        let pairs = HIDLocator.usagePairs(from: [
            ["DeviceUsagePage": 0xFF00, "DeviceUsage": 1],
            ["DeviceUsagePage": 0xFF00, "DeviceUsage": 2],
            ["DeviceUsagePage": 1, "DeviceUsage": 2],
        ])
        XCTAssertEqual(pairs.count, 3)
        XCTAssertEqual(pairs[0].page, 0xFF00)
        XCTAssertEqual(pairs[0].usage, 1)
        XCTAssertEqual(pairs[1].page, 0xFF00)
        XCTAssertEqual(pairs[2].page, 0x0001)
    }

    func testUsagePairsReturnsEmptyForInvalidInput() {
        XCTAssertTrue(HIDLocator.usagePairs(from: nil).isEmpty)
        XCTAssertTrue(HIDLocator.usagePairs(from: ["nope"]).isEmpty)
        XCTAssertTrue(HIDLocator.usagePairs(from: [[1]]).isEmpty)
    }

    func testIsHIDPPInterfaceDetectsLogitechUsagePages() {
        XCTAssertTrue(HIDLocator.isHIDPPInterface(usagePairs: [(0xFF00, 1)]))
        XCTAssertTrue(HIDLocator.isHIDPPInterface(usagePairs: [(0xFF43, 1)]))
        XCTAssertTrue(HIDLocator.isHIDPPInterface(usagePairs: [(0x0001, 2), (0xFF00, 4)]))
        XCTAssertFalse(HIDLocator.isHIDPPInterface(usagePairs: [(0x0001, 2)]))
        XCTAssertFalse(HIDLocator.isHIDPPInterface(usagePairs: []))
    }
}

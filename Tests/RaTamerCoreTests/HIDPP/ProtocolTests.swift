import XCTest
@testable import RaTamerCore

final class ProtocolTests: XCTestCase {
    func testBuildShortPadsAndSizes() {
        let bytes = HIDPP.buildShort(
            deviceIndex: 0x01, featureIndex: 0x08,
            functionID: 0x00, softwareID: 0x01,
            params: [0x1B, 0x04, 0x00]
        )
        XCTAssertEqual(bytes, [0x10, 0x01, 0x08, 0x01, 0x1B, 0x04, 0x00])
    }

    func testBuildLongPadsTo20() {
        let bytes = HIDPP.buildLong(
            deviceIndex: 0x01, featureIndex: 0x08,
            functionID: 0x03, softwareID: 0x04,
            params: [0x00, 0xC3, 0x01]
        )
        XCTAssertEqual(bytes.count, 20)
        XCTAssertEqual(bytes[0], 0x11)
        XCTAssertEqual(bytes[3], 0x34)
        XCTAssertEqual(bytes[4], 0x00)
        XCTAssertEqual(bytes[5], 0xC3)
        XCTAssertEqual(bytes[6], 0x01)
    }

    func testControlTaskName() {
        XCTAssertEqual(ControlTaskName.name(for: 0x0038), "Left Button")
        XCTAssertEqual(ControlTaskName.name(for: 0x009D), "Scroll Mode (SmartShift)")
        XCTAssertEqual(ControlTaskName.name(for: 0x00A9), "Thumb / Gesture")
        XCTAssertEqual(ControlTaskName.name(for: 0x1234), "Control 0x1234")
    }

    func testSmartShiftTaskConstant() {
        XCTAssertEqual(HIDPP.taskSmartShift, 0x009D)
    }
}

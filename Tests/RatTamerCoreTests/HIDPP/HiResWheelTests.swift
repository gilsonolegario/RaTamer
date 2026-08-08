import XCTest
@testable import RatTamerCore

final class HiResWheelTests: XCTestCase {
    private func makeService(_ mock: MockHIDDevice) -> HiResWheel {
        HiResWheel(session: HIDPPSession(device: mock),
                   deviceIndex: 1, featureIndex: 0x0E)
    }

    func testGetInfoParsesCapabilities() throws {
        let mock = MockHIDDevice()
        // multiplier=8, flags=0x0C (invert+switch), ratches=0x18, diameter=0x14
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x00, 0x08, 0x0C, 0x18, 0x14]]
        let info = try makeService(mock).getInfo()
        XCTAssertEqual(info.multiplier, 8)
        XCTAssertTrue(info.hasInvert)
        XCTAssertTrue(info.hasSwitch)
    }

    func testGetInfoNoInvert() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x00, 0x08, 0x00, 0x18, 0x14]]
        let info = try makeService(mock).getInfo()
        XCTAssertFalse(info.hasInvert)
        XCTAssertFalse(info.hasSwitch)
    }

    func testGetWheelModeNativeLow() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x00]]
        let mode = try makeService(mock).getWheelMode()
        XCTAssertFalse(mode.inverted)
        XCTAssertFalse(mode.highResolution)
        XCTAssertFalse(mode.diverted)
    }

    func testGetWheelModeInvertedHighDiverted() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x07]]
        let mode = try makeService(mock).getWheelMode()
        XCTAssertTrue(mode.inverted)
        XCTAssertTrue(mode.highResolution)
        XCTAssertTrue(mode.diverted)
    }

    func testSetInvertedTruePreservesModeBits() throws {
        let mock = MockHIDDevice()
        // current mode 0x02 (high, native) -> set invert -> 0x06
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x02]]
        try makeService(mock).setInverted(true)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(7)), [0x11, 0x01, 0x0E, 0x21, 0x06, 0x00, 0x00])
    }

    func testSetInvertedFalsePreservesModeBits() throws {
        let mock = MockHIDDevice()
        // current mode 0x06 (inverted, high, native) -> clear invert -> 0x02
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x06]]
        try makeService(mock).setInverted(false)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(7)), [0x11, 0x01, 0x0E, 0x21, 0x02, 0x00, 0x00])
    }

    func testSetInvertedReadsCurrentModeFirst() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x00]]
        try makeService(mock).setInverted(true)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(7)), [0x11, 0x01, 0x0E, 0x21, 0x04, 0x00, 0x00])
    }

    func testFeatureIDIs2121() {
        XCTAssertEqual(HiResWheel.featureID, 0x2121)
    }
}

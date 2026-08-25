import XCTest
@testable import RaTamerCore

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

    func testParseWheelMovementParsesDeltaAndFlags() {
        // flags 0x1F -> periods 15, resolution 1; deltaV 0x002C = 44
        let m = HiResWheel.parseWheelMovement(
            [0x11, 0x01, 0x0E, 0x00, 0x1F, 0x00, 0x2C],
            deviceIndex: 1, featureIndex: 0x0E)
        XCTAssertEqual(m?.deltaV, 44)
        XCTAssertEqual(m?.periods, 15)
        XCTAssertEqual(m?.resolution, true)
    }

    func testParseWheelMovementNegativeDelta() {
        // flags 0x01 -> periods 1, resolution 0; deltaV 0xFF38 = -200
        let m = HiResWheel.parseWheelMovement(
            [0x11, 0x01, 0x0E, 0x00, 0x01, 0xFF, 0x38],
            deviceIndex: 1, featureIndex: 0x0E)
        XCTAssertEqual(m?.deltaV, -200)
        XCTAssertEqual(m?.periods, 1)
        XCTAssertEqual(m?.resolution, false)
    }

    func testParseWheelMovementRejectsOtherFeature() {
        XCTAssertNil(HiResWheel.parseWheelMovement(
            [0x11, 0x01, 0x0A, 0x00, 0x01, 0x00, 0x2C],
            deviceIndex: 1, featureIndex: 0x0E))
    }

    func testParseWheelMovementRejectsShortReport() {
        XCTAssertNil(HiResWheel.parseWheelMovement(
            [0x11, 0x01, 0x0E, 0x00, 0x01],
            deviceIndex: 1, featureIndex: 0x0E))
    }

    func testSetWheelModeHighResDiverted() throws {
        let mock = MockHIDDevice()
        // current mode 0x00 (native low) -> set high + target -> 0x03
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x00]]
        try makeService(mock).setWheelMode(highResolution: true, target: true)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(7)), [0x11, 0x01, 0x0E, 0x21, 0x03, 0x00, 0x00])
    }

    func testSetWheelModePreservesInvert() throws {
        let mock = MockHIDDevice()
        // current mode 0x04 (inverted, native low) -> set high + target -> 0x07
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x04]]
        try makeService(mock).setWheelMode(highResolution: true, target: true)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(7)), [0x11, 0x01, 0x0E, 0x21, 0x07, 0x00, 0x00])
    }

    func testSetWheelModeRestoresNative() throws {
        let mock = MockHIDDevice()
        // current mode 0x03 (diverted high) -> set native low -> 0x00
        mock.queuedReads = [[0x11, 0x01, 0x0E, 0x10, 0x03]]
        try makeService(mock).setWheelMode(highResolution: false, target: false)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(7)), [0x11, 0x01, 0x0E, 0x21, 0x00, 0x00, 0x00])
    }

    func testSetInvertedThrowsWhenReadFails() {
        // No queued read: the mode read times out. The set must throw instead
        // of writing a zeroed mode that wipes the divert/hi-res bits.
        let mock = MockHIDDevice()
        XCTAssertThrowsError(try makeService(mock).setInverted(true))
        XCTAssertEqual(mock.writeLog.count, 1, "only the read request may be written")
        XCTAssertEqual(Array(mock.writeLog[0].prefix(4)), [0x11, 0x01, 0x0E, 0x11])
    }

    func testSetWheelModeThrowsWhenReadFails() {
        let mock = MockHIDDevice()
        XCTAssertThrowsError(try makeService(mock).setWheelMode(highResolution: true, target: true))
        XCTAssertEqual(mock.writeLog.count, 1, "only the read request may be written")
        XCTAssertEqual(Array(mock.writeLog[0].prefix(4)), [0x11, 0x01, 0x0E, 0x11])
    }
}

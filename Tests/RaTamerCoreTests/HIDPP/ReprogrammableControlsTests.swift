import XCTest
@testable import RaTamerCore

final class ReprogrammableControlsTests: XCTestCase {
    private func makeService(_ mock: MockHIDDevice) -> ReprogrammableControls {
        ReprogrammableControls(session: HIDPPSession(device: mock),
                               deviceIndex: 1, featureIndex: 0x0A)
    }

    func testGetCountParsesCount() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x00, 0x08, 0, 0, 0, 0]]
        XCTAssertEqual(try makeService(mock).getCount(), 8)
    }

    func testControlInfoDecodesRow() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x10, 0x00, 0xC4, 0x00, 0x9D, 0x31, 0x00, 0x03, 0x07, 0x00]]
        let info = try makeService(mock).controlInfo(at: 6)
        XCTAssertEqual(info?.cid, 0x00C4)
        XCTAssertEqual(info?.taskID, 0x009D)
        XCTAssertEqual(info?.flags, 0x31)
        XCTAssertEqual(info?.group, 3)
        XCTAssertEqual(info?.groupMask, 0x07)
        XCTAssertTrue(info?.isMouseButton == true)
        XCTAssertTrue(info?.isReprogrammable == true)
        XCTAssertTrue(info?.isDivertable == true)
    }

    func testControlInfoNotDivertableWhenFlagCleared() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x10, 0x00, 0x50, 0x00, 0x38, 0x01, 0x00, 0x01, 0x01, 0x00]]
        let info = try makeService(mock).controlInfo(at: 0)
        XCTAssertEqual(info?.cid, 0x0050)
        XCTAssertTrue(info?.isMouseButton == true)
        XCTAssertTrue(info?.isDivertable == false)
    }

    func testEnumerateCollectsAllRows() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [
            [0x11, 0x01, 0x0A, 0x00, 0x02, 0, 0, 0, 0],
            [0x11, 0x01, 0x0A, 0x10, 0x00, 0x50, 0x00, 0x38, 0x01, 0x00, 0x01, 0x01, 0x00],
            [0x11, 0x01, 0x0A, 0x10, 0x00, 0x51, 0x00, 0x39, 0x01, 0x00, 0x01, 0x01, 0x00],
        ]
        let controls = try makeService(mock).enumerate()
        XCTAssertEqual(controls.count, 2)
        XCTAssertEqual(controls.map(\.cid), [0x0050, 0x0051])
    }

    func testSetDivertedWritesDivertFlags() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x31, 0, 0, 0, 0, 0]]
        try makeService(mock).setDiverted(cid: 0x00C4, diverted: true)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(9)), [0x11, 0x01, 0x0A, 0x31, 0x00, 0xC4, 0x03, 0x00, 0x00])
        XCTAssertEqual(written.count, 20)
    }

    func testSetDivertedWritesUndivertFlags() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x31, 0, 0, 0, 0, 0]]
        try makeService(mock).setDiverted(cid: 0x00C4, diverted: false)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(9)), [0x11, 0x01, 0x0A, 0x31, 0x00, 0xC4, 0x02, 0x00, 0x00])
    }

    func testSetDivertedRawXYWritesRawXYFlags() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x31, 0, 0, 0, 0, 0]]
        try makeService(mock).setDiverted(cid: 0x00C3, diverted: true, rawXY: true)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(9)), [0x11, 0x01, 0x0A, 0x31, 0x00, 0xC3, 0x33, 0x00, 0x00])
    }

    func testSetDivertedRawXYUndivertWritesRawXYValidOnly() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x31, 0, 0, 0, 0, 0]]
        try makeService(mock).setDiverted(cid: 0x00C3, diverted: false, rawXY: true)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(9)), [0x11, 0x01, 0x0A, 0x31, 0x00, 0xC3, 0x22, 0x00, 0x00])
    }

    func testParseRawXYEventDecodesSignedDeltas() {
        let bytes: [UInt8] = [0x11, 0x01, 0x0A, 0x10, 0x01, 0x2C, 0xFF, 0x38, 0, 0, 0, 0]
        let raw = ReprogrammableControls.parseRawXYEvent(bytes, deviceIndex: 1, featureIndex: 0x0A)
        XCTAssertEqual(raw?.dx, 300)
        XCTAssertEqual(raw?.dy, -200)
    }

    func testParseRawXYEventDecodesZeroAndNegative() {
        let zero: [UInt8] = [0x11, 0x01, 0x0A, 0x10, 0, 0, 0, 0]
        XCTAssertEqual(ReprogrammableControls.parseRawXYEvent(zero, deviceIndex: 1, featureIndex: 0x0A)?.dx, 0)
        XCTAssertEqual(ReprogrammableControls.parseRawXYEvent(zero, deviceIndex: 1, featureIndex: 0x0A)?.dy, 0)
        let negative: [UInt8] = [0x11, 0x01, 0x0A, 0x10, 0x80, 0x00, 0x80, 0x00]
        XCTAssertEqual(ReprogrammableControls.parseRawXYEvent(negative, deviceIndex: 1, featureIndex: 0x0A)?.dx, Int16.min)
        XCTAssertEqual(ReprogrammableControls.parseRawXYEvent(negative, deviceIndex: 1, featureIndex: 0x0A)?.dy, Int16.min)
    }

    func testParseRawXYEventRejectsOthers() {
        XCTAssertNil(ReprogrammableControls.parseRawXYEvent([0x11, 0x01, 0x0A, 0x00, 0x01, 0x2C, 0xFF, 0x38], deviceIndex: 1, featureIndex: 0x0A))
        XCTAssertNil(ReprogrammableControls.parseRawXYEvent([0x11, 0x02, 0x0A, 0x10, 0x01, 0x2C, 0xFF, 0x38], deviceIndex: 1, featureIndex: 0x0A))
        XCTAssertNil(ReprogrammableControls.parseRawXYEvent([0x11, 0x01, 0x0B, 0x10, 0x01, 0x2C, 0xFF, 0x38], deviceIndex: 1, featureIndex: 0x0A))
        XCTAssertNil(ReprogrammableControls.parseRawXYEvent([0x10, 0x01, 0x0A, 0x10, 0x01, 0x2C, 0xFF, 0x38], deviceIndex: 1, featureIndex: 0x0A))
        XCTAssertNil(ReprogrammableControls.parseRawXYEvent([0x11, 0x01, 0x0A, 0x10, 0x01, 0x2C, 0xFF], deviceIndex: 1, featureIndex: 0x0A))
    }

    func testReportingFlagsDecodes() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x21, 0x00, 0xC4, 0x01, 0x00, 0x00]]
        let flags = try makeService(mock).reportingFlags(cid: 0x00C4)
        XCTAssertEqual(flags?.flags, 0x01)
        XCTAssertEqual(flags?.remap, 0x0000)
    }

    func testSetRemappedPreservesFlagsAndWritesTarget() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x21, 0x00, 0x50, 0x01, 0x00, 0x00]]
        try makeService(mock).setRemapped(cid: 0x0050, target: 0x0051)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(9)), [0x11, 0x01, 0x0A, 0x31, 0x00, 0x50, 0x01, 0x00, 0x51])
        XCTAssertEqual(written.count, 20)
    }

    func testSetRemappedFallsBackToZeroFlagsWhenNoReport() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[]]
        try makeService(mock).setRemapped(cid: 0x0051, target: 0x0050)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(9)), [0x11, 0x01, 0x0A, 0x31, 0x00, 0x51, 0x00, 0x00, 0x50])
    }

    func testResetRemapWritesOwnCidAsTarget() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x21, 0x00, 0x50, 0x01, 0x00, 0x00]]
        try makeService(mock).resetRemap(cid: 0x0050)
        let written = try XCTUnwrap(mock.writeLog.last)
        XCTAssertEqual(Array(written.prefix(9)), [0x11, 0x01, 0x0A, 0x31, 0x00, 0x50, 0x01, 0x00, 0x50])
    }

    func testParseDivertedEventPress() {
        let bytes: [UInt8] = [0x11, 0x01, 0x0A, 0x00, 0x00, 0xC4, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        XCTAssertEqual(ReprogrammableControls.parseDivertedEvent(bytes, deviceIndex: 1, featureIndex: 0x0A), [0x00C4])
    }

    func testParseDivertedEventMultipleAndRelease() {
        let pressed: [UInt8] = [0x11, 0x01, 0x0A, 0x00, 0x00, 0xC4, 0x00, 0x53, 0x00, 0x00, 0x00, 0x00]
        XCTAssertEqual(ReprogrammableControls.parseDivertedEvent(pressed, deviceIndex: 1, featureIndex: 0x0A), [0x00C4, 0x0053])
        let released: [UInt8] = [0x11, 0x01, 0x0A, 0x00, 0, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(ReprogrammableControls.parseDivertedEvent(released, deviceIndex: 1, featureIndex: 0x0A), [])
    }

    func testParseDivertedEventRejectsOthers() {
        XCTAssertNil(ReprogrammableControls.parseDivertedEvent([0x11, 0x01, 0x0B, 0x00, 0x00, 0xC4, 0, 0, 0, 0, 0, 0], deviceIndex: 1, featureIndex: 0x0A))
        XCTAssertNil(ReprogrammableControls.parseDivertedEvent([0x11, 0x02, 0x0A, 0x00, 0x00, 0xC4, 0, 0, 0, 0, 0, 0], deviceIndex: 1, featureIndex: 0x0A))
        XCTAssertNil(ReprogrammableControls.parseDivertedEvent([0x11, 0x01, 0x0A, 0x10, 0x00, 0xC4, 0, 0, 0, 0, 0, 0], deviceIndex: 1, featureIndex: 0x0A))
        XCTAssertNil(ReprogrammableControls.parseDivertedEvent([0x10, 0x01, 0x0A, 0x00, 0x00, 0xC4, 0, 0, 0, 0, 0, 0], deviceIndex: 1, featureIndex: 0x0A))
        XCTAssertNil(ReprogrammableControls.parseDivertedEvent([0x11, 0x01, 0x0A, 0x00, 0x00], deviceIndex: 1, featureIndex: 0x0A))
    }
}

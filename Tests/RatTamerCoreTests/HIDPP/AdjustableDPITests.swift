import XCTest
@testable import RatTamerCore

final class AdjustableDPITests: XCTestCase {
    private func makeService(_ mock: MockHIDDevice) -> AdjustableDPI {
        AdjustableDPI(session: HIDPPSession(device: mock),
                      deviceIndex: 1, featureIndex: 0x0B)
    }

    func testGetSensorCountParsesCount() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0B, 0x00, 0x01]]
        XCTAssertEqual(try makeService(mock).getSensorCount(), 1)
    }

    func testGetSensorDpiListDecodesExplicitValues() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0B, 0x10, 0x00, 0x03, 0xE8, 0x0C, 0x80, 0x00, 0x00]]
        let list = try makeService(mock).getSensorDpiList(sensor: 0)
        XCTAssertEqual(list, [1000, 3200])
    }

    func testGetSensorDpiListExpandsRange() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0B, 0x10, 0x00, 0x00, 0xC8, 0xE0, 0x64, 0x01, 0x90, 0x00, 0x00]]
        let list = try makeService(mock).getSensorDpiList(sensor: 0)
        XCTAssertEqual(list, [200, 300, 400])
    }

    func testGetSensorDpiDecodesValueAndDefault() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0B, 0x20, 0x00, 0x03, 0xE8, 0x03, 0xE8]]
        let info = try makeService(mock).getSensorDpi(sensor: 0)
        XCTAssertEqual(info?.dpi, 1000)
        XCTAssertEqual(info?.defaultDpi, 1000)
    }

    func testGetSensorDpiDefaultZeroWhenAbsent() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0B, 0x20, 0x00, 0x03, 0xE8, 0x00, 0x00]]
        let info = try makeService(mock).getSensorDpi(sensor: 0)
        XCTAssertEqual(info?.dpi, 1000)
        XCTAssertEqual(info?.defaultDpi, 0)
    }

    func testSetSensorDpiWritesPayload() throws {
        let mock = MockHIDDevice()
        try makeService(mock).setSensorDpi(sensor: 0, dpi: 1600)
        let written = try XCTUnwrap(mock.writeLog.first)
        XCTAssertEqual(Array(written.prefix(9)), [0x11, 0x01, 0x0B, 0x31, 0x00, 0x06, 0x40, 0x00, 0x00])
        XCTAssertEqual(written.count, 20)
    }

    func testFeatureIDIs2201() {
        XCTAssertEqual(AdjustableDPI.featureID, 0x2201)
    }

    func testExpandRangeMarkerAtStartTreatedAsPlainValue() {
        // Range marker as the first entry: no previous value to expand from.
        XCTAssertEqual(AdjustableDPI.expand([0xE064, 0x0190]), [0xE064, 0x0190])
    }

    func testExpandRangeMarkerAtEndTreatedAsPlainValue() {
        // Range marker as the last entry: no end value to expand to.
        XCTAssertEqual(AdjustableDPI.expand([0x00C8, 0xE064]), [0x00C8, 0xE064])
    }

    func testExpandZeroStepRangeMarkerDoesNotLoopForever() {
        // 0xE000 is a range marker with step 0: expanding would never advance.
        XCTAssertEqual(AdjustableDPI.expand([0x00C8, 0xE000, 0x0190]), [0x00C8, 0xE000, 0x0190])
    }

    func testExpandValidRangeStillExpands() {
        XCTAssertEqual(AdjustableDPI.expand([0x00C8, 0xE064, 0x0190]), [0x00C8, 0x012C, 0x0190])
    }
}

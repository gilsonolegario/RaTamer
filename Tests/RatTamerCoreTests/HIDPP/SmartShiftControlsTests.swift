import XCTest
@testable import RatTamerCore

final class SmartShiftControlsTests: XCTestCase {
    private func makeService(_ mock: MockHIDDevice) -> SmartShiftControls {
        SmartShiftControls(session: HIDPPSession(device: mock),
                           deviceIndex: 1, featureIndex: 0x0D)
    }

    func testGetRatchetControlModeDecodesStatus() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0D, 0x01, 0x02, 0x1E, 0x1E]]
        let status = try makeService(mock).getRatchetControlMode()
        XCTAssertEqual(status?.wheelMode, 2)
        XCTAssertEqual(status?.autoDisengage, 30)
        XCTAssertEqual(status?.autoDisengageDefault, 30)
    }

    func testGetRatchetControlModeReturnsNilOnShortResponse() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0D, 0x01, 0x02]]
        XCTAssertNil(try makeService(mock).getRatchetControlMode())
    }

    func testSetRatchetControlModeWritesPayload() throws {
        let mock = MockHIDDevice()
        try makeService(mock).setRatchetControlMode(status: SmartShiftStatus(
            wheelMode: 1, autoDisengage: 0, autoDisengageDefault: 0))
        let written = try XCTUnwrap(mock.writeLog.first)
        XCTAssertEqual(Array(written.prefix(9)),
                       [0x11, 0x01, 0x0D, 0x11, 0x01, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(written.count, 20)
    }

    func testFeatureIDIs2110() {
        XCTAssertEqual(SmartShiftControls.featureID, 0x2110)
    }

    func testEnhancedUsesFunctionOneForGet() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0D, 0x11, 0x02, 0x1E, 0x1E]]
        let service = SmartShiftControls(session: HIDPPSession(device: mock), deviceIndex: 1,
                                         featureIndex: 0x0D, featureID: SmartShiftControls.enhancedFeatureID)
        let status = try service.getRatchetControlMode()
        XCTAssertEqual(status?.wheelMode, 2)
        XCTAssertEqual(mock.writeLog.first.map { $0[3] >> 4 }, 0x01)
    }

    func testEnhancedUsesFunctionTwoForSet() throws {
        let mock = MockHIDDevice()
        let service = SmartShiftControls(session: HIDPPSession(device: mock), deviceIndex: 1,
                                         featureIndex: 0x0D, featureID: SmartShiftControls.enhancedFeatureID)
        try service.setRatchetControlMode(status: SmartShiftStatus(wheelMode: 2, autoDisengage: 0x1E, autoDisengageDefault: 0x1E))
        XCTAssertEqual(mock.writeLog.first.map { $0[3] >> 4 }, 0x02)
    }

    func testEnhancedFeatureIDIs2111() {
        XCTAssertEqual(SmartShiftControls.enhancedFeatureID, 0x2111)
    }

    func testStatusForFreespinIgnoresSensitivity() {
        let status = SmartShiftStatus.status(for: .freespin, sensitivity: 50)
        XCTAssertEqual(status.wheelMode, 1)
        XCTAssertEqual(status.autoDisengage, 0x00)
        XCTAssertEqual(status.autoDisengageDefault, 0)
    }

    func testStatusForRatchetedAlwaysEngaged() {
        let status = SmartShiftStatus.status(for: .ratcheted, sensitivity: 50)
        XCTAssertEqual(status.wheelMode, 2)
        XCTAssertEqual(status.autoDisengage, 0xFF)
        XCTAssertEqual(status.autoDisengageDefault, 0)
    }

    func testStatusForSmartshiftUsesSensitivity() {
        XCTAssertEqual(SmartShiftStatus.status(for: .smartshift, sensitivity: 16).autoDisengage, 16)
        XCTAssertEqual(SmartShiftStatus.status(for: .smartshift, sensitivity: 1).autoDisengage, 1)
        XCTAssertEqual(SmartShiftStatus.status(for: .smartshift, sensitivity: 100).autoDisengage, 100)
        XCTAssertEqual(SmartShiftStatus.status(for: .smartshift, sensitivity: 16).wheelMode, 2)
        XCTAssertEqual(SmartShiftStatus.status(for: .smartshift, sensitivity: 16).autoDisengageDefault, 0)
    }

    func testStatusClampsSensitivityToProtocolRange() {
        XCTAssertEqual(SmartShiftStatus.status(for: .smartshift, sensitivity: 0).autoDisengage, 1)
        XCTAssertEqual(SmartShiftStatus.status(for: .smartshift, sensitivity: -5).autoDisengage, 1)
        XCTAssertEqual(SmartShiftStatus.status(for: .smartshift, sensitivity: 999).autoDisengage, 254)
    }
}

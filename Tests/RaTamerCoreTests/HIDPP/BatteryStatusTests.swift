import XCTest
@testable import RaTamerCore

final class BatteryStatusTests: XCTestCase {
    private func makeService(_ mock: MockHIDDevice) -> BatteryStatus {
        BatteryStatus(session: HIDPPSession(device: mock),
                      deviceIndex: 1, featureIndex: 0x07)
    }

    func testGetBatteryInfoDischargingHighCapacity() throws {
        let mock = MockHIDDevice()
        // [capacity=90, next=75, status=0 (discharging)]
        mock.queuedReads = [[0x11, 0x01, 0x07, 0x00, 0x5A, 0x4B, 0x00]]
        let info = try makeService(mock).getBatteryInfo()
        XCTAssertEqual(info.capacity, 90)
        XCTAssertEqual(info.nextCapacity, 75)
        XCTAssertEqual(info.state, .discharging)
        XCTAssertEqual(info.level, .full)
    }

    func testGetBatteryInfoDischargingCritical() throws {
        let mock = MockHIDDevice()
        // capacity=10 -> critical
        mock.queuedReads = [[0x11, 0x01, 0x07, 0x00, 0x0A, 0x00, 0x00]]
        let info = try makeService(mock).getBatteryInfo()
        XCTAssertEqual(info.state, .discharging)
        XCTAssertEqual(info.level, .critical)
    }

    func testGetBatteryInfoDischargingLow() throws {
        let mock = MockHIDDevice()
        // capacity=29 -> low (< 30)
        mock.queuedReads = [[0x11, 0x01, 0x07, 0x00, 0x1D, 0x00, 0x00]]
        let info = try makeService(mock).getBatteryInfo()
        XCTAssertEqual(info.level, .low)
    }

    func testGetBatteryInfoDischargingGood() throws {
        let mock = MockHIDDevice()
        // capacity=60 -> good
        mock.queuedReads = [[0x11, 0x01, 0x07, 0x00, 0x3C, 0x00, 0x00]]
        let info = try makeService(mock).getBatteryInfo()
        XCTAssertEqual(info.level, .good)
    }

    func testGetBatteryInfoRechargingCapacityUnknown() throws {
        let mock = MockHIDDevice()
        // status=1 (recharging), capacity 0 (unknown while charging)
        mock.queuedReads = [[0x11, 0x01, 0x07, 0x00, 0x00, 0x00, 0x01]]
        let info = try makeService(mock).getBatteryInfo()
        XCTAssertEqual(info.state, .recharging)
        XCTAssertEqual(info.level, .unknown)
    }

    func testGetBatteryInfoChargeCompleteIsFull() throws {
        let mock = MockHIDDevice()
        // status=3 (charge complete) -> level full regardless of capacity
        mock.queuedReads = [[0x11, 0x01, 0x07, 0x00, 0x00, 0x00, 0x03]]
        let info = try makeService(mock).getBatteryInfo()
        XCTAssertEqual(info.state, .full)
        XCTAssertEqual(info.level, .full)
        XCTAssertEqual(info.capacity, 100)
    }

    func testGetBatteryInfoErrorStatus() throws {
        let mock = MockHIDDevice()
        // status=5 (invalid battery type) -> not charging
        mock.queuedReads = [[0x11, 0x01, 0x07, 0x00, 0x00, 0x00, 0x05]]
        let info = try makeService(mock).getBatteryInfo()
        XCTAssertEqual(info.state, .notCharging)
    }

    func testGetBatteryInfoShortResponseThrows() {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x07]]
        XCTAssertThrowsError(try makeService(mock).getBatteryInfo())
    }

    func testFeatureIDIs1000() {
        XCTAssertEqual(BatteryStatus.featureID, 0x1000)
    }

    func testGetBatteryInfoUnifiedReadsStateFromByteFive() throws {
        let mock = MockHIDDevice()
        // 0x1004 unified: capacity [4]=80, charging status [5]=2 (almost full),
        // discharge next [6]=20, power source [7]=1
        mock.queuedReads = [[0x11, 0x01, 0x09, 0x00, 0x50, 0x02, 0x14, 0x01]]
        let service = BatteryStatus(session: HIDPPSession(device: mock), deviceIndex: 1,
                                    featureIndex: 0x09, featureID: BatteryStatus.unifiedFeatureID)
        let info = try service.getBatteryInfo()
        XCTAssertEqual(info.capacity, 80)
        XCTAssertEqual(info.nextCapacity, 20)
        XCTAssertEqual(info.state, .charging)
    }

    func testUnifiedFeatureIDIs1004() {
        XCTAssertEqual(BatteryStatus.unifiedFeatureID, 0x1004)
    }
}

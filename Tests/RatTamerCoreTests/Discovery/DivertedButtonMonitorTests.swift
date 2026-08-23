import XCTest
@testable import RatTamerCore

final class DivertedButtonMonitorTests: XCTestCase {
    private func event(_ feature: UInt8, device: UInt8 = 1, _ cids: [UInt16]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 12)
        bytes[0] = HIDPP.reportIDLong
        bytes[1] = device
        bytes[2] = feature
        bytes[3] = 0x00
        for (i, cid) in cids.enumerated() where i < 4 {
            bytes[4 + i * 2] = UInt8(cid >> 8)
            bytes[5 + i * 2] = UInt8(cid & 0xFF)
        }
        return bytes
    }

    func testPressThenReleaseFiresBothEvents() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A)
        var pressed: [UInt16] = []
        var released: [UInt16] = []
        monitor.onControlPressed = { pressed.append($0) }
        monitor.onControlReleased = { released.append($0) }
        _ = monitor.feed(event(0x0A, [0x00C4]))
        XCTAssertEqual(pressed, [0x00C4])
        _ = monitor.feed(event(0x0A, []))
        XCTAssertEqual(released, [0x00C4])
        XCTAssertEqual(monitor.pressed, [])
    }

    func testHoldSendsSinglePress() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A)
        var presses = 0
        monitor.onControlPressed = { _ in presses += 1 }
        _ = monitor.feed(event(0x0A, [0x00C4]))
        _ = monitor.feed(event(0x0A, [0x00C4]))
        XCTAssertEqual(presses, 1)
    }

    func testTwoButtonsIndependent() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A)
        var pressed: [UInt16] = []
        var released: [UInt16] = []
        monitor.onControlPressed = { pressed.append($0) }
        monitor.onControlReleased = { released.append($0) }
        _ = monitor.feed(event(0x0A, [0x00C4, 0x0053]))
        XCTAssertEqual(pressed, [0x00C4, 0x0053])
        _ = monitor.feed(event(0x0A, [0x0053]))
        XCTAssertEqual(released, [0x00C4])
        XCTAssertEqual(pressed, [0x00C4, 0x0053])
    }

    func testIgnoresUnrelatedReports() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A)
        XCTAssertFalse(monitor.feed([0x02, 0x01, 0x00, 0x00]))
        XCTAssertFalse(monitor.feed(event(0x0B, [0x00C4])))
        XCTAssertFalse(monitor.feed(event(0x0A, device: 2, [0x00C4])))
        XCTAssertFalse(monitor.feed([0x11, 0x01, 0x0A, 0x00, 0x00]))
    }

    func testRawXYFiresCallback() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A)
        var deltas: [(Int16, Int16)] = []
        monitor.onRawXY = { deltas.append(($0, $1)) }
        let bytes: [UInt8] = [0x11, 0x01, 0x0A, 0x10, 0x01, 0x2C, 0xFF, 0x38, 0, 0, 0, 0]
        XCTAssertTrue(monitor.feed(bytes))
        XCTAssertEqual(deltas.count, 1)
        XCTAssertEqual(deltas[0].0, 300)
        XCTAssertEqual(deltas[0].1, -200)
    }

    func testRawXYDoesNotTriggerPress() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A)
        var presses = 0
        monitor.onControlPressed = { _ in presses += 1 }
        let bytes: [UInt8] = [0x11, 0x01, 0x0A, 0x10, 0x01, 0x2C, 0xFF, 0x38, 0, 0, 0, 0]
        _ = monitor.feed(bytes)
        XCTAssertEqual(presses, 0)
        XCTAssertEqual(monitor.pressed, [])
    }

    func testWheelMovementRoutesToCallback() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A,
                                            wheelFeatureIndex: 0x0E)
        var movements: [WheelMovement] = []
        monitor.onWheelMovement = { movements.append($0) }
        // 11 01 0E 00 13 00 2C -> periods 3, resolution 1, deltaV 44
        let bytes: [UInt8] = [0x11, 0x01, 0x0E, 0x00, 0x13, 0x00, 0x2C, 0, 0, 0, 0, 0]
        XCTAssertTrue(monitor.feed(bytes))
        XCTAssertEqual(movements.count, 1)
        XCTAssertEqual(movements[0].deltaV, 44)
        XCTAssertEqual(movements[0].periods, 3)
        XCTAssertEqual(movements[0].resolution, true)
    }

    func testWheelReportDoesNotTriggerPress() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A,
                                            wheelFeatureIndex: 0x0E)
        var presses = 0
        monitor.onControlPressed = { _ in presses += 1 }
        let bytes: [UInt8] = [0x11, 0x01, 0x0E, 0x00, 0x01, 0x00, 0x2C, 0, 0, 0, 0, 0]
        XCTAssertTrue(monitor.feed(bytes))
        XCTAssertEqual(presses, 0)
        XCTAssertEqual(monitor.pressed, [])
    }

    func testWheelRoutingIgnoredWithoutWheelFeatureIndex() {
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: 0x0A)
        var movements = 0
        monitor.onWheelMovement = { _ in movements += 1 }
        let bytes: [UInt8] = [0x11, 0x01, 0x0E, 0x00, 0x01, 0x00, 0x2C, 0, 0, 0, 0, 0]
        XCTAssertFalse(monitor.feed(bytes))
        XCTAssertEqual(movements, 0)
    }
}

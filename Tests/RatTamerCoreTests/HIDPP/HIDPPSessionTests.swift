import XCTest
@testable import RatTamerCore

final class HIDPPSessionTests: XCTestCase {
    func testSendShortWritesShortPacket() throws {
        let mock = MockHIDDevice()
        let session = HIDPPSession(device: mock)
        try session.sendShort(deviceIndex: 1, featureIndex: 8, functionID: 0, params: [0x1B, 0x04, 0x00])
        XCTAssertEqual(mock.writeLog, [[0x10, 0x01, 0x08, 0x01, 0x1B, 0x04, 0x00]])
    }

    func testGetFeatureIndexReturnsValue() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [
            [0x10, 0x01, 0x00, 0x01, 0x08]
        ]
        let session = HIDPPSession(device: mock)
        let fi = try session.getFeatureIndex(featureID: 0x1B04, deviceIndex: 1)
        XCTAssertEqual(fi, 0x08)
    }

    func testGetFeatureIndexReturnsNilWhenRootIsZero() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x10, 0x01, 0x00, 0x01, 0x00]]
        let session = HIDPPSession(device: mock)
        let fi = try session.getFeatureIndex(featureID: 0x1B04, deviceIndex: 1)
        XCTAssertNil(fi)
    }

    func testGetFeatureIndexReturnsNilOnNoResponse() throws {
        let mock = MockHIDDevice()
        let session = HIDPPSession(device: mock)
        let fi = try session.getFeatureIndex(featureID: 0x1B04, deviceIndex: 1)
        XCTAssertNil(fi)
    }

    func testGetFeatureIndexRetriesWhenFirstResponseIsSlow() throws {
        let mock = MockHIDDevice()
        var writes = 0
        mock.onWrite = { _ in
            writes += 1
            return writes == 2 ? [0x11, 0x01, 0x00, 0x01, 0x0A] : nil
        }
        let session = HIDPPSession(device: mock)
        let fi = try session.getFeatureIndex(featureID: 0x1B04, deviceIndex: 1)
        XCTAssertEqual(fi, 0x0A)
        XCTAssertEqual(mock.writeLog.count, 2)
    }

    func testGetFeatureIndexSkipsUnrelatedResponses() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [
            [0x10, 0x01, 0x00, 0x09, 0x08],
            [0x10, 0x01, 0x00, 0x01, 0x08]
        ]
        let session = HIDPPSession(device: mock, softwareID: 1)
        let fi = try session.getFeatureIndex(featureID: 0x1B04, deviceIndex: 1)
        XCTAssertEqual(fi, 0x08)
    }

    func testPingReturnsTrueWhenDeviceAnswers() throws {
        let mock = MockHIDDevice()
        mock.onWrite = { bytes in
            bytes[1] == 3 ? [0x10, 0x03, 0x00, 0x01, 0x00] : nil
        }
        let session = HIDPPSession(device: mock)
        let answered = try session.ping(deviceIndex: 3)
        XCTAssertTrue(answered)
    }

    func testPingAcceptsLongResponseFromReceiver() throws {
        // Real Unifying receivers answer a short ping with a LONG root reply:
        // reportID 0x11, devIndex, feature 0x00 (root), function|swID, params.
        let mock = MockHIDDevice()
        mock.onWrite = { _ in
            [0x11, 0x01, 0x00, 0x01, 0x00, 0x00, 0x01,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
        }
        let session = HIDPPSession(device: mock)
        let answered = try session.ping(deviceIndex: 1)
        XCTAssertTrue(answered)
    }

    func testPingReturnsFalseWhenNoAnswer() throws {
        let mock = MockHIDDevice()
        let session = HIDPPSession(device: mock)
        let answered = try session.ping(deviceIndex: 3)
        XCTAssertFalse(answered)
    }

    func testPingSucceedsWhileARequestIsInFlight() throws {
        let mock = MockHIDDevice()
        mock.inFlightRequests = 1
        mock.onWrite = { _ in [0x10, 0x01, 0x00, 0x01, 0x00] }
        let session = HIDPPSession(device: mock)
        let answered = try session.ping(deviceIndex: 1)
        XCTAssertTrue(answered)
    }

    func testPingIgnoresErrorResponse() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [
            [0x10, 0x01, 0x00, 0x8F, 0x09, 0x00, 0x00],   // HID++ error (0x8F) — device not present
        ]
        let session = HIDPPSession(device: mock)
        let answered = try session.ping(deviceIndex: 1)
        XCTAssertFalse(answered)
    }

    func testPingSkipsUnrelatedReportsThenAcceptsRootReply() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [
            [0x11, 0x01, 0x0A, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00],   // unrelated feature reply
            [0x10, 0x01, 0x00, 0x01, 0x00],                            // the real root ping reply
        ]
        let session = HIDPPSession(device: mock)
        let answered = try session.ping(deviceIndex: 1)
        XCTAssertTrue(answered)
    }

    func testRequestWritesLongPacketAndReturnsMatchingResponse() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x31, 0x00, 0xC4, 0x03, 0x00, 0x00]]
        let session = HIDPPSession(device: mock)
        let resp = try session.request(deviceIndex: 1, featureIndex: 0x0A, functionID: 0x03,
                                       params: [0x00, 0xC4, 0x03, 0x00, 0x00])
        XCTAssertEqual(resp, [0x11, 0x01, 0x0A, 0x31, 0x00, 0xC4, 0x03, 0x00, 0x00])
        XCTAssertEqual(mock.writeLog.count, 1)
        XCTAssertEqual(mock.writeLog.first?.count, 20)
        XCTAssertEqual(mock.writeLog.first?.first, 0x11)
    }

    func testRequestSkipsUnrelatedAndNotificationResponses() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [
            [0x11, 0x01, 0x0A, 0x20, 0x00, 0xC4, 0x00, 0x00, 0x00],   // different function
            [0x11, 0x01, 0x0A, 0x00, 0x00, 0xC4, 0x00, 0x00, 0x00],   // notification (function 0)
            [0x11, 0x01, 0x0A, 0x31, 0x00, 0x00, 0x00, 0x00, 0x00],   // the real reply
        ]
        let session = HIDPPSession(device: mock)
        let resp = try session.request(deviceIndex: 1, featureIndex: 0x0A, functionID: 0x03, params: [])
        XCTAssertEqual(resp?[3], 0x31)
    }

    func testRequestAcceptsZeroSwIdEcho() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x0A, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00]]
        let session = HIDPPSession(device: mock)
        let resp = try session.request(deviceIndex: 1, featureIndex: 0x0A, functionID: 0x03, params: [])
        XCTAssertEqual(resp?[3], 0x30)
    }

    func testRequestReturnsNilOnTimeout() throws {
        let mock = MockHIDDevice()
        let session = HIDPPSession(device: mock)
        let resp = try session.request(deviceIndex: 1, featureIndex: 0x0A, functionID: 0x03, timeout: 0.1)
        XCTAssertNil(resp)
    }
}

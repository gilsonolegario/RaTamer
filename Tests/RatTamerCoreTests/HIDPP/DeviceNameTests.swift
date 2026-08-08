import XCTest
@testable import RatTamerCore

final class DeviceNameTests: XCTestCase {
    func testGetNameCountReturnsLength() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x08, 0x00, 0x0A]]
        let service = DeviceName(session: HIDPPSession(device: mock), deviceIndex: 1, featureIndex: 0x08)
        XCTAssertEqual(try service.getNameCount(), 10)
    }

    func testGetNameAssemblesChunks() throws {
        let mock = MockHIDDevice()
        var writes = 0
        mock.onWrite = { _ in
            writes += 1
            if writes == 1 {
                return [0x11, 0x01, 0x08, 0x00, 12]
            }
            return [0x11, 0x01, 0x08, 0x10] + Array("MX Master 3S".utf8)
        }
        let service = DeviceName(session: HIDPPSession(device: mock), deviceIndex: 1, featureIndex: 0x08)
        XCTAssertEqual(try service.getName(), "MX Master 3S")
    }

    func testGetNameMultiChunkUsesByteOffset() throws {
        let mock = MockHIDDevice()
        var writes = 0
        mock.onWrite = { _ in
            writes += 1
            switch writes {
            case 1: return [0x11, 0x01, 0x08, 0x00, 20]
            case 2: return [0x11, 0x01, 0x08, 0x10] + Array("ABCDEFGHIJKLMNOP".utf8)
            default: return [0x11, 0x01, 0x08, 0x10] + Array("QRST".utf8) + [UInt8](repeating: 0, count: 12)
            }
        }
        let service = DeviceName(session: HIDPPSession(device: mock), deviceIndex: 1, featureIndex: 0x08)
        XCTAssertEqual(try service.getName(), "ABCDEFGHIJKLMNOPQRST")
        XCTAssertEqual(Array(mock.writeLog[1].prefix(5)), [0x11, 0x01, 0x08, 0x11, 0x00])
        XCTAssertEqual(Array(mock.writeLog[2].prefix(5)), [0x11, 0x01, 0x08, 0x11, 0x10])
    }

    func testGetNameReturnsNilWhenNoName() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x08, 0x00, 0x00]]
        let service = DeviceName(session: HIDPPSession(device: mock), deviceIndex: 1, featureIndex: 0x08)
        XCTAssertNil(try service.getName())
    }
}

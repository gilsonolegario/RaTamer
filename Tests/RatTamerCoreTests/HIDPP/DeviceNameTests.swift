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

    func testGetNameReturnsNilWhenNoName() throws {
        let mock = MockHIDDevice()
        mock.queuedReads = [[0x11, 0x01, 0x08, 0x00, 0x00]]
        let service = DeviceName(session: HIDPPSession(device: mock), deviceIndex: 1, featureIndex: 0x08)
        XCTAssertNil(try service.getName())
    }
}

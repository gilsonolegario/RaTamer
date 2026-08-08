import XCTest
@testable import RatTamerCore

final class SystemVolumeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SystemVolume.commandRunner = { _ in nil }
    }

    func testCurrentParsesOutputVolume() {
        SystemVolume.commandRunner = { _ in "42\n" }
        XCTAssertEqual(SystemVolume.current(), 42)
    }

    func testCurrentReturnsNilWhenCommandFails() {
        SystemVolume.commandRunner = { _ in nil }
        XCTAssertNil(SystemVolume.current())
    }

    func testSetRunsClampedScript() {
        var ran: String?
        SystemVolume.commandRunner = { ran = $0; return "" }
        SystemVolume.set(105)
        XCTAssertEqual(ran, "set volume output volume 100")
    }

    func testSetRunsScriptWithNegativeClampedToZero() {
        var ran: String?
        SystemVolume.commandRunner = { ran = $0; return "" }
        SystemVolume.set(-5)
        XCTAssertEqual(ran, "set volume output volume 0")
    }

    func testSetRunsScriptWithInRangeValue() {
        var ran: String?
        SystemVolume.commandRunner = { ran = $0; return "" }
        SystemVolume.set(37)
        XCTAssertEqual(ran, "set volume output volume 37")
    }
}

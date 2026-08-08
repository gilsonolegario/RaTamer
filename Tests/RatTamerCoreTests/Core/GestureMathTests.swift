import XCTest
@testable import RatTamerCore
import CoreGraphics

final class GestureMathTests: XCTestCase {
    private let origin = CGPoint(x: 100, y: 100)

    func testBelowLimitIsNil() {
        XCTAssertNil(GestureMath.direction(from: origin, to: CGPoint(x: 120, y: 110), limit: 40))
    }

    func testDominantAxisWins() {
        XCTAssertEqual(GestureMath.direction(from: origin, to: CGPoint(x: 180, y: 105), limit: 40), .right)
        XCTAssertEqual(GestureMath.direction(from: origin, to: CGPoint(x: 20, y: 105), limit: 40), .left)
        XCTAssertEqual(GestureMath.direction(from: origin, to: CGPoint(x: 105, y: 30), limit: 40), .down)
        XCTAssertEqual(GestureMath.direction(from: origin, to: CGPoint(x: 105, y: 180), limit: 40), .up)
    }

    func testScreenCoordinatesYFlipped() {
        XCTAssertEqual(GestureMath.direction(from: origin, to: CGPoint(x: 105, y: 160), limit: 40), .up)
    }

    func testDeltaBelowLimitIsNil() {
        XCTAssertNil(GestureMath.direction(dx: 20, dy: 10, limit: 40))
    }

    func testDeltaDominantAxisWins() {
        XCTAssertEqual(GestureMath.direction(dx: 180, dy: 5, limit: 40), .right)
        XCTAssertEqual(GestureMath.direction(dx: -180, dy: 5, limit: 40), .left)
        XCTAssertEqual(GestureMath.direction(dx: 5, dy: -160, limit: 40), .down)
        XCTAssertEqual(GestureMath.direction(dx: 5, dy: 160, limit: 40), .up)
    }
}

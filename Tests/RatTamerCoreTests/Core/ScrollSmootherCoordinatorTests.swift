import XCTest
@testable import RatTamerCore

final class ScrollSmootherCoordinatorTests: XCTestCase {
    func testSetParametersAppliesLive() {
        let now = Date()
        var posted: [Double] = []
        let exp = expectation(description: "posted")
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: false,
                                                        invert: false))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother,
                                                    now: { now },
                                                    poster: { posted.append($0); exp.fulfill() })
        coordinator.setParameters(.init(multiplier: 15,
                                        momentumEnabled: false,
                                        invert: false,
                                        pixelsPerNotch: 20))
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(posted.first ?? 0, 20, accuracy: 0.0001)
    }

    func testSetParametersEnablesMomentumDecay() {
        let now = Date()
        let fed = expectation(description: "fed")
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: false,
                                                        invert: false))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother,
                                                    now: { now },
                                                    poster: { _ in fed.fulfill() })
        coordinator.setParameters(.init(multiplier: 15,
                                        momentumEnabled: true,
                                        invert: false,
                                        momentumDecay: 0.5,
                                        pixelsPerNotch: 20))
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        wait(for: [fed], timeout: 1)
        let t = Date(timeIntervalSince1970: now.timeIntervalSince1970 + 0.2)
        XCTAssertEqual(smoother.tick(at: t), 20, accuracy: 0.0001)
        XCTAssertEqual(smoother.tick(at: t + 1.0 / 120.0), 10, accuracy: 0.0001)
    }

    func testStopResetsSmootherState() {
        let now = Date()
        let exp = expectation(description: "stopped")
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: true,
                                                        invert: false))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother,
                                                    now: { now },
                                                    poster: { _ in })
        _ = smoother.feed(WheelMovement(deltaV: 15, periods: 1, resolution: true), at: now)
        coordinator.stop()
        // After reset, momentum is gone: tick after the feed gap returns 0.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let out = smoother.tick(at: Date(timeIntervalSince1970: now.timeIntervalSince1970 + 0.2))
            XCTAssertEqual(out, 0, accuracy: 0.0001)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }
}

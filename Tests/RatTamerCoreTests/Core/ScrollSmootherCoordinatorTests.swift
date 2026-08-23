import XCTest
@testable import RatTamerCore

final class ScrollSmootherCoordinatorTests: XCTestCase {
    private func waitUntil(_ condition: () -> Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return condition()
    }

    func testTimerStartsOnFeedAndStopsWhenIdle() {
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: true,
                                                        invert: false,
                                                        pixelsPerNotch: 20))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother, poster: { _ in })
        coordinator.start()
        XCTAssertFalse(coordinator.isTicking)
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        XCTAssertTrue(waitUntil({ coordinator.isTicking }, timeout: 1.0))
        XCTAssertTrue(waitUntil({ !coordinator.isTicking }, timeout: 2.0))
    }

    func testPassthroughNeverStartsTimer() {
        let coordinator = ScrollSmootherCoordinator(
            smoother: ScrollSmoother(parameters: .init(multiplier: 15,
                                                       momentumEnabled: false,
                                                       invert: false)),
            poster: { _ in })
        coordinator.start()
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        XCTAssertFalse(coordinator.isTicking)
    }

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
        let postedOnce = DispatchSemaphore(value: 0)
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: false,
                                                        invert: false))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother,
                                                    now: { now },
                                                    poster: { _ in postedOnce.signal() })
        coordinator.setParameters(.init(multiplier: 15,
                                        momentumEnabled: true,
                                        invert: false,
                                        momentumDecay: 0.5,
                                        pixelsPerNotch: 20))
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        XCTAssertEqual(postedOnce.wait(timeout: .now() + 1.0), .success)
        let t = Date(timeIntervalSince1970: now.timeIntervalSince1970 + 0.2)
        XCTAssertEqual(coordinator.synchronized { $0.tick(at: t) }, 20, accuracy: 0.0001)
        XCTAssertEqual(coordinator.synchronized { $0.tick(at: t + 1.0 / 120.0) }, 10, accuracy: 0.0001)
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
        _ = coordinator.synchronized { $0.feed(WheelMovement(deltaV: 15, periods: 1, resolution: true), at: now) }
        coordinator.stop()
        // After reset, momentum is gone: tick after the feed gap returns 0.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            let out = coordinator.synchronized { $0.tick(at: Date(timeIntervalSince1970: now.timeIntervalSince1970 + 0.2)) }
            XCTAssertEqual(out, 0, accuracy: 0.0001)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func testOnSampleEmitsRawThenOutputPerFeed() {
        let now = Date()
        var samples: [ScrollSample] = []
        let lock = NSLock()
        let exp = expectation(description: "samples")
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: false,
                                                        invert: false,
                                                        pixelsPerNotch: 20))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother,
                                                    now: { now },
                                                    poster: { _ in })
        coordinator.onSample = { sample in
            lock.lock()
            samples.append(sample)
            lock.unlock()
            if samples.count == 2 { exp.fulfill() }
        }
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        wait(for: [exp], timeout: 1)
        lock.lock()
        let got = samples
        lock.unlock()
        XCTAssertEqual(got.count, 2)
        XCTAssertEqual(got[0].kind, .raw)
        XCTAssertEqual(got[0].value, 20, accuracy: 0.0001)
        XCTAssertEqual(got[1].kind, .output)
        XCTAssertEqual(got[1].value, 20, accuracy: 0.0001)
    }

    func testOnSampleEmitsOutputOnEveryTick() {
        var samples: [ScrollSample] = []
        let lock = NSLock()
        let smoother = ScrollSmoother(parameters: .init(multiplier: 15,
                                                        momentumEnabled: true,
                                                        invert: false,
                                                        momentumDecay: 0.5,
                                                        pixelsPerNotch: 20))
        let coordinator = ScrollSmootherCoordinator(smoother: smoother, poster: { _ in })
        coordinator.onSample = { sample in
            lock.lock()
            samples.append(sample)
            lock.unlock()
        }
        coordinator.start()
        coordinator.onWheelMovement(WheelMovement(deltaV: 15, periods: 1, resolution: true))
        let gotEnough = waitUntil({
            lock.lock()
            let n = samples.count
            lock.unlock()
            return n >= 4
        }, timeout: 2.0)
        coordinator.stop()
        XCTAssertTrue(gotEnough)
        lock.lock()
        let got = samples
        lock.unlock()
        XCTAssertEqual(got.first?.kind, .raw)
        XCTAssertTrue(got.dropFirst().allSatisfy { $0.kind == .output })
    }
}

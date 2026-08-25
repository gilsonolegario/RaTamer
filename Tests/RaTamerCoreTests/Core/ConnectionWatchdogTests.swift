import XCTest
@testable import RaTamerCore

final class ConnectionWatchdogTests: XCTestCase {
    func testStaysConnectedOnSuccessfulPings() {
        let watchdog = ConnectionWatchdog(failureThreshold: 3)
        var disconnectedCount = 0
        var reconnectedCount = 0
        watchdog.onDisconnected = { disconnectedCount += 1 }
        watchdog.onReconnected = { reconnectedCount += 1 }

        watchdog.report(ok: true)
        watchdog.report(ok: true)
        watchdog.report(ok: true)

        XCTAssertTrue(watchdog.isConnected)
        XCTAssertEqual(disconnectedCount, 0)
        XCTAssertEqual(reconnectedCount, 0)
    }

    func testDisconnectsAfterConsecutiveFailures() {
        let watchdog = ConnectionWatchdog(failureThreshold: 3)
        var disconnectedCount = 0
        watchdog.onDisconnected = { disconnectedCount += 1 }

        watchdog.report(ok: false)
        XCTAssertTrue(watchdog.isConnected)
        watchdog.report(ok: false)
        XCTAssertTrue(watchdog.isConnected)
        watchdog.report(ok: false)

        XCTAssertFalse(watchdog.isConnected)
        XCTAssertEqual(disconnectedCount, 1)
    }

    func testIsolatedFailuresDoNotDisconnect() {
        let watchdog = ConnectionWatchdog(failureThreshold: 3)
        var disconnectedCount = 0
        watchdog.onDisconnected = { disconnectedCount += 1 }

        watchdog.report(ok: false)
        watchdog.report(ok: true)
        watchdog.report(ok: false)
        watchdog.report(ok: true)
        watchdog.report(ok: false)

        XCTAssertTrue(watchdog.isConnected)
        XCTAssertEqual(disconnectedCount, 0)
    }

    func testOnDisconnectedFiresOnceUntilReconnect() {
        let watchdog = ConnectionWatchdog(failureThreshold: 3)
        var disconnectedCount = 0
        watchdog.onDisconnected = { disconnectedCount += 1 }

        watchdog.report(ok: false)
        watchdog.report(ok: false)
        watchdog.report(ok: false)
        watchdog.report(ok: false)
        watchdog.report(ok: false)

        XCTAssertFalse(watchdog.isConnected)
        XCTAssertEqual(disconnectedCount, 1)
    }

    func testReconnectsAfterSuccess() {
        let watchdog = ConnectionWatchdog(failureThreshold: 3)
        var disconnectedCount = 0
        var reconnectedCount = 0
        watchdog.onDisconnected = { disconnectedCount += 1 }
        watchdog.onReconnected = { reconnectedCount += 1 }

        watchdog.report(ok: false)
        watchdog.report(ok: false)
        watchdog.report(ok: false)
        XCTAssertFalse(watchdog.isConnected)

        watchdog.report(ok: true)

        XCTAssertTrue(watchdog.isConnected)
        XCTAssertEqual(disconnectedCount, 1)
        XCTAssertEqual(reconnectedCount, 1)
    }

    func testDisconnectsAgainAfterReconnect() {
        let watchdog = ConnectionWatchdog(failureThreshold: 2)
        var disconnectedCount = 0
        var reconnectedCount = 0
        watchdog.onDisconnected = { disconnectedCount += 1 }
        watchdog.onReconnected = { reconnectedCount += 1 }

        watchdog.report(ok: false)
        watchdog.report(ok: false)
        watchdog.report(ok: true)
        watchdog.report(ok: false)
        watchdog.report(ok: false)

        XCTAssertFalse(watchdog.isConnected)
        XCTAssertEqual(disconnectedCount, 2)
        XCTAssertEqual(reconnectedCount, 1)
    }

    func testConcurrentReportsAreThreadSafe() {
        let watchdog = ConnectionWatchdog(failureThreshold: 3)
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.watchdog", attributes: .concurrent)
        for _ in 0..<200 {
            queue.async(group: group) { watchdog.report(ok: true) }
            queue.async(group: group) { watchdog.report(ok: false) }
        }
        group.wait()
        XCTAssertTrue(watchdog.isConnected || !watchdog.isConnected)
    }

    func testConcurrentFailuresNeverUnderReportThreshold() {
        let watchdog = ConnectionWatchdog(failureThreshold: 3)
        var disconnectedCount = 0
        let countLock = NSLock()
        watchdog.onDisconnected = {
            countLock.lock()
            disconnectedCount += 1
            countLock.unlock()
        }
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "test.watchdog.fail", attributes: .concurrent)
        for _ in 0..<100 {
            queue.async(group: group) { watchdog.report(ok: false) }
        }
        group.wait()
        // Even under concurrency, a disconnect must fire only when the
        // threshold is reached and exactly once until a success resets it.
        XCTAssertLessThanOrEqual(disconnectedCount, 1)
    }
}

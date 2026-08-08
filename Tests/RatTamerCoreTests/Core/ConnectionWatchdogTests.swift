import XCTest
@testable import RatTamerCore

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
}

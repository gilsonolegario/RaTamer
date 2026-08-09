import XCTest
@testable import RatTamerCore

final class MockVerifier: LicenseVerifying {
    var result: Result<LicenseVerification, Error> = .success(
        LicenseVerification(success: true, uses: 1, purchase: nil)
    )
    var lastKey: String?

    func verify(licenseKey: String) async throws -> LicenseVerification {
        lastKey = licenseKey
        return try result.get()
    }
}

final class ControllableVerifier: LicenseVerifying {
    private let lock = NSLock()
    private var pending: [CheckedContinuation<LicenseVerification, Error>] = []
    private var startedKeys: [String] = []
    private var waiters: [CheckedContinuation<String, Never>] = []

    func verify(licenseKey: String) async throws -> LicenseVerification {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pending.append(continuation)
            if waiters.isEmpty {
                startedKeys.append(licenseKey)
                lock.unlock()
            } else {
                let waiter = waiters.removeFirst()
                lock.unlock()
                waiter.resume(returning: licenseKey)
            }
        }
    }

    func awaitStartedCall() async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            lock.lock()
            if !startedKeys.isEmpty {
                let key = startedKeys.removeFirst()
                lock.unlock()
                continuation.resume(returning: key)
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func complete(at index: Int, with outcome: Result<LicenseVerification, Error>) {
        lock.lock()
        let continuation = pending.remove(at: index)
        lock.unlock()
        continuation.resume(with: outcome)
    }
}

final class LicenseServiceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "rattamer-lic-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        LicenseKeyStore.userDefaults = defaults
    }

    override func tearDown() {
        LicenseKeyStore.userDefaults = .standard
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeService(verifier: any LicenseVerifying) -> LicenseService {
        LicenseService(verifier: verifier, defaults: defaults)
    }

    func testSubmitValidKeyActivatesAndStores() async {
        let verifier = MockVerifier()
        let service = makeService(verifier: verifier)

        let state = await service.submit(key: "GOOD-KEY")

        XCTAssertEqual(state, .active)
        XCTAssertEqual(LicenseKeyStore.load(), "GOOD-KEY")
        XCTAssertEqual(verifier.lastKey, "GOOD-KEY")
        XCTAssertNotNil(defaults.object(forKey: LicenseService.lastValidatedKey) as? Date)
        XCTAssertTrue(service.isPro(.gestures))
        XCTAssertTrue(service.isPro(.smartShift))
        XCTAssertTrue(service.isPro(.runShortcut))
        XCTAssertTrue(service.isPro(.profiles))
    }

    func testSubmitInvalidKeyClearsAndMarksInvalid() async {
        let verifier = MockVerifier()
        verifier.result = .success(LicenseVerification(success: false, uses: 1, purchase: nil))
        let service = makeService(verifier: verifier)

        LicenseKeyStore.save("BAD-KEY")
        let state = await service.submit(key: "BAD-KEY")

        XCTAssertEqual(state, .invalid)
        XCTAssertNil(LicenseKeyStore.load())
        XCTAssertFalse(service.isPro(.gestures))
    }

    func testUnlicensedIsNotPro() {
        let service = makeService(verifier: MockVerifier())
        XCTAssertEqual(service.state, .unlicensed)
        XCTAssertFalse(service.isPro(.gestures))
        XCTAssertFalse(service.isPro(.smartShift))
        XCTAssertFalse(service.isPro(.runShortcut))
        XCTAssertFalse(service.isPro(.profiles))
    }

    func testNetworkFailureWithFreshCacheStaysActive() async {
        let verifier = MockVerifier()
        verifier.result = .failure(URLError(.timedOut))
        let service = makeService(verifier: verifier)

        LicenseKeyStore.save("CACHED-KEY")
        defaults.set(Date().addingTimeInterval(-60), forKey: LicenseService.lastValidatedKey)

        let state = await service.validate()

        XCTAssertEqual(state, .active)
        XCTAssertTrue(service.isPro(.gestures))
    }

    func testNetworkFailureWithStaleCacheBecomesOfflineExpired() async {
        let verifier = MockVerifier()
        verifier.result = .failure(URLError(.timedOut))
        let service = makeService(verifier: verifier)

        LicenseKeyStore.save("STALE-KEY")
        defaults.set(Date().addingTimeInterval(-31 * 24 * 3600), forKey: LicenseService.lastValidatedKey)

        let state = await service.validate()

        XCTAssertEqual(state, .offlineExpired)
        XCTAssertFalse(service.isPro(.gestures))
    }

    func testStartupUsesCachedStateWithoutNetwork() {
        let verifier = MockVerifier()
        LicenseKeyStore.save("KEY")
        defaults.set(Date().addingTimeInterval(-60), forKey: LicenseService.lastValidatedKey)

        let service = makeService(verifier: verifier)

        XCTAssertEqual(service.state, .active)
    }

    func testClearReturnsToUnlicensed() async {
        let verifier = MockVerifier()
        let service = makeService(verifier: verifier)
        _ = await service.submit(key: "GOOD-KEY")

        service.clear()

        XCTAssertEqual(service.state, .unlicensed)
        XCTAssertNil(LicenseKeyStore.load())
        XCTAssertFalse(service.isPro(.gestures))
    }

    func testSubmitBlankKeyChangesNothing() async {
        let verifier = MockVerifier()
        let service = makeService(verifier: verifier)

        let state = await service.submit(key: "   ")

        XCTAssertEqual(state, .unlicensed)
        XCTAssertNil(LicenseKeyStore.load())
        XCTAssertNil(verifier.lastKey)
    }

    func testOnStateChangeFiresOnTransition() async {
        let verifier = MockVerifier()
        let service = makeService(verifier: verifier)
        var states: [LicenseService.State] = []
        service.onStateChange = { states.append($0) }

        _ = await service.submit(key: "GOOD-KEY")

        XCTAssertEqual(states, [.validating, .active])
    }

    func testStaleResultDoesNotOverwriteNewerSubmission() async {
        let verifier = ControllableVerifier()
        let service = makeService(verifier: verifier)

        LicenseKeyStore.save("OLD-KEY")
        let staleTask = Task { await service.validate() }
        let firstKey = await verifier.awaitStartedCall()
        XCTAssertEqual(firstKey, "OLD-KEY")

        let newerTask = Task { await service.submit(key: "NEW-KEY") }
        let secondKey = await verifier.awaitStartedCall()
        XCTAssertEqual(secondKey, "NEW-KEY")

        verifier.complete(at: 1, with: .success(
            LicenseVerification(success: false, uses: 1, purchase: nil)
        ))
        let newerState = await newerTask.value
        XCTAssertEqual(newerState, .invalid)
        XCTAssertNil(LicenseKeyStore.load())

        verifier.complete(at: 0, with: .success(
            LicenseVerification(success: true, uses: 1, purchase: nil)
        ))
        let staleState = await staleTask.value

        XCTAssertEqual(staleState, .invalid)
        XCTAssertNil(LicenseKeyStore.load())
        XCTAssertFalse(service.isPro(.gestures))
    }
}

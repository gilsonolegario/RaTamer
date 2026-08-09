import XCTest
@testable import RatTamerCore

final class LicenseKeyStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "rattamer-keytests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        LicenseKeyStore.userDefaults = defaults
    }

    override func tearDown() {
        LicenseKeyStore.userDefaults = .standard
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadNilWhenEmpty() {
        XCTAssertNil(LicenseKeyStore.load())
    }

    func testSaveThenLoadRoundTrip() {
        LicenseKeyStore.save("ABC-123")
        XCTAssertEqual(LicenseKeyStore.load(), "ABC-123")
    }

    func testClearRemovesKey() {
        LicenseKeyStore.save("ABC-123")
        LicenseKeyStore.clear()
        XCTAssertNil(LicenseKeyStore.load())
    }

    func testProFeatureCases() {
        XCTAssertEqual(ProFeature.allCases, [.gestures, .smartShift, .runShortcut, .profiles])
    }
}

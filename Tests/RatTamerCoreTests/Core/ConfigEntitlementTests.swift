import XCTest
@testable import RatTamerCore

final class ConfigEntitlementTests: XCTestCase {
    private var config: Config!

    override func setUp() {
        super.setUp()
        var c = Config.empty()
        c.setAction(.gesture(.logitechDefault()), forCID: 0x00C3)
        c.setAction(.runShortcut("SS Volume Up"), forCID: 0x0052)
        c.setAction(.shortcut(key: "w", modifiers: ["command"]), forCID: 0x0053)
        c.setThumbWheelAction(.runShortcut("SS Volume Up"), for: .left)
        c.setThumbWheelAction(.gesture(.logitechDefault()), for: .right)
        c.smartShiftMode = .smartshift
        c.smartShiftSensitivity = 32
        c.swapLeftRight = true
        config = c
    }

    func testFreeFeaturesSurviveWithoutEntitlement() {
        let filtered = config.filteringProFeatures { _ in false }
        XCTAssertEqual(filtered.action(forCID: 0x0053),
                       .shortcut(key: "w", modifiers: ["command"]))
        XCTAssertTrue(filtered.swapLeftRight)
    }

    func testStripsGestureActionsWithoutEntitlement() {
        let filtered = config.filteringProFeatures { _ in false }
        XCTAssertEqual(filtered.action(forCID: 0x00C3), .disabled)
        XCTAssertNil(filtered.thumbWheelAction(for: .right))
    }

    func testStripsRunShortcutActionsWithoutEntitlement() {
        let filtered = config.filteringProFeatures { _ in false }
        XCTAssertEqual(filtered.action(forCID: 0x0052), .disabled)
        XCTAssertNil(filtered.thumbWheelAction(for: .left))
    }

    func testStripsSmartShiftWithoutEntitlement() {
        let filtered = config.filteringProFeatures { _ in false }
        XCTAssertNil(filtered.smartShiftMode)
        XCTAssertNil(filtered.smartShiftSensitivity)
    }

    func testFullEntitlementKeepsEverything() {
        let filtered = config.filteringProFeatures { _ in true }
        XCTAssertEqual(filtered.action(forCID: 0x00C3), .gesture(.logitechDefault()))
        XCTAssertEqual(filtered.action(forCID: 0x0052), .runShortcut("SS Volume Up"))
        XCTAssertEqual(filtered.thumbWheelAction(for: .left), .runShortcut("SS Volume Up"))
        XCTAssertEqual(filtered.thumbWheelAction(for: .right), .gesture(.logitechDefault()))
        XCTAssertEqual(filtered.smartShiftMode, .smartshift)
        XCTAssertEqual(filtered.smartShiftSensitivity, 32)
        XCTAssertEqual(filtered, config)
    }

    func testOriginalConfigIsNotMutated() {
        _ = config.filteringProFeatures { _ in false }
        XCTAssertEqual(config.action(forCID: 0x00C3), .gesture(.logitechDefault()))
        XCTAssertEqual(config.smartShiftMode, .smartshift)
    }

    func testStripsSmoothScrollWithoutEntitlement() {
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 75
        let filtered = config.filteringProFeatures { _ in false }
        XCTAssertNil(filtered.smoothScrollEnabled)
        XCTAssertNil(filtered.smoothScrollLevel)
    }

    func testKeepsSmoothScrollWithEntitlement() {
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 30
        let filtered = config.filteringProFeatures { _ in true }
        XCTAssertEqual(filtered.smoothScrollEnabled, true)
        XCTAssertEqual(filtered.smoothScrollLevel, 30)
    }
}

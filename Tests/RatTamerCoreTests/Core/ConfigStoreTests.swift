import XCTest
@testable import RatTamerCore

final class ConfigStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadReturnsEmptyWhenFileMissing() {
        let store = ConfigStore(fileURL: tempDir.appendingPathComponent("nope.json"))
        XCTAssertEqual(store.load(), Config.empty())
    }

    func testSaveThenLoadRoundTrip() throws {
        let url = tempDir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.deviceIndex = 1
        config.buttons["0x00C3"] = .shortcut(key: "w", modifiers: ["command"])
        config.thumbWheelLeft = .system("volumeDownSmall")
        config.thumbWheelRight = .system("volumeUpSmall")
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded, config)
    }

    func testLoadThrowsOnCorruptJSON() {
        let url = tempDir.appendingPathComponent("bad.json")
        try? "{ not json".write(to: url, atomically: true, encoding: .utf8)
        let store = ConfigStore(fileURL: url)
        XCTAssertThrowsError(try store.loadStrict())
    }

    func testLoadBacksUpCorruptFileInsteadOfOverwriting() throws {
        let url = tempDir.appendingPathComponent("corrupt.json")
        try "{ not json".write(to: url, atomically: true, encoding: .utf8)
        let store = ConfigStore(fileURL: url)
        XCTAssertEqual(store.load(), Config.empty())
        // The corrupted original must be preserved, not silently overwritten.
        let backup = try XCTUnwrap(FileManager.default.contents(atPath: url.appendingPathExtension("corrupt").path))
        XCTAssertEqual(String(data: backup, encoding: .utf8), "{ not json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoadsLegacyConfigWithoutDPIFields() throws {
        let url = tempDir.appendingPathComponent("legacy.json")
        try #"""
        {"version":1,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(loaded.deviceIndex, 1)
        XCTAssertNil(loaded.dpiFeatureIndex)
        XCTAssertNil(loaded.dpiDeviceIndex)
        XCTAssertNil(loaded.dpiDownValue)
        XCTAssertNil(loaded.dpiAction)
        XCTAssertEqual(loaded.thumbWheelLeft, .system("volumeDownSmall"))
        XCTAssertEqual(loaded.thumbWheelRight, .system("volumeUpSmall"))
    }

    func testLegacyDpiActionMigratesToSmartShiftButton() throws {
        let url = tempDir.appendingPathComponent("legacy-dpi.json")
        try #"""
        {"version":1,"deviceIndex":1,"buttons":{},"dpiFeatureIndex":14,
         "dpiDeviceIndex":1,"dpiDownValue":0,"dpiAction":{"action":"shortcut","key":"w","modifiers":["command"]}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(loaded.action(forCID: 0x00C4),
                       .shortcut(key: "w", modifiers: ["command"]))
        XCTAssertNil(loaded.dpiAction)
    }

    func testLegacyLearnedButtonDefaultsToCmdWWhenNoAction() throws {
        let url = tempDir.appendingPathComponent("legacy-learned.json")
        try #"""
        {"version":1,"deviceIndex":1,"buttons":{},"dpiFeatureIndex":14,
         "dpiDeviceIndex":1,"dpiDownValue":0}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.version, 2)
        XCTAssertEqual(loaded.action(forCID: 0x00C4),
                       .shortcut(key: "w", modifiers: ["command"]))
    }

    func testActionAndSetActionRoundTrip() {
        var config = Config.empty()
        XCTAssertNil(config.action(forCID: 0x0052))
        config.setAction(.system("missionControl"), forCID: 0x0052)
        XCTAssertEqual(config.action(forCID: 0x0052), .system("missionControl"))
        XCTAssertNil(config.action(forCID: 0x0053))
        XCTAssertEqual(config.cidKey(0x00C4), "0x00C4")
    }

    func testMigrateLegacySetsThumbWheelDefaultsWhenAbsent() {
        var config = Config(version: 1, deviceIndex: 1, buttons: ["0x0052": .disabled])
        XCTAssertTrue(config.migrateLegacy())
        XCTAssertEqual(config.thumbWheelLeft, .system("volumeDownSmall"))
        XCTAssertEqual(config.thumbWheelRight, .system("volumeUpSmall"))
        XCTAssertEqual(config.version, 2)
    }

    func testMigrateLegacyPreservesThumbWheelWhenConfigured() {
        var config = Config(version: 2, deviceIndex: 1, buttons: [:])
        config.thumbWheelLeft = .disabled
        XCTAssertFalse(config.migrateLegacy())
        XCTAssertEqual(config.thumbWheelLeft, .disabled)
        XCTAssertNil(config.thumbWheelRight)
    }

    func testGestureConfigDecodesLegacyStrings() throws {
        let json = #"""
        {"action":"gesture","gesture":{"click":"missionControl","up":"showDesktop",
         "down":"previousSpace","left":"nextSpace","right":"missionControl"}}
        """#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let action = try JSONDecoder().decode(ButtonAction.self, from: data)
        guard case .gesture(let g) = action else { return XCTFail("expected gesture") }
        XCTAssertEqual(g.click, .system("missionControl"))
        XCTAssertEqual(g.up, .system("showDesktop"))
        XCTAssertEqual(g.down, .system("previousSpace"))
        XCTAssertEqual(g.left, .system("nextSpace"))
        XCTAssertEqual(g.right, .system("missionControl"))
    }

    func testGestureConfigDecodesButtonActionsAndRoundTrips() throws {
        var g = GestureConfig.logitechDefault()
        g.up = .shortcut(key: "w", modifiers: ["command"])
        let data = try JSONEncoder().encode(ButtonAction.gesture(g))
        let back = try JSONDecoder().decode(ButtonAction.self, from: data)
        XCTAssertEqual(back, .gesture(g))
    }

    func testLoadsConfigWithoutSwapLeftRightDefaultsToFalse() throws {
        let url = tempDir.appendingPathComponent("no-swap.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertFalse(loaded.swapLeftRight)
    }

    func testSwapLeftRightRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("swap.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.swapLeftRight = true
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertTrue(loaded.swapLeftRight)
    }

    func testRequiresDivert() {
        XCTAssertTrue(ButtonAction.system("missionControl").requiresDivert)
        XCTAssertTrue(ButtonAction.shortcut(key: "w", modifiers: ["command"]).requiresDivert)
        XCTAssertFalse(ButtonAction.disabled.requiresDivert)
    }

    func testSmartShiftModeDecodesNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-smartshift.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertNil(loaded.smartShiftMode)
    }

    func testSmartShiftModeRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("smartshift.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.smartShiftMode = .smartshift
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.smartShiftMode, .smartshift)
    }

    func testSmartShiftModeMapping() {
        XCTAssertEqual(SmartShiftMode.freespin.wheelMode, 1)
        XCTAssertEqual(SmartShiftMode.ratcheted.wheelMode, 2)
        XCTAssertEqual(SmartShiftMode.ratcheted.autoDisengage, 0xFF)
        XCTAssertEqual(SmartShiftMode.smartshift.wheelMode, 2)
        XCTAssertEqual(SmartShiftMode.smartshift.autoDisengage, 0x00)
    }

    func testSmartShiftSensitivityDecodesNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-sensitivity.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertNil(loaded.smartShiftSensitivity)
    }

    func testSmartShiftSensitivityRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("sensitivity.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.smartShiftSensitivity = 42
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.smartShiftSensitivity, 42)
    }

    func testDpiValueDecodesNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-dpi.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertNil(loaded.dpiValue)
    }

    func testDpiValueRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("dpi.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.dpiValue = 1600
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.dpiValue, 1600)
    }

    func testInvertScrollDirectionDecodesNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-invert.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertNil(loaded.invertScrollDirection)
    }

    func testInvertScrollDirectionRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("invert.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.invertScrollDirection = true
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.invertScrollDirection, true)
    }

    func testThumbWheelFieldsRoundTripThroughStore() throws {
        let url = tempDir.appendingPathComponent("thumbwheel.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.setThumbWheelAction(.system("volumeDownSmall"), for: .left)
        config.setThumbWheelAction(.shortcut(key: "w", modifiers: ["command"]), for: .right)
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.thumbWheelAction(for: .left), .system("volumeDownSmall"))
        XCTAssertEqual(loaded.thumbWheelAction(for: .right), .shortcut(key: "w", modifiers: ["command"]))
    }

    func testThumbWheelFieldsDecodeNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-thumbwheel.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{},"thumbWheelLeft":{"action":"disabled"}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.thumbWheelLeft, .disabled)
        XCTAssertNil(loaded.thumbWheelRight)
    }

    func testRunShortcutActionDecodesFromJSON() throws {
        let data = try XCTUnwrap(#"{"action":"runShortcut","shortcut":"SS Volume Up"}"#.data(using: .utf8))
        let action = try JSONDecoder().decode(ButtonAction.self, from: data)
        XCTAssertEqual(action, .runShortcut("SS Volume Up"))
    }

    func testRunShortcutActionRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("runshortcut.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.setThumbWheelAction(.runShortcut("SS Volume Up"), for: .left)
        config.setAction(.runShortcut("SS Volume Down"), forCID: 0x0052)
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.thumbWheelAction(for: .left), .runShortcut("SS Volume Up"))
        XCTAssertEqual(loaded.action(forCID: 0x0052), .runShortcut("SS Volume Down"))
    }

    func testCycleDPIActionRoundTrips() throws {
        let data = try JSONEncoder().encode(ButtonAction.cycleDPI)
        let back = try JSONDecoder().decode(ButtonAction.self, from: data)
        XCTAssertEqual(back, .cycleDPI)
    }

    func testCycleDPIActionDecodesFromJSON() throws {
        let data = try XCTUnwrap(#"{"action":"cycleDPI"}"#.data(using: .utf8))
        let action = try JSONDecoder().decode(ButtonAction.self, from: data)
        XCTAssertEqual(action, .cycleDPI)
    }

    func testCycleDPIActionRequiresDivert() {
        XCTAssertTrue(ButtonAction.cycleDPI.requiresDivert)
    }

    func testDPICycleValuesDecodeNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-dpi-cycle.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertNil(loaded.dpiCycleValues)
    }

    func testDPICycleValuesRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("dpi-cycle.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.dpiCycleValues = [1000, 1600, 2000, 4000]
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.dpiCycleValues, [1000, 1600, 2000, 4000])
    }

    func testMenuBarOnlyDecodesNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-menubar.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertNil(loaded.menuBarOnly)
    }

    func testProtectTerminalsDefaultsOnWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-protect.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{}}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertNil(loaded.protectTerminals, "stored value should be nil until the user changes it")
    }

    func testProtectTerminalsRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("protect.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.protectTerminals = false
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.protectTerminals, false)
    }

    func testMenuBarOnlyRoundTripsThroughStore() throws {
        let url = tempDir.appendingPathComponent("menubar.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.menuBarOnly = true
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.menuBarOnly, true)
    }

    func testSmoothScrollFieldsRoundTrip() throws {
        let url = tempDir.appendingPathComponent("smooth.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 75
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.smoothScrollEnabled, true)
        XCTAssertEqual(loaded.smoothScrollLevel, 75)
    }

    func testLegacySmoothScrollMomentumConfigDecodes() throws {
        let json = """
        {"version":1,"smoothScrollEnabled":true,"smoothScrollMomentum":true}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(config.smoothScrollEnabled, true)
        XCTAssertNil(config.smoothScrollLevel)
    }

    func testLegacySmoothScrollMomentumFalseConfigDecodes() throws {
        let json = """
        {"version":1,"smoothScrollEnabled":true,"smoothScrollMomentum":false}
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(config.smoothScrollEnabled, true)
        XCTAssertNil(config.smoothScrollLevel)
    }

    func testSmoothScrollAdvancedRoundTrips() throws {
        let url = tempDir.appendingPathComponent("smooth-advanced.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.smoothScrollEnabled = true
        config.smoothScrollLevel = 50
        config.thumbWheelLeft = .system("volumeDownSmall")
        config.thumbWheelRight = .system("volumeUpSmall")
        config.smoothScrollAdvanced = ScrollSmoother.Parameters(
            multiplier: 8, momentumEnabled: true, invert: false,
            maxBoost: 4.2, momentumDecay: 0.91, pixelsPerNotch: 132,
            accelerationWindow: 0.05, feedGapTimeout: 0.09,
            momentumStopThreshold: 0.3, bounceWindow: 0.1,
            bounceRatio: 0.8, bounceDamping: 0.6,
            reversalConfirmation: 3, directionThreshold: 1.5,
            smoothingEnabled: true, smoothFraction: 0.13,
            glideStopThreshold: 0.5)
        try store.save(config)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded, config)
        XCTAssertEqual(loaded.smoothScrollAdvanced?.maxBoost, 4.2)
        XCTAssertEqual(loaded.smoothScrollAdvanced?.reversalConfirmation, 3)
    }

    func testSmoothScrollAdvancedDecodesNilWhenAbsent() throws {
        let url = tempDir.appendingPathComponent("no-smooth-advanced.json")
        try #"""
        {"version":2,"deviceIndex":1,"buttons":{},"smoothScrollEnabled":true,"smoothScrollLevel":50}
        """#.write(to: url, atomically: true, encoding: .utf8)
        let loaded = ConfigStore(fileURL: url).load()
        XCTAssertEqual(loaded.smoothScrollEnabled, true)
        XCTAssertEqual(loaded.smoothScrollLevel, 50)
        XCTAssertNil(loaded.smoothScrollAdvanced)
    }

    func testLoadReloadsWhenFileChangesExternally() throws {
        let url = tempDir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.dpiValue = 1000
        try store.save(config)
        XCTAssertEqual(store.load().dpiValue, 1000)
        var edited = Config.empty()
        edited.dpiValue = 4000
        let editedData = try JSONEncoder().encode(edited)
        try editedData.write(to: url, options: .atomic)
        XCTAssertEqual(store.load().dpiValue, 4000)
    }

    func testLoadReturnsEmptyAfterFileDeleted() throws {
        let url = tempDir.appendingPathComponent("config.json")
        let store = ConfigStore(fileURL: url)
        var config = Config.empty()
        config.dpiValue = 1000
        try store.save(config)
        XCTAssertEqual(store.load().dpiValue, 1000)
        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(store.load(), Config.empty())
    }
}

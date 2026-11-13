import XCTest
@testable import RaTamerCore
import Carbon
import CoreGraphics

final class MockEventPoster: EventPoster {
    var keys: [(keyCode: UInt16, down: Bool, flags: CGEventFlags)] = []
    var clicks: [UInt8] = []

    func postKey(_ keyCode: UInt16, down: Bool, flags: CGEventFlags) {
        keys.append((keyCode, down, flags))
    }

    func postMouseClick(button: UInt8) {
        clicks.append(button)
    }
}

final class MockVolumeController: VolumeControlling {
    var adjustments: [VolumeAdjustment] = []
    var error: Error?

    func apply(_ adjustment: VolumeAdjustment) throws {
        if let error { throw error }
        adjustments.append(adjustment)
    }
}

final class MockShortcutRunner: ShortcutRunner {
    var names: [String] = []
    var error: Error?

    func run(_ name: String) throws {
        if let error { throw error }
        names.append(name)
    }
}

final class ActionEngineTests: XCTestCase {
    func testShortcutPostsKeyDownAndUp() throws {
        let poster = MockEventPoster()
        let engine = ActionEngine(poster: poster)
        try engine.execute(.shortcut(key: "w", modifiers: ["command"]))
        XCTAssertEqual(poster.keys.count, 2)
        XCTAssertEqual(poster.keys[0].keyCode, 0x0D)
        XCTAssertTrue(poster.keys[0].down)
        XCTAssertFalse(poster.keys[1].down)
        XCTAssertEqual(poster.keys[0].flags, .maskCommand)
    }

    func testSystemActionMissionControlPostsCtrlUp() throws {
        let poster = MockEventPoster()
        let engine = ActionEngine(poster: poster)
        try engine.execute(.system("missionControl"))
        XCTAssertEqual(poster.keys.count, 2)
        XCTAssertEqual(poster.keys[0].keyCode, 0x7E)
        XCTAssertTrue(poster.keys[0].down)
        XCTAssertFalse(poster.keys[1].down)
        XCTAssertEqual(poster.keys[0].flags, .maskControl)
    }

    func testClickPostsOnce() throws {
        let poster = MockEventPoster()
        let engine = ActionEngine(poster: poster)
        try engine.execute(.click(button: 3))
        XCTAssertEqual(poster.clicks, [3])
    }

    func testUnsupportedKeyThrows() {
        let engine = ActionEngine(poster: MockEventPoster())
        XCTAssertThrowsError(try engine.execute(.shortcut(key: "Ω", modifiers: [])))
    }

    func testDisabledDoesNothing() throws {
        let poster = MockEventPoster()
        let engine = ActionEngine(poster: poster)
        try engine.execute(.disabled)
        XCTAssertTrue(poster.keys.isEmpty)
    }

    func testCycleDPIDoesNothing() throws {
        let poster = MockEventPoster()
        let engine = ActionEngine(poster: poster)
        try engine.execute(.cycleDPI)
        XCTAssertTrue(poster.keys.isEmpty)
        XCTAssertTrue(poster.clicks.isEmpty)
    }

    func testKeyCodeMap() {
        XCTAssertEqual(ActionEngine.keyCode(for: "w"), 0x0D)
        XCTAssertEqual(ActionEngine.keyCode(for: "tab"), 0x30)
        XCTAssertNil(ActionEngine.keyCode(for: "Ω"))
    }

    func testKeyCodeFromBackgroundThread() {
        let expectation = expectation(description: "keyCode from background thread")
        var result: UInt16?
        DispatchQueue.global().async {
            result = ActionEngine.keyCode(for: "w")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, 0x0D)
    }

    func testKeyCodeDoesNotDeadlockWhenMainThreadIsBlocked() {
        let mainBlocked = DispatchSemaphore(value: 0)
        let done = DispatchSemaphore(value: 0)
        var result: UInt16?

        DispatchQueue.main.async {
            mainBlocked.wait()
        }
        Thread.sleep(forTimeInterval: 0.1)

        DispatchQueue.global().async {
            result = ActionEngine.keyCode(for: "w")
            done.signal()
        }

        let outcome = done.wait(timeout: .now() + 2)
        mainBlocked.signal()
        XCTAssertEqual(outcome, .success, "keyCode blocked waiting on the main thread")
        XCTAssertEqual(result, 0x0D)
    }

    func testKeyboardLayoutChangeInvalidatesCache() {
        ActionEngine.warmKeyCodeCache()
        XCTAssertNotNil(ActionEngine.layoutCache, "warm up should populate the layout cache")
        ActionEngine.handleKeyboardLayoutChanged()
        XCTAssertNil(ActionEngine.layoutCache, "layout change should invalidate the cache")
        XCTAssertEqual(ActionEngine.keyCode(for: "w"), 0x0D,
                       "cache should refill on the next lookup")
        XCTAssertNotNil(ActionEngine.layoutCache)
    }

    func testPunctuationKeyCodesMatchCurrentLayout() throws {
        let src = try XCTUnwrap(TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue())
        let raw = try XCTUnwrap(TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData))
        let layout = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let layoutPtr = (layout as NSData).bytes.assumingMemoryBound(to: UCKeyboardLayout.self)

        func chars(for vk: UInt16) -> String {
            var dead: UInt32 = 0
            var outLen = 0
            var out = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layoutPtr, vk, 0, 0,
                                        UInt32(kUCKeyTranslateNoDeadKeysBit), 0,
                                        &dead, 8, &outLen, &out)
            guard status == noErr else { return "" }
            return String(utf16CodeUnits: out, count: Int(outLen))
        }

        for char in ["[", "]"] {
            let vk = try XCTUnwrap(ActionEngine.keyCode(for: char))
            XCTAssertEqual(chars(for: vk), char,
                           "keyCode 0x\(String(format: "%02X", vk)) should produce \(char)")
        }

        for char in ["[", "]", "\\", "`", ";", "'", "=", "-", ",", ".", "/", "~"] {
            if let vk = ActionEngine.keyCode(for: char) {
                XCTAssertEqual(chars(for: vk), char,
                               "keyCode 0x\(String(format: "%02X", vk)) should produce \(char)")
            }
        }
    }

    func testKeyCodeForFunctionKeys() {
        XCTAssertEqual(ActionEngine.keyCode(for: "f1"), 0x7A)
        XCTAssertEqual(ActionEngine.keyCode(for: "f4"), 0x76)
        XCTAssertEqual(ActionEngine.keyCode(for: "f11"), 0x67)
        XCTAssertEqual(ActionEngine.keyCode(for: "f12"), 0x6F)
    }

    func testKeyNameFromKeyCodeAndCharacters() {
        XCTAssertEqual(ActionEngine.keyName(for: 0x0D, characters: "W"), "w")
        XCTAssertEqual(ActionEngine.keyName(for: 0x7E, characters: nil), "up")
        XCTAssertEqual(ActionEngine.keyName(for: 0x7A, characters: nil), "f1")
        XCTAssertEqual(ActionEngine.keyName(for: 0x31, characters: " "), "space")
    }

    func testSystemActionsPostKeys() throws {
        let cases: [(name: String, keyCode: UInt16, flags: CGEventFlags)] = [
            ("missionControl", 0x7E, .maskControl),
            ("appExpose", 0x7D, .maskControl),
            ("previousSpace", 0x7B, .maskControl),
            ("nextSpace", 0x7C, .maskControl),
            ("showDesktop", 0x67, []),
            ("spotlight", 0x31, .maskCommand),
            ("lockScreen", 0x0C, [.maskControl, .maskCommand]),
        ]
        for (name, keyCode, flags) in cases {
            let poster = MockEventPoster()
            let engine = ActionEngine(poster: poster)
            try engine.execute(.system(name))
            XCTAssertEqual(poster.keys.map(\.keyCode), [keyCode, keyCode], "\(name)")
            XCTAssertTrue(poster.keys[0].down, "\(name) key down")
            XCTAssertFalse(poster.keys[1].down, "\(name) key up")
            XCTAssertEqual(poster.keys[0].flags, flags, "\(name) flags")
        }
    }

    func testLaunchpadActionIsNoOpWithoutSpawning() throws {
        let poster = MockEventPoster()
        let engine = ActionEngine(poster: poster)
        try engine.execute(.system("launchpad"))
        XCTAssertTrue(poster.keys.isEmpty,
                      "launchpad is gone on current macOS and must not post keys or spawn anything")
    }

    func testVolumeUnavailableDeviceDoesNotThrow() {
        let volume = MockVolumeController()
        volume.error = VolumeController.Unavailable(message: "HDMI without volume control")
        let engine = ActionEngine(poster: MockEventPoster(), volume: volume)
        XCTAssertNoThrow(try engine.execute(.system("volumeUp")),
                         "unsupported devices (HDMI) should be logged, not crash the button loop")
    }

    func testRunShortcutRunsShortcutWithName() throws {
        let runner = MockShortcutRunner()
        let engine = ActionEngine(poster: MockEventPoster(), shortcutRunner: runner)
        try engine.execute(.runShortcut("SS Volume Up"))
        XCTAssertEqual(runner.names, ["SS Volume Up"])
    }

    func testRunShortcutFailureThrows() {
        let runner = MockShortcutRunner()
        runner.error = ActionError.shortcutFailed("boom")
        let engine = ActionEngine(poster: MockEventPoster(), shortcutRunner: runner)
        XCTAssertThrowsError(try engine.execute(.runShortcut("SS Volume Up")))
    }

    func testRunShortcutExecutes() throws {
        let runner = MockShortcutRunner()
        let engine = ActionEngine(poster: MockEventPoster(),
                                  shortcutRunner: runner)
        try engine.execute(.runShortcut("SS Volume Up"))
        XCTAssertEqual(runner.names, ["SS Volume Up"])
    }

    func testVolumeActionsForwardToController() throws {
        let volume = MockVolumeController()
        let engine = ActionEngine(poster: MockEventPoster(), volume: volume)
        try engine.execute(.system("volumeUp"))
        try engine.execute(.system("volumeDown"))
        try engine.execute(.system("volumeUpSmall"))
        try engine.execute(.system("volumeDownSmall"))
        try engine.execute(.system("volumeMute"))
        XCTAssertEqual(volume.adjustments, [
            .increase(.normal), .decrease(.normal),
            .increase(.small), .decrease(.small), .mute,
        ])
    }

    func testPosterSuppressesSynthesizedEventsWithoutAccessibility() {
        let poster = CGEventPoster()
        poster.isAccessibilityTrusted = { false }
        poster.postKey(0x0D, down: true, flags: [])
        XCTAssertEqual(poster.blockedPostCount, 1, "key down should be suppressed and counted")
        poster.postMouseClick(button: 3)
        XCTAssertEqual(poster.blockedPostCount, 2, "mouse click should be suppressed and counted")
    }

    func testPosterSuppressesSynthesizedEventsWhenFrontmostIsTerminal() {
        let poster = CGEventPoster()
        poster.isAccessibilityTrusted = { true }
        poster.isFrontmostTerminal = { true }
        poster.postKey(0x0D, down: true, flags: [])
        XCTAssertEqual(poster.terminalBlockedPostCount, 1,
                       "key down should be suppressed and counted when frontmost is a terminal")
        poster.postMouseClick(button: 3)
        XCTAssertEqual(poster.terminalBlockedPostCount, 2,
                       "mouse click should be suppressed and counted when frontmost is a terminal")
        XCTAssertEqual(poster.blockedPostCount, 0,
                       "accessibility counter should stay untouched by the terminal guard")
    }

    func testSystemKeySuppressedWhenFrontmostIsTerminal() throws {
        let poster = MockEventPoster()
        let engine = ActionEngine(poster: poster)
        engine.isFrontmostTerminal = { true }
        try engine.execute(.system("missionControl"))
        XCTAssertTrue(poster.keys.isEmpty,
                      "systemKey must not post synthesized keys when frontmost is a terminal")
    }

    func testShutdownRemovesLayoutObserverWithoutCrashing() {
        ActionEngine.warmKeyCodeCache()
        ActionEngine.shutdown()
        ActionEngine.shutdown()
        ActionEngine.warmKeyCodeCache()
    }
}

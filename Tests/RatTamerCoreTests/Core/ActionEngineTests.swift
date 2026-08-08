import XCTest
@testable import RatTamerCore
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

final class MockScriptRunner: ScriptRunner {
    var scripts: [String] = []
    var error: Error?

    func run(_ script: String) throws {
        if let error { throw error }
        scripts.append(script)
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

    func testSystemActionRunsScriptForSystemShortcut() throws {
        let runner = MockScriptRunner()
        let engine = ActionEngine(poster: MockEventPoster(), scriptRunner: runner)
        try engine.execute(.system("missionControl"))
        XCTAssertEqual(runner.scripts, [
            "tell application \"System Events\" to key code 126 using {control down}"
        ])
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

    func testSystemActionsRunScripts() throws {
        func scripts(for action: ButtonAction) throws -> [String] {
            let runner = MockScriptRunner()
            try ActionEngine(poster: MockEventPoster(), scriptRunner: runner).execute(action)
            return runner.scripts
        }

        XCTAssertEqual(try scripts(for: .system("launchpad")), [
            "do shell script \"/usr/bin/open -a Launchpad\""
        ])
        XCTAssertEqual(try scripts(for: .system("spotlight")), [
            "tell application \"System Events\" to key code 49 using {command down}"
        ])
        XCTAssertEqual(try scripts(for: .system("lockScreen")), [
            "tell application \"System Events\" to key code 12 using {control down, command down}"
        ])
        XCTAssertEqual(try scripts(for: .system("showDesktop")), [
            "tell application \"System Events\" to key code 103"
        ])
    }

    func testScriptFailureThrows() {
        let runner = MockScriptRunner()
        runner.error = ActionError.scriptFailed("boom")
        let engine = ActionEngine(poster: MockEventPoster(), scriptRunner: runner)
        XCTAssertThrowsError(try engine.execute(.system("missionControl")))
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

    func testVolumeSmallActionsRunScripts() throws {
        func scripts(for action: ButtonAction) throws -> [String] {
            let runner = MockScriptRunner()
            try ActionEngine(poster: MockEventPoster(), scriptRunner: runner).execute(action)
            return runner.scripts
        }
        XCTAssertEqual(try scripts(for: .system("volumeUpSmall")), [
            "set volume output volume ((output volume of (get volume settings)) + 3)"
        ])
        XCTAssertEqual(try scripts(for: .system("volumeDownSmall")), [
            "set volume output volume ((output volume of (get volume settings)) - 3)"
        ])
    }
}

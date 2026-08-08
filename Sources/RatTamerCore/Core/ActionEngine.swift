import Foundation
import CoreGraphics
import Carbon
import os

public protocol EventPoster {
    func postKey(_ keyCode: UInt16, down: Bool, flags: CGEventFlags)
    func postMouseClick(button: UInt8)
}

public protocol ScriptRunner {
    func run(_ script: String) throws
}

public protocol ShortcutRunner {
    func run(_ name: String) throws
}

public struct ProcessShortcutRunner: ShortcutRunner {
    public init() {}

    public func run(_ name: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ActionError.shortcutFailed(name)
        }
    }
}

public struct ProcessScriptRunner: ScriptRunner {
    public init() {}

    public func run(_ script: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ActionError.scriptFailed(script)
        }
    }
}

public final class CGEventPoster: EventPoster {
    private static let log = Logger(subsystem: "com.rattamer", category: "engine")

    public init() {}

    public func postKey(_ keyCode: UInt16, down: Bool, flags: CGEventFlags) {
        if down {
            for (flag, code) in Self.modifierKeys where flags.contains(flag) {
                postRaw(code, down: true)
                usleep(15_000)
            }
            postRaw(keyCode, down: true, flags: flags)
        } else {
            postRaw(keyCode, down: false, flags: flags)
            for (flag, code) in Self.modifierKeys where flags.contains(flag) {
                postRaw(code, down: false)
            }
        }
    }

    private static let modifierKeys: [(CGEventFlags, UInt16)] = [
        (.maskControl, 0x3B),
        (.maskShift, 0x38),
        (.maskCommand, 0x37),
        (.maskAlternate, 0x3A),
    ]

    private func postRaw(_ keyCode: UInt16, down: Bool, flags: CGEventFlags = []) {
        guard let event = CGEvent(
            keyboardEventSource: nil, virtualKey: keyCode, keyDown: down
        ) else { return }
        event.flags = flags
        Self.log.info("post keyCode=0x\(String(keyCode, radix: 16, uppercase: true), privacy: .public) down=\(down ? 1 : 0, privacy: .public) flags=\(flags.rawValue, privacy: .public)")
        event.post(tap: .cghidEventTap)
    }

    public func postMouseClick(button: UInt8) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let down = CGEvent(
            mouseEventSource: nil, mouseType: .otherMouseDown,
            mouseCursorPosition: location, mouseButton: .left
        )
        let up = CGEvent(
            mouseEventSource: nil, mouseType: .otherMouseUp,
            mouseCursorPosition: location, mouseButton: .left
        )
        for event in [down, up] {
            event?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
            event?.post(tap: .cghidEventTap)
        }
    }
}

public enum ActionError: Error {
    case unsupportedKey
    case scriptFailed(String)
    case shortcutFailed(String)
}

public final class ActionEngine {
    private static let log = Logger(subsystem: "com.rattamer", category: "engine")
    private let poster: EventPoster
    private let scriptRunner: ScriptRunner
    private let shortcutRunner: ShortcutRunner

    public init(poster: EventPoster,
                scriptRunner: ScriptRunner = ProcessScriptRunner(),
                shortcutRunner: ShortcutRunner = ProcessShortcutRunner()) {
        self.poster = poster
        self.scriptRunner = scriptRunner
        self.shortcutRunner = shortcutRunner
    }

    public func execute(_ action: ButtonAction) throws {
        switch action {
        case .shortcut(let key, let modifiers):
            guard let keyCode = ActionEngine.keyCode(for: key) else {
                Self.log.info("shortcut key \(key, privacy: .public) unsupported")
                throw ActionError.unsupportedKey
            }
            let flags = ActionEngine.flags(for: modifiers)
            Self.log.info("shortcut key=\(key, privacy: .public) keyCode=0x\(String(format: "%02X", keyCode), privacy: .public) modifiers=\(String(describing: modifiers), privacy: .public)")
            poster.postKey(keyCode, down: true, flags: flags)
            poster.postKey(keyCode, down: false, flags: flags)
        case .runShortcut(let name):
            Self.log.info("run shortcut name=\(name, privacy: .public)")
            try shortcutRunner.run(name)
        case .system(let name):
            try executeSystemAction(name)
        case .click(let button):
            poster.postMouseClick(button: button)
        case .gesture, .disabled, .cycleDPI:
            break
        }
    }

    private func executeSystemAction(_ name: String) throws {
        Self.log.info("system action=\(name, privacy: .public)")
        switch name {
        case "missionControl":
            try systemKey(0x7E, [.maskControl])           // Ctrl+Up
        case "appExpose":
            try systemKey(0x7D, [.maskControl])           // Ctrl+Down
        case "previousSpace":
            try systemKey(0x7B, [.maskControl])           // Ctrl+Left
        case "nextSpace":
            try systemKey(0x7C, [.maskControl])           // Ctrl+Right
        case "showDesktop":
            try systemKey(0x67, [])                       // F11
        case "volumeUp":
            try runScript("set volume output volume ((output volume of (get volume settings)) + 10)")
        case "volumeDown":
            try runScript("set volume output volume ((output volume of (get volume settings)) - 10)")
        case "volumeUpSmall":
            try runScript("set volume output volume ((output volume of (get volume settings)) + 3)")
        case "volumeDownSmall":
            try runScript("set volume output volume ((output volume of (get volume settings)) - 3)")
        case "volumeMute":
            try runScript("set volume with output muted")
        case "launchpad":
            try runScript("do shell script \"/usr/bin/open -a Launchpad\"")
        case "spotlight":
            try systemKey(0x31, [.maskCommand])           // Cmd+Space
        case "lockScreen":
            try systemKey(0x0C, [.maskControl, .maskCommand]) // Ctrl+Cmd+Q
        default:
            break
        }
    }

    private func systemKey(_ keyCode: UInt16, _ flags: CGEventFlags) throws {
        var mods: [String] = []
        if flags.contains(.maskControl) { mods.append("control down") }
        if flags.contains(.maskCommand) { mods.append("command down") }
        if flags.contains(.maskAlternate) { mods.append("option down") }
        if flags.contains(.maskShift) { mods.append("shift down") }
        let using = mods.isEmpty ? "" : " using {\(mods.joined(separator: ", "))}"
        let script = "tell application \"System Events\" to key code \(keyCode)\(using)"
        Self.log.info("systemKey code=\(keyCode, privacy: .public) script=\(script, privacy: .public)")
        try runScript(script)
    }

    private func runScript(_ script: String) throws {
        try scriptRunner.run(script)
    }

    public static func keyCode(for character: String) -> UInt16? {
        let lower = character.lowercased()
        if lower.count == 1 {
            if let code = layoutCode(for: lower) {
                return code
            }
        }
        return staticKeyCode(for: lower)
    }

    // Character → virtual key code map for the current keyboard layout.
    //
    // TIS/HIToolbox input-source calls must run on the main thread only — they
    // assert on it, which crashed the button loop — and `DispatchQueue.main.sync`
    // from the button loop can deadlock when the main thread is busy. So the map
    // is built entirely on the main thread and the hot path only reads this cache,
    // never blocking on main. Layout switches invalidate it via the TIS
    // notification; the map is rebuilt on the next lookup.
    internal static var layoutCache: [String: UInt16]?
    private static let layoutLock = NSLock()
    private static var layoutRefillQueued = false

    private static let layoutChangeObserverToken = DistributedNotificationCenter.default()
        .addObserver(forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
                     object: nil, queue: .main) { _ in
            ActionEngine.handleKeyboardLayoutChanged()
        }

    /// Pre-computes the character → key code map for the current layout. Call on
    /// the main thread (e.g. after the engine connects) so the button loop never
    /// falls back to the static map on its first press.
    public static func warmKeyCodeCache() {
        _ = layoutChangeObserverToken
        requestLayoutRefill()
    }

    /// Invalidates the cached layout map. Called when the keyboard layout
    /// changes; the map is rebuilt on the next lookup.
    static func handleKeyboardLayoutChanged() {
        layoutLock.lock()
        layoutCache = nil
        layoutLock.unlock()
    }

    private static func layoutCode(for character: String) -> UInt16? {
        layoutLock.lock()
        let cached = layoutCache?[character]
        layoutLock.unlock()
        if let cached { return cached }
        requestLayoutRefill()
        if Thread.isMainThread {
            layoutLock.lock()
            let fresh = layoutCache?[character]
            layoutLock.unlock()
            return fresh
        }
        return nil
    }

    private static func requestLayoutRefill() {
        layoutLock.lock()
        guard !layoutRefillQueued else {
            layoutLock.unlock()
            return
        }
        layoutRefillQueued = true
        layoutLock.unlock()
        let refill = {
            refillLayoutCache()
            layoutLock.lock()
            layoutRefillQueued = false
            layoutLock.unlock()
        }
        if Thread.isMainThread {
            refill()
        } else {
            DispatchQueue.main.async(execute: refill)
        }
    }

    /// Builds the full character → key code map for the current keyboard layout.
    /// Must be called on the main thread only.
    private static func refillLayoutCache() {
        guard let src = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue() else { return }
        guard let raw = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return }
        let cfData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
        let data = cfData as Data
        let layoutPtr = (data as NSData).bytes.assumingMemoryBound(to: UCKeyboardLayout.self)
        var codes: [String: UInt16] = [:]
        for vk in UInt16(0)...127 {
            var dead: UInt32 = 0
            var outLen = 0
            var out = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layoutPtr, vk, 0, 0,
                                        UInt32(kUCKeyTranslateNoDeadKeysBit), 0,
                                        &dead, 8, &outLen, &out)
            guard status == noErr, outLen == 1 else { continue }
            let chars = String(utf16CodeUnits: out, count: Int(outLen))
            guard chars.count == 1 else { continue }
            let key = chars.lowercased()
            if codes[key] == nil { codes[key] = vk }
        }
        layoutLock.lock()
        layoutCache = codes
        layoutLock.unlock()
    }

    public static func staticKeyCode(for character: String) -> UInt16? {
        let lower = character.lowercased()
        switch lower {
        case "a": return 0x00
        case "s": return 0x01
        case "d": return 0x02
        case "f": return 0x03
        case "h": return 0x04
        case "g": return 0x05
        case "z": return 0x06
        case "x": return 0x07
        case "c": return 0x08
        case "v": return 0x09
        case "b": return 0x0B
        case "q": return 0x0C
        case "w": return 0x0D
        case "e": return 0x0E
        case "r": return 0x0F
        case "y": return 0x10
        case "t": return 0x11
        case "1": return 0x12
        case "2": return 0x13
        case "3": return 0x14
        case "4": return 0x15
        case "6": return 0x16
        case "5": return 0x17
        case "=": return 0x18
        case "9": return 0x19
        case "7": return 0x1A
        case "-": return 0x1B
        case "8": return 0x1C
        case "0": return 0x1D
        case "]": return 0x1E
        case "o": return 0x1F
        case "u": return 0x20
        case "[": return 0x21
        case "i": return 0x22
        case "p": return 0x23
        case "l": return 0x25
        case "j": return 0x26
        case "'": return 0x27
        case "k": return 0x28
        case ";": return 0x29
        case "\\": return 0x2A
        case ",": return 0x2B
        case "/": return 0x2C
        case "n": return 0x2D
        case "m": return 0x2E
        case ".": return 0x2F
        case "tab": return 0x30
        case "space": return 0x31
        case "return", "enter": return 0x24
        case "escape", "esc": return 0x35
        case "delete": return 0x33
        case "up": return 0x7E
        case "down": return 0x7D
        case "left": return 0x7B
        case "right": return 0x7C
        case "f1": return 0x7A
        case "f2": return 0x78
        case "f3": return 0x63
        case "f4": return 0x76
        case "f5": return 0x60
        case "f6": return 0x61
        case "f7": return 0x62
        case "f8": return 0x64
        case "f9": return 0x65
        case "f10": return 0x6D
        case "f11": return 0x67
        case "f12": return 0x6F
        case "home": return 0x73
        case "end": return 0x77
        case "pageup": return 0x74
        case "pagedown": return 0x79
        case "deleteForward": return 0x75
        default: return nil
        }
    }

    public static func keyName(for keyCode: UInt16, characters: String?) -> String? {
        if let characters {
            let cleaned = characters.lowercased()
            if cleaned.count == 1, !cleaned.contains(" ") {
                return cleaned
            }
        }
        switch keyCode {
        case 0x30: return "tab"
        case 0x31: return "space"
        case 0x24: return "return"
        case 0x35: return "escape"
        case 0x33: return "delete"
        case 0x75: return "deleteForward"
        case 0x73: return "home"
        case 0x77: return "end"
        case 0x74: return "pageup"
        case 0x79: return "pagedown"
        case 0x7E: return "up"
        case 0x7D: return "down"
        case 0x7B: return "left"
        case 0x7C: return "right"
        case 0x7A: return "f1"
        case 0x78: return "f2"
        case 0x63: return "f3"
        case 0x76: return "f4"
        case 0x60: return "f5"
        case 0x61: return "f6"
        case 0x62: return "f7"
        case 0x64: return "f8"
        case 0x65: return "f9"
        case 0x6D: return "f10"
        case 0x67: return "f11"
        case 0x6F: return "f12"
        default: return nil
        }
    }

    public static func flags(for modifierNames: [String]) -> CGEventFlags {
        var flags = CGEventFlags()
        for name in modifierNames {
            switch name.lowercased() {
            case "command", "cmd": flags.insert(.maskCommand)
            case "control", "ctrl": flags.insert(.maskControl)
            case "option", "alt": flags.insert(.maskAlternate)
            case "shift": flags.insert(.maskShift)
            default: break
            }
        }
        return flags
    }
}

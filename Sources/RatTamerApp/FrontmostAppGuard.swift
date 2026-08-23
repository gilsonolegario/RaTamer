import AppKit
import Foundation

/// Answers "is the frontmost app a terminal emulator?" cheaply from any thread.
/// The engine consults this before injecting synthesized events, so keystrokes,
/// clicks, scrolls and system key codes never land as text/commands in a tmux
/// window. The answer is cached for a short window because the smooth-scroll
/// path queries it at 120 Hz.
enum FrontmostAppGuard {
    private static let cacheTTL: TimeInterval = 0.25

    private static let lock = NSLock()
    private static var cachedResult = false
    private static var cachedAt = Date.distantPast

    /// Whether the terminal protection is enabled in the user config. Set from
    /// EngineController whenever the config reloads; cached so the hot path
    /// (120 Hz smooth scroll) never touches the config store or AppKit.
    static var isEnabled = true

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.mitchellh.ghostty",
        "io.wez.wezterm",
        "com.warp.Warp-Stable",
        "com.tabby.sh",
    ]

    static func isFrontmostTerminal() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(cachedAt) < cacheTTL else {
            let value = compute()
            cachedResult = value
            cachedAt = now
            return value
        }
        return cachedResult
    }

    private static func compute() -> Bool {
        guard isEnabled else { return false }
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return terminalBundleIDs.contains(bundleID)
    }
}

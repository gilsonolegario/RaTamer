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
        "io.alacritty",
        "com.mitchellh.ghostty",
        "com.github.wez.wezterm",
        "io.wez.wezterm",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "dev.warp.Warp-Preview",
        "com.warp.Warp-Stable",
        "org.tabby",
        "com.tabby.sh",
        // Hybrid editors — their integrated terminals also receive keystrokes.
        // Over-blocking (buttons dead in the editor) is safer than under-blocking
        // (garbage typed into the terminal/tmux).
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.microsoft.VSCodium",
        "com.vscodium.vscodium",
        "dev.zed.Zed",
        "dev.zed.Zed-Preview",
        "dev.zed.Zed-Dev",
        "com.todesktop.230313mzl4w4u92", // Cursor (Todesktop)
        "com.google.antigravity-ide",
        "co.zeit.hyper",
        "com.vercel.hyper",
    ]

    /// Test hook: whether a given bundle ID is considered a terminal.
    static func isTerminalBundleID(_ bundleID: String) -> Bool {
        terminalBundleIDs.contains(bundleID)
    }

    /// Invalidate the cached answer so the next query recomputes. Call when
    /// the frontmost app changes (NSWorkspace.didActivateApplicationNotification).
    static func invalidate() {
        lock.lock()
        cachedAt = .distantPast
        lock.unlock()
    }

    static func isFrontmostTerminal() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        guard now.timeIntervalSince(cachedAt) < cacheTTL else {
            let value: Bool
            if Thread.isMainThread {
                value = compute()
            } else {
                var computed = false
                DispatchQueue.main.sync { computed = compute() }
                value = computed
            }
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

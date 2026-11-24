import AppKit
import Foundation

/// Answers "is the frontmost app a terminal emulator?" cheaply from any thread.
/// The engine consults this before injecting synthesized events, so keystrokes,
/// clicks, scrolls and system key codes never land as text/commands in a tmux
/// window. The answer is cached for a short window because the smooth-scroll
/// path queries it at 120 Hz.
enum FrontmostAppGuard {
    private static let lock = NSLock()
    private static var cachedResult = false

    /// Whether the terminal protection is enabled in the user config. Set from
    /// EngineController whenever the config reloads; cached so the hot path
    /// (120 Hz smooth scroll) never touches the config store or AppKit.
    static var isEnabled = true {
        didSet {
            invalidate()
        }
    }

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

    /// Directly updates the cached terminal state using the provided bundle ID.
    static func update(bundleID: String?) {
        let isTerm = bundleID.map { terminalBundleIDs.contains($0) } ?? false
        lock.lock()
        cachedResult = isEnabled && isTerm
        lock.unlock()
    }

    /// Invalidate the cached answer so the next query reflects the current frontmost app.
    /// Safely hops to main if invoked from a background queue.
    static func invalidate() {
        if Thread.isMainThread {
            update(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        } else {
            DispatchQueue.main.async {
                update(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
            }
        }
    }

    /// Fast non-blocking check. Called at 120 Hz from the smooth-scroll coordinator
    /// queue without ever blocking on the main thread.
    static func isFrontmostTerminal() -> Bool {
        lock.lock()
        defer { lock.unlock() }
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

import AppKit
import SwiftUI

final class SettingsNSWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    private init() {}

    func show() {
        makeWindowIfNeeded()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        CrashReporter.addBreadcrumb("settings shown")
    }

    func close() {
        window?.close()
    }

    private func makeWindowIfNeeded() {
        guard window == nil else { return }
        let view = SettingsView(
            onTitleChange: { [weak self] title in
                self?.window?.title = "RaTamer — \(title)"
            },
            onContentHeight: { [weak self] height in
                self?.resizeToContent(height)
            })
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        let window = SettingsNSWindow(contentViewController: hosting)
        window.title = "RaTamer — General"
        // Compact utility window (Mos-like): content scrolls, the window doesn't
        // need to show every section at once. No frame autosave: the window
        // hugs each pane's content on open (a restored oversized frame would
        // fight resizeToContent).
        window.setContentSize(NSSize(width: 560, height: 500))
        window.contentMinSize = NSSize(width: 520, height: 320)
        window.contentMaxSize = NSSize(width: 800, height: 1400)
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        self.window = window
    }

    /// Grows/shrinks the window vertically to hug the pane content, keeping
    /// the title bar fixed (the frame grows downward).
    private func resizeToContent(_ contentHeight: CGFloat) {
        guard let window, contentHeight > 0 else { return }
        let contentNow = window.contentView?.frame.height ?? window.frame.height
        let chrome = window.frame.height - contentNow
        // Breathing room covers automatic ScrollView content margins that the
        // geometry reader doesn't account for (empirically ~30-40pt).
        var total = (contentHeight + chrome + 40).rounded(.up)
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if visible.height > 0 {
            total = min(total, visible.height - 24)
        }
        total = max(total, 340)
        let old = window.frame
        guard abs(old.height - total) > 1 else { return }
        let newFrame = NSRect(x: old.minX, y: old.maxY - total,
                              width: old.width, height: total)
        window.setFrame(newFrame, display: true, animate: true)
    }
}

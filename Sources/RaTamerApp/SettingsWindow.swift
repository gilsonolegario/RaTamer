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
    private var resizeWorkItem: DispatchWorkItem?
    private var isLiveResizing = false
    private var mouseUpMonitor: Any?
    private var lastTabSwitchTime: CFTimeInterval = 0

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
                self?.scheduleResize(height)
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

        // Track user drags: hugging the content height mid-drag is what made
        // every resize look like a reflow dance (window snaps under the cursor).
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.willStartLiveResizeNotification,
                           object: window, queue: .main) { [weak self] _ in
            self?.isLiveResizing = true
        }
        // No matching didEnd notification exists; detect mouse-up to clear the flag.
        self.mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) {
            [weak self] event in
            self?.isLiveResizing = false
            return event
        }
    }

    /// Record the moment a tab switch happened. scheduleResize ignores
    /// geometry changes for 250ms after this to avoid flashing.
    func recordTabSwitch() {
        lastTabSwitchTime = CACurrentMediaTime()
    }

    /// Debounced resize: batches rapid geometry changes into a single frame update.
    /// During a tab-switch animation, delays the resize until the crossfade ends.
    private func scheduleResize(_ contentHeight: CGFloat) {
        guard !isLiveResizing else { return }
        resizeWorkItem?.cancel()
        let delay: TimeInterval = (CACurrentMediaTime() - lastTabSwitchTime < 0.25) ? 0.2 : 0.05
        let work = DispatchWorkItem { [weak self] in
            self?.resizeToContent(contentHeight)
        }
        resizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
        window.setFrame(newFrame, display: false, animate: false)
    }
}

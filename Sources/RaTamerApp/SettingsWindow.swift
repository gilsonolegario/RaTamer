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
            onContentHeight: { [weak self] height in
                self?.scheduleResize(height)
            })
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        let window = SettingsNSWindow(contentViewController: hosting)
        // Static title: a per-tab title swaps centered text on every switch,
        // and that repaint is what reads as the titlebar "flickering".
        window.title = "RaTamer"
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

    /// Debounced resize: batches rapid geometry changes into a single frame update.
    private func scheduleResize(_ contentHeight: CGFloat) {
        guard !isLiveResizing else { return }
        resizeWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.resizeToContent(contentHeight)
        }
        resizeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    /// Grows/shrinks the window vertically to hug the pane content.
    /// Anchors the top edge and grows downward, but clamps to visible screen.
    /// Guarded against live resize here (not just at scheduling) so a work
    /// item already in flight can never fight a drag the user just started.
    private func resizeToContent(_ contentHeight: CGFloat) {
        guard let window, contentHeight > 0, !isLiveResizing else { return }
        let contentNow = window.contentView?.frame.height ?? window.frame.height
        let chrome = window.frame.height - contentNow
        // The pane's measured height already includes its own bottom padding
        // (SettingsView adds it inside the measurement); only rounding slack
        // is added here. Margins outside the measurement were eliminated at
        // the source, so this goes all the way to the last content row.
        var total = (contentHeight + chrome + 6).rounded(.up)
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if visible.height > 0 {
            total = min(total, visible.height)
        }
        total = max(total, 340)
        let old = window.frame
        guard abs(old.height - total) > 1 else { return }
        // Anchor top edge; clamp bottom to not exceed visible screen
        let newY = max(visible.minY, old.maxY - total)
        let newFrame = NSRect(x: old.minX, y: newY,
                              width: old.width, height: total)
        // Plan B: apply the frame in ONE coalesced stroke. Animating the
        // NSWindow frame repaints the titlebar every animation frame, which
        // reads as flicker no matter what else is debounced. All visible
        // motion lives on the SwiftUI side instead: crossfade + vertical
        // drift + sliding underline (see SettingsView / TabBar).
        window.setFrame(newFrame, display: false, animate: false)
    }
}

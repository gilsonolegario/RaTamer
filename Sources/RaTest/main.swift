import AppKit
import RaTamerCore
import SwiftUI

final class RaTestNSWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

/// Window holder mirroring SettingsWindow: the SwiftUI content reports its
/// ideal height through `onContentHeight`, this class debounces those
/// reports and resizes the window to hug the visible tab's content.
final class RaTestWindow {
    static let shared = RaTestWindow()
    private var window: NSWindow?
    private var resizeWorkItem: DispatchWorkItem?
    private var isLiveResizing = false
    private var mouseUpMonitor: Any?

    private init() {}

    /// `engine` is created by the AppDelegate before the first `show()` and
    /// kept alive there; passed in so this class never holds a second
    /// reference or owns its lifecycle.
    func show(engine: RaTestEngine) {
        makeWindowIfNeeded(engine: engine)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }

    private func makeWindowIfNeeded(engine: RaTestEngine) {
        guard window == nil else { return }
        let view = RaTestView(
            engine: engine,
            onContentHeight: { [weak self] height in
                self?.scheduleResize(height)
            })
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        let window = RaTestNSWindow(contentViewController: hosting)
        // Static title — same reasoning as SettingsWindow: per-tab titles
        // repaint the titlebar on every switch and read as flicker.
        window.title = "RaTest — Button Tester"
        // Content hugs each tab's height via scheduleResize; no frame
        // autosave because a restored frame would fight resizeToContent.
        window.setContentSize(NSSize(width: 560, height: 500))
        window.contentMinSize = NSSize(width: 520, height: 320)
        window.contentMaxSize = NSSize(width: 800, height: 1400)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        self.window = window

        // Track user drags: resizing mid-drag makes every update look like
        // the window snapping under the cursor.
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

    /// Grows/shrinks the window vertically to hug the pane content,
    /// anchoring the top edge and clamping to the visible screen.
    private func resizeToContent(_ contentHeight: CGFloat) {
        guard let window, contentHeight > 0, !isLiveResizing else { return }
        let contentNow = window.contentView?.frame.height ?? window.frame.height
        let chrome = window.frame.height - contentNow
        // The pane's measured height already includes its own bottom padding;
        // only rounding slack is added here.
        var total = (contentHeight + chrome + 6).rounded(.up)
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        if visible.height > 0 {
            total = min(total, visible.height)
        }
        total = max(total, 340)
        let old = window.frame
        guard abs(old.height - total) > 1 else { return }
        // Anchor top edge; clamp bottom to not exceed visible screen.
        let newY = max(visible.minY, old.maxY - total)
        let newFrame = NSRect(x: old.minX, y: newY,
                              width: old.width, height: total)
        // Instant stroke (no animation): animating the frame repaints the
        // titlebar per frame and reads as flicker; all visible motion lives
        // in the SwiftUI crossfade + drift inside RaTestView.
        window.setFrame(newFrame, display: false, animate: false)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: RaTestEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = RaTestEngine(configStore: ConfigStore(fileURL: ConfigStore.defaultFileURL()))
        self.engine = engine

        // Window holder wires engine callbacks via the view's onAppear;
        // stop() happens in applicationWillTerminate.
        RaTestWindow.shared.show(engine: engine)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()

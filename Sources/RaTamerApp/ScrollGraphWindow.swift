import AppKit
import SwiftUI

/// External window hosting the live thermal scroll graph. Closed by default
/// at launch: opening it is the only thing that connects the sample sink and
/// starts the 30 Hz flush, so a closed window costs nothing.
final class ScrollGraphWindow: NSObject, NSWindowDelegate {
    static let shared = ScrollGraphWindow()
    private var window: NSWindow?
    private let store = ScrollGraphStore()
    private var configPoll: Timer?

    private override init() {}

    func show() {
        makeWindowIfNeeded()
        refreshSmoothFlag()
        startConfigPoll()
        AppModel.shared.engine?.scrollSampleSink = { [weak store] sample in
            store?.add(sample)
        }
        store.start()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        AppModel.shared.engine?.scrollSampleSink = nil
        stopConfigPoll()
        store.stop()
    }

    private func refreshSmoothFlag() {
        store.smoothEnabled = AppModel.shared.configStore.load().smoothScrollEnabled == true
    }

    /// 1 Hz refresh of the smooth flag so the empty-state warning reacts to
    /// toggles in Settings while the window stays open. Runs only while open.
    private func startConfigPoll() {
        stopConfigPoll()
        let poll = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshSmoothFlag()
        }
        RunLoop.main.add(poll, forMode: .common)
        configPoll = poll
    }

    private func stopConfigPoll() {
        configPoll?.invalidate()
        configPoll = nil
    }

    private func makeWindowIfNeeded() {
        guard window == nil else { return }
        let view = ScrollGraphView(store: store)
        let hosting = NSHostingController(rootView: view)
        let window = SettingsNSWindow(contentViewController: hosting)
        window.title = "RaTamer — Scroll Thermograph"
        window.setContentSize(NSSize(width: 640, height: 400))
        window.contentMinSize = NSSize(width: 480, height: 300)
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("RaTamerScrollThermograph")
        self.window = window
    }
}

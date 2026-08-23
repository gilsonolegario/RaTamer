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
        let view = SettingsView { [weak self] title in
            self?.window?.title = "RatTamer — \(title)"
        }
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = []
        let window = SettingsNSWindow(contentViewController: hosting)
        window.title = "RatTamer — Buttons"
        window.setContentSize(NSSize(width: 900, height: 760))
        window.contentMinSize = NSSize(width: 720, height: 620)
        window.contentMaxSize = NSSize(width: 1400, height: 1100)
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("RatTamerSettings")
        self.window = window
    }
}

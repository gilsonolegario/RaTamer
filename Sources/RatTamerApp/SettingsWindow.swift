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
        window.title = "RatTamer — General"
        // Compact utility window (Mos-like): content scrolls, the window doesn't
        // need to show every section at once. New autosave name so a previously
        // saved giant frame doesn't override the compact default.
        window.setContentSize(NSSize(width: 560, height: 500))
        window.contentMinSize = NSSize(width: 520, height: 420)
        window.contentMaxSize = NSSize(width: 800, height: 1000)
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("RatTamerSettingsCompact")
        self.window = window
    }
}

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
        hosting.sizingOptions = [.preferredContentSize]
        let window = SettingsNSWindow(contentViewController: hosting)
        window.title = "RatTamer — Buttons"
        window.setContentSize(NSSize(width: 760, height: 560))
        window.contentMinSize = NSSize(width: 680, height: 460)
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("RatTamerSettings")
        self.window = window
    }
}

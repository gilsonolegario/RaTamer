import AppKit
import SwiftUI
import RatTamerCore

final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?

    private init() {}

    func showIfNeeded() {
        guard OnboardingGate.shouldShow else { return }
        show()
    }

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
        let view = OnboardingView {
            self.close()
        }
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        let window = SettingsNSWindow(contentViewController: hosting)
        window.title = "Welcome to RatTamer"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        self.window = window
        window.center()
    }
}

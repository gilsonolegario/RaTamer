import AppKit
import SwiftUI
import RaTamerCore

final class OnboardingWindow {
    static let shared = OnboardingWindow()
    private var window: NSWindow?
    /// Called after the window closes so the app can hand off to its main UI.
    var onFinish: (() -> Void)?

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

    private func finish() {
        close()
        onFinish?()
    }

    private func makeWindowIfNeeded() {
        guard window == nil else { return }
        let view = OnboardingView {
            self.finish()
        }
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        let window = SettingsNSWindow(contentViewController: hosting)
        window.title = "Welcome to RaTamer"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        self.window = window
        window.center()
    }
}

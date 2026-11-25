import AppKit
import SwiftUI
import RaTamerCore

final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()
    private var window: NSWindow?
    /// Called after the window closes so the app can hand off to its main UI.
    var onFinish: (() -> Void)?

    private override init() {
        super.init()
    }

    func showIfNeeded() {
        guard OnboardingGate.shouldShow else { return }
        show()
    }

    func show() {
        makeWindowIfNeeded()
        AppModel.shared.refreshAccessibility()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        ActivationPolicyHelper.apply(reason: "onboarding-close")
    }

    func windowWillClose(_ notification: Notification) {
        ActivationPolicyHelper.apply(reason: "onboarding-close")
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
        window.delegate = self
        self.window = window
        window.center()
    }
}

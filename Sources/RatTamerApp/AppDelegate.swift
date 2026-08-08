import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()
        Notifier.requestAuthorization()
        AppModel.shared.startEngine()
        menuBar = MenuBarController()
        menuBar?.buildMenu()
        EngineEvents.shared.onConnected = {
            Notifier.post(title: "RatTamer", body: "MX Master 2S connected")
        }
        EngineEvents.shared.onDisconnected = {
            Notifier.post(title: "RatTamer", body: "MX Master 2S disconnected")
        }
        requestAccessibilityIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            OnboardingWindow.shared.onFinish = { [weak self] in
                self?.menuBar?.showPopover()
            }
            OnboardingWindow.shared.showIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stopEngine()
    }

    private func requestAccessibilityIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !Permissions.isAccessibilityTrusted() else { return }
            Permissions.requestAccessibility()
        }
    }

    private func applyActivationPolicy() {
        let config = AppModel.shared.configStore.load()
        NSApp.setActivationPolicy(config.menuBarOnly == true ? .accessory : .regular)
    }
}

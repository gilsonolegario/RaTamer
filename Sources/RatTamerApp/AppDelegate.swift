import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
}

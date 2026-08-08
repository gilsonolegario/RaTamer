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
        requestAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stopEngine()
    }

    private func requestAccessibilityIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !Permissions.isAccessibilityTrusted() else { return }
            Permissions.requestAccessibility()
            let alert = NSAlert()
            alert.messageText = "RatTamer needs Accessibility permission"
            alert.informativeText = "Shortcuts and gestures require keyboard and mouse control. "
                + "Enable RatTamer in System Settings → Privacy & Security → Accessibility."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

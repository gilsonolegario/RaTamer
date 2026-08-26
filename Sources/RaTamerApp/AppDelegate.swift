import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.addBreadcrumb("didFinishLaunching")
        CrashReporter.addBreadcrumb("accessibilityTrusted=\(Permissions.isAccessibilityTrusted())")
        applyActivationPolicy()
        Notifier.requestAuthorization()
        AppModel.shared.startEngine()
        BatteryMonitor.shared.start()
        buildMainMenu()
        menuBar = MenuBarController()
        menuBar?.buildMenu()
        EngineEvents.shared.onConnected = {
            CrashReporter.addBreadcrumb("device connected")
            Notifier.post(title: "RaTamer", body: "\(AppModel.shared.deviceName) connected")
        }
        EngineEvents.shared.onDisconnected = {
            CrashReporter.addBreadcrumb("device disconnected")
            Notifier.post(title: "RaTamer", body: "\(AppModel.shared.deviceName) disconnected")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            OnboardingWindow.shared.onFinish = { [weak self] in
                self?.menuBar?.showPopover()
            }
            OnboardingWindow.shared.showIfNeeded()
        }
        // Test automation hook: abre Settings sem simular cliques.
        if ProcessInfo.processInfo.environment["RATAMER_SHOW_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                SettingsWindow.shared.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CrashReporter.addBreadcrumb("willTerminate")
        AppModel.shared.stopEngine()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(showSettings),
                                      keyEquivalent: "")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let graphItem = NSMenuItem(title: "Scroll Thermograph…",
                                   action: #selector(showScrollThermograph),
                                   keyEquivalent: "")
        graphItem.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: nil)
        menu.addItem(graphItem)

        menu.addItem(NSMenuItem.separator())

        let reconnectItem = NSMenuItem(title: "Reconnect",
                                       action: #selector(reconnect),
                                       keyEquivalent: "")
        reconnectItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        menu.addItem(reconnectItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit RaTamer",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        return menu
    }

    private func applyActivationPolicy() {
        let config = AppModel.shared.configStore.load()
        NSApp.setActivationPolicy(config.menuBarOnly == true ? .accessory : .regular)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let graphItem = NSMenuItem(title: "Scroll Thermograph…",
                                   action: #selector(showScrollThermograph),
                                   keyEquivalent: "t")
        graphItem.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(NSMenuItem(title: "About RaTamer",
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(graphItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit RaTamer",
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize",
                                      action: #selector(NSWindow.performMiniaturize(_:)),
                                      keyEquivalent: "m"))
        windowMenu.addItem(.separator())
        windowMenu.addItem(NSMenuItem(title: "Close Window",
                                      action: #selector(NSWindow.performClose(_:)),
                                      keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showScrollThermograph() {
        ScrollGraphWindow.shared.show()
    }

    @objc private func showSettings() {
        SettingsWindow.shared.show()
    }

    @objc private func reconnect() {
        AppModel.shared.engine?.reconnect()
    }
}

import AppKit
import RaTamerCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: RatTestEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = RatTestEngine(configStore: ConfigStore(fileURL: ConfigStore.defaultFileURL()))
        self.engine = engine

        let hosting = NSHostingController(rootView: RatTestView(engine: engine))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "RatTest — Button Tester"
        window.setContentSize(NSSize(width: 660, height: 1200))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 660, height: 700)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.stop()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()

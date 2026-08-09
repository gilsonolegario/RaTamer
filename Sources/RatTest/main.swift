import AppKit
import RatTamerCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: RatTestEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = RatTestEngine(configStore: ConfigStore(fileURL: ConfigStore.defaultFileURL()))
        self.engine = engine

        let hosting = NSHostingController(rootView: RatTestView(engine: engine))
        let window = NSWindow(contentViewController: hosting)
        window.title = "RatTest — Button Tester"
        window.setContentSize(NSSize(width: 660, height: 720))
        window.styleMask = [.titled, .closable, .miniaturizable]
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

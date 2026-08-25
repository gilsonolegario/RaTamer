import AppKit
import RaTamerCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var engine: RaTestEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = RaTestEngine(configStore: ConfigStore(fileURL: ConfigStore.defaultFileURL()))
        self.engine = engine

        // Frame flexível: define largura mínima/ideal mas permite
        // redimensionamento. NSHostingController usa o ideal para
        // tamanho inicial; ScrollView lida com overflow vertical.
        let root = RaTestView(engine: engine)
            .frame(minWidth: 560, idealWidth: 620, maxWidth: .infinity,
                   minHeight: 500, idealHeight: 760, maxHeight: .infinity)
        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "RaTest — Button Tester"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.contentMinSize = NSSize(width: 560, height: 500)
        window.isRestorable = false
        // Dimensiona pela área visível (sem menu bar/Dock) — janela maior que a tela
        // encosta no topo e parece "grudada" na menu bar.
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let width = min(600, visible.width - 40)
            let height = min(760, visible.height - 40)
            let frame = NSRect(
                x: visible.midX - width / 2,
                y: visible.midY - height / 2,
                width: width,
                height: height
            )
            window.setFrame(frame, display: true)
        } else {
            window.setContentSize(NSSize(width: 600, height: 760))
            window.center()
        }
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

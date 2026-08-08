import AppKit
import SwiftUI

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var hosting: NSHostingController<MenuBarPopoverView>?

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "computermouse",
                               accessibilityDescription: "RatTamer")
        button.action = #selector(togglePopover(_:))
        button.target = self

        let popover = NSPopover()
        popover.behavior = .transient
        let hosting = NSHostingController(rootView: MenuBarPopoverView())
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        self.popover = popover
        self.hosting = hosting
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            if let hosting {
                popover?.contentSize = hosting.view.fittingSize
            }
            popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

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

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(from: button)
        }
    }

    /// Shows the popover anchored to the status item. Used by onboarding to
    /// hand off to the main UI once setup finishes.
    func showPopover() {
        guard let button = statusItem?.button else { return }
        showPopover(from: button)
    }

    private func showPopover(from button: NSStatusBarButton) {
        if let hosting {
            popover?.contentSize = hosting.view.fittingSize
        }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }
}

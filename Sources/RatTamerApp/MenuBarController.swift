import AppKit
import Combine
import SwiftUI

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private let model = AppModel.shared
    private var cancellables = Set<AnyCancellable>()

    func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "computermouse",
                               accessibilityDescription: "RatTamer")
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.action = #selector(togglePopover(_:))
        button.target = self

        let popover = NSPopover()
        popover.behavior = .transient
        let viewController = NSViewController()
        viewController.view = NSHostingView(rootView: MenuBarPopoverView())
        popover.contentViewController = viewController
        self.popover = popover

        model.$isConnected
            .combineLatest(model.$isReconnecting)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)
        updateStatusIcon()
    }

    /// Swaps the status item icon to reflect the connection state, mirroring
    /// swmpc's setPopoverAnchorImage: connected/reconnecting shows a filled
    /// mouse, disconnected shows the outline.
    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol = (model.isConnected || model.isReconnecting)
            ? "computermouse.fill"
            : "computermouse"
        button.image = NSImage(systemSymbolName: symbol,
                               accessibilityDescription: "RatTamer")
        button.image?.isTemplate = true
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
        CrashReporter.addBreadcrumb("popover shown")
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        popover?.contentViewController?.view.window?.makeKey()
    }
}

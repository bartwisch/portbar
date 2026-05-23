import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let scanner = ServerScanner()
    private var cancellables = Set<AnyCancellable>()
    private var popover: NSPopover?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configurePopover()
        bindScanner()
        scanner.refresh()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "PortBar")
        item.button?.imagePosition = .imageLeading
        item.button?.action = #selector(togglePopover)
        item.button?.target = self
        statusItem = item
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 390, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: ServerListView(
                scanner: scanner,
                onQuit: { NSApp.terminate(nil) }
            )
        )
        self.popover = popover
    }

    private func bindScanner() {
        scanner.$servers
            .sink { [weak self] servers in
                self?.updateStatusTitle(for: servers)
            }
            .store(in: &cancellables)
    }

    private func updateStatusTitle(for servers: [ServerProcess]) {
        let count = servers.filter(\.isLikelyDevelopmentServer).count
        statusItem?.button?.title = count > 0 ? " \(count)" : ""
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            scanner.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

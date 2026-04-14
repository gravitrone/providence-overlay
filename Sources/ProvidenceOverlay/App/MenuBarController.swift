import AppKit
import Combine

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let state: AppState
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "\u{1F525}"  // Fire emoji placeholder - proper icon in Phase 10

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Providence Overlay", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let connectionItem = NSMenuItem(title: "Connection: ...", action: nil, keyEquivalent: "")
        connectionItem.identifier = NSUserInterfaceItemIdentifier("connection")
        menu.addItem(connectionItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu

        state.$connectionStatus
            .sink { [weak self] status in
                if let item = self?.statusItem.menu?.item(withIdentifier: NSUserInterfaceItemIdentifier("connection")) {
                    item.title = "Connection: \(status)"
                }
            }
            .store(in: &cancellables)
    }

    @objc func quit() { NSApp.terminate(nil) }
}

extension NSMenu {
    func item(withIdentifier id: NSUserInterfaceItemIdentifier) -> NSMenuItem? {
        items.first { $0.identifier == id }
    }
}

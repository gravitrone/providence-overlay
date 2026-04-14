import AppKit
import Combine

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let state: AppState
    private let exclusions: ExclusionsManager?
    private var cancellables = Set<AnyCancellable>()

    // Phase 10: pulsing recording indicator. Alternates between flame (on) and
    // dim flame (off) while audio is active or meeting mode is on. Never
    // suppressed - privacy requirement.
    private var pulseTimer: Timer?
    private var pulseVisible: Bool = true
    private var pulseActive: Bool = false

    // Fixed default exclusion list shown in the submenu. Bundle ID -> display name.
    private static let commonExclusionApps: [(String, String)] = [
        ("com.1password.1password", "1Password"),
        ("com.apple.keychainaccess", "Keychain Access"),
        ("org.whispersystems.signal-desktop", "Signal"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("company.thebrowser.Browser", "Arc (private)"),
    ]

    init(state: AppState, exclusions: ExclusionsManager? = nil) {
        self.state = state
        self.exclusions = exclusions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if let img = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Providence Overlay") {
                img.isTemplate = true
                btn.image = img
            } else {
                btn.title = "P"
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Providence Overlay", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let connectionItem = NSMenuItem(title: "Connection: ...", action: nil, keyEquivalent: "")
        connectionItem.identifier = NSUserInterfaceItemIdentifier("connection")
        menu.addItem(connectionItem)

        let recordingItem = NSMenuItem(title: "Recording: idle", action: nil, keyEquivalent: "")
        recordingItem.identifier = NSUserInterfaceItemIdentifier("recording")
        menu.addItem(recordingItem)

        let batteryItem = NSMenuItem(title: "Battery: —", action: nil, keyEquivalent: "")
        batteryItem.identifier = NSUserInterfaceItemIdentifier("battery")
        menu.addItem(batteryItem)

        menu.addItem(NSMenuItem.separator())

        // Privacy exclusions submenu - Phase 10.
        let exclusionsItem = NSMenuItem(title: "Privacy Exclusions", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for (bundleID, name) in Self.commonExclusionApps {
            let item = NSMenuItem(title: name, action: #selector(toggleExclusion(_:)), keyEquivalent: "")
            item.representedObject = bundleID
            item.state = (exclusions?.contains(bundleID) == true) ? .on : .off
            item.target = self
            submenu.addItem(item)
        }
        exclusionsItem.submenu = submenu
        menu.addItem(exclusionsItem)

        // UI Mode submenu - Phase H. Radio-style: ghost / chat / both.
        let uiModeItem = NSMenuItem(title: "UI Mode", action: nil, keyEquivalent: "")
        let uiModeSubmenu = NSMenu()
        let modes: [(title: String, key: String)] = [
            ("Ghost (suggestions only)", "ghost"),
            ("Chat (persistent panel)",  "chat"),
            ("Both",                      "both"),
        ]
        for (title, key) in modes {
            let item = NSMenuItem(title: title, action: #selector(setUIMode(_:)), keyEquivalent: "")
            item.representedObject = key
            item.state = (state.uiMode == key) ? .on : .off
            item.target = self
            uiModeSubmenu.addItem(item)
        }
        uiModeItem.submenu = uiModeSubmenu
        uiModeItem.identifier = NSUserInterfaceItemIdentifier("uiMode")
        menu.addItem(uiModeItem)

        // Stealth auto-hide toggle. Default ON.
        let hideDuringShare = NSMenuItem(
            title: "Hide during screen share",
            action: #selector(toggleScreenShareAutoHide(_:)),
            keyEquivalent: ""
        )
        hideDuringShare.identifier = NSUserInterfaceItemIdentifier("hideDuringShare")
        hideDuringShare.state = state.screenShareAutoHide ? .on : .off
        hideDuringShare.target = self
        menu.addItem(hideDuringShare)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu

        wireObservers(uiModeSubmenu: uiModeSubmenu)
    }

    deinit {
        pulseTimer?.invalidate()
    }

    private func wireObservers(uiModeSubmenu: NSMenu? = nil) {
        if let submenu = uiModeSubmenu {
            state.$uiMode
                .sink { [weak submenu] current in
                    guard let submenu = submenu else { return }
                    for item in submenu.items {
                        let key = item.representedObject as? String ?? ""
                        item.state = (key == current) ? .on : .off
                    }
                }
                .store(in: &cancellables)
        }

        state.$connectionStatus
            .sink { [weak self] status in
                if let item = self?.statusItem.menu?.item(withIdentifier: NSUserInterfaceItemIdentifier("connection")) {
                    item.title = "Connection: \(status)"
                }
            }
            .store(in: &cancellables)

        // Pulse when audio is active OR meeting mode is on.
        Publishers.CombineLatest(state.$audioActive, state.$meetingMode)
            .sink { [weak self] audio, meeting in
                self?.updatePulse(active: audio || meeting)
                if let item = self?.statusItem.menu?.item(withIdentifier: NSUserInterfaceItemIdentifier("recording")) {
                    if meeting {
                        item.title = "Recording: meeting"
                    } else if audio {
                        item.title = "Recording: active"
                    } else {
                        item.title = "Recording: idle"
                    }
                }
            }
            .store(in: &cancellables)

        state.$screenShareAutoHide
            .sink { [weak self] on in
                if let item = self?.statusItem.menu?.item(withIdentifier: NSUserInterfaceItemIdentifier("hideDuringShare")) {
                    item.state = on ? .on : .off
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(state.$batteryLevel, state.$onBattery)
            .sink { [weak self] level, onBattery in
                if let item = self?.statusItem.menu?.item(withIdentifier: NSUserInterfaceItemIdentifier("battery")) {
                    let pct = Int(level * 100)
                    item.title = onBattery ? "Battery: \(pct)% (unplugged)" : "Battery: \(pct)% (charging)"
                }
            }
            .store(in: &cancellables)
    }

    private func updatePulse(active: Bool) {
        if active == pulseActive { return }
        pulseActive = active
        if active {
            // 0.6s period, ~1% CPU. Only runs while recording.
            pulseTimer?.invalidate()
            pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tickPulse() }
            }
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            pulseVisible = true
            statusItem.button?.title = "\u{1F525}"
            statusItem.button?.alphaValue = 1.0
        }
    }

    private func tickPulse() {
        pulseVisible.toggle()
        statusItem.button?.alphaValue = pulseVisible ? 1.0 : 0.35
    }

    @objc func quit() { NSApp.terminate(nil) }

    @objc func toggleScreenShareAutoHide(_ sender: NSMenuItem) {
        state.screenShareAutoHide.toggle()
    }

    @objc func setUIMode(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        state.uiMode = key
    }

    @objc func toggleExclusion(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        exclusions?.toggle(bundleID)
        sender.state = (exclusions?.contains(bundleID) == true) ? .on : .off
    }
}

extension NSMenu {
    func item(withIdentifier id: NSUserInterfaceItemIdentifier) -> NSMenuItem? {
        items.first { $0.identifier == id }
    }
}

import Foundation
import AppKit
import Combine

/// Detects when a screen-sharing-capable application is frontmost or likely
/// actively sharing. Publishes a simple Bool so panels can bind to it.
///
/// This complements `StealthMode.apply(to:enabled:)` (which sets
/// `window.sharingType = .none`). The sharingType baseline works for legacy
/// capture APIs and most older screen-share apps (Teams/Meet/Chime/etc.), but
/// macOS 15+ ScreenCaptureKit ignores it. This detector is the pragmatic
/// fallback: we watch for known screen-share apps becoming frontmost and
/// auto-hide the panels while they are.
@MainActor
final class ScreenShareDetector: ObservableObject {
    @Published private(set) var screenSharingActive = false

    /// Known screen-sharing apps. When one of these is frontmost we assume
    /// the user may be sharing and auto-hide. This is a heuristic; the user
    /// can disable it via the menu bar toggle if they don't want it.
    static let knownShareBundleIDs: Set<String> = [
        "us.zoom.xos",               // Zoom
        "com.microsoft.teams",       // Teams
        "com.microsoft.teams2",      // New Teams
        "com.hnc.Discord",           // Discord (share-enabled)
        "com.apple.FaceTime",        // FaceTime
        "com.amazon.Chime",          // Chime
        "com.google.Chrome",         // Google Meet in Chrome
        "com.google.Chrome.beta",
        "com.apple.Safari",          // Meet in Safari
        "company.thebrowser.Browser",// Arc / Meet
        "com.loom.desktop",          // Loom records
    ]

    private var cancellables = Set<AnyCancellable>()
    private var enabled: Bool = true

    init() {
        // React to frontmost app changes
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notif in
                guard let self = self else { return }
                let bundleID = (notif.userInfo?[NSWorkspace.applicationUserInfoKey]
                                as? NSRunningApplication)?.bundleIdentifier ?? ""
                self.update(frontmostBundleID: bundleID)
            }
            .store(in: &cancellables)

        // Seed initial state with the currently frontmost app
        let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        update(frontmostBundleID: current)
    }

    /// Enable/disable the auto-hide heuristic. When disabled, screenSharingActive
    /// always reports false (panels remain visible regardless).
    func setEnabled(_ on: Bool) {
        enabled = on
        if !on {
            screenSharingActive = false
        } else {
            let current = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            update(frontmostBundleID: current)
        }
    }

    private func update(frontmostBundleID: String) {
        guard enabled else { return }
        let active = Self.knownShareBundleIDs.contains(frontmostBundleID)
        if active != screenSharingActive {
            screenSharingActive = active
            Logger.log("stealth: screenSharing=\(active) app=\(frontmostBundleID)")
        }
    }
}

import Foundation
import ApplicationServices
import AppKit

struct AXSnapshot {
    let appName: String
    let bundleID: String?
    let windowTitle: String
    let focusedElementValue: String?
    let summary: String  // human-readable summary, ~500 chars max
}

enum AXReader {
    /// Best-effort snapshot of the frontmost app's focused window. Never throws or crashes
    /// when AX permission is missing - returns a minimal snapshot built from NSWorkspace.
    static func snapshot() -> AXSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appEl, 1.5)

        var windowTitle = ""
        var focusedWindow: CFTypeRef?
        let wRes = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        if wRes == .success, let w = focusedWindow {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &titleRef)
            if let s = titleRef as? String { windowTitle = s }
        }

        var focusedValue: String? = nil
        var focusedEl: CFTypeRef?
        let fRes = AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focusedEl)
        if fRes == .success, let fe = focusedEl {
            var valRef: CFTypeRef?
            AXUIElementCopyAttributeValue(fe as! AXUIElement, kAXValueAttribute as CFString, &valRef)
            if let s = valRef as? String { focusedValue = String(s.prefix(400)) }
        }

        var sb: [String] = []
        sb.append("App: \(app.localizedName ?? "?")")
        if !windowTitle.isEmpty { sb.append("Window: \(windowTitle)") }
        if let fv = focusedValue, !fv.isEmpty {
            let trimmed = fv.replacingOccurrences(of: "\n", with: " ").prefix(400)
            sb.append("Focus: \(trimmed)")
        }
        let summary = sb.joined(separator: " | ")

        return AXSnapshot(
            appName: app.localizedName ?? "",
            bundleID: app.bundleIdentifier,
            windowTitle: windowTitle,
            focusedElementValue: focusedValue,
            summary: String(summary.prefix(500))
        )
    }
}

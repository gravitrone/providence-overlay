import AppKit

/// Phase 10: apply `NSWindow.sharingType = .none` so the overlay panel is
/// excluded from screen sharing and most screen capture APIs.
///
/// CAVEAT: Apple broke `sharingType = .none` for ScreenCaptureKit in macOS 15+.
/// The panel is still hidden from:
///   - Legacy CGDisplayCreateImage / screencapture CLI
///   - Zoom, Google Meet, Microsoft Teams, Chime (all use legacy capture paths)
/// It IS visible to:
///   - macOS 15+ apps using SCStream (including our own CaptureService).
/// We document the limitation; there is no workaround short of swapping
/// `CGWindowLevel` which Apple also plugged.
@MainActor
enum StealthMode {
    static func apply(to window: NSWindow, enabled: Bool) {
        if enabled {
            window.sharingType = .none
        } else {
            window.sharingType = .readOnly
        }
    }
}

import AppKit

final class ChatPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .resizable, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Transparent window chrome so SwiftUI's rounded + blurred background shows through.
        isOpaque = false
        backgroundColor = .clear
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Stealth hint - ignored by macOS 15+ ScreenCaptureKit but still hides
        // from legacy screen-share APIs (Teams/Meet/Chime).
        sharingType = .none
        // Sensible minimum + maximum.
        minSize = NSSize(width: 280, height: 220)
        maxSize = NSSize(width: 800, height: 1400)
        // Remember user drag position across launches.
        setFrameAutosaveName("ProvidenceChatPanel")
    }

    // A chat panel accepts keyboard focus so the text input works.
    override var canBecomeKey: Bool { true }
    // But not main (doesn't claim menubar/app status).
    override var canBecomeMain: Bool { false }
}

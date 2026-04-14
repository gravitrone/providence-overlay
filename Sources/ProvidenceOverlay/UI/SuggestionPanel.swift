import AppKit

final class SuggestionPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        ignoresMouseEvents = true  // click-through by default
        isFloatingPanel = true
        hidesOnDeactivate = false
    }

    // Required for borderless panel - we never want it stealing focus.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

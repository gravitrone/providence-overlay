import AppKit
import SwiftUI

final class ChatPanel: NSPanel {
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
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Spotlight-style: panel can become key only when a control that needs
        // it (the text input) is clicked. Plain clicks on the bar / toggles
        // do not steal focus from the user's frontmost app. Without this, the
        // earlier `canBecomeKey=false` fix that solved the alpha quantization
        // bug also blocked all mouse interaction.
        becomesKeyOnlyIfNeeded = true
    }

    // canBecomeKey true is required for the text input to accept keystrokes
    // AND for SwiftUI Buttons to receive mouse events. Combined with
    // becomesKeyOnlyIfNeeded above, the panel only actually grabs key focus
    // on demand from key-requiring controls.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

}

/// NSHostingView wrapper that returns true for `acceptsFirstMouse(for:)`. In
/// an accessory (.LSUIElement) app, AppKit suppresses mouse events on a view
/// inside a window that is not the key window of the active application.
/// Without this override, clicking the chat panel while iTerm / Tabby is
/// frontmost would deliver the click to the host app instead of the panel,
/// manifesting as a spinning beachball.
final class ChatHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

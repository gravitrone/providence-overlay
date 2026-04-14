import AppKit
import SwiftUI
import Combine

@MainActor
final class ChatWindowController: NSWindowController {
    private let state: AppState
    private weak var bridgeClient: BridgeClient?
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState, bridgeClient: BridgeClient, onTogglePause: @escaping () -> Void) {
        self.state = state
        self.bridgeClient = bridgeClient

        let screen = Self.primaryScreen()
        let initialFrame = Self.computeInitialFrame(screen: screen, position: state.chatPosition)
        let panel = ChatPanel(contentRect: initialFrame)

        let rootView = ChatRootView(
            onSubmit: { [weak bridgeClient] text in
                bridgeClient?.sendUserQuery(text, source: "chat_input")
            },
            onTogglePause: onTogglePause
        ).environmentObject(state)
        let hostingView = NSHostingView(rootView: rootView)
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12

        super.init(window: panel)

        // Force frame + display commit. Without display:true, SwiftUI's
        // NSHostingView never flushes a first paint for a .nonactivatingPanel
        // in an accessory app, and WindowServer leaves the window off-screen
        // even though AppKit reports isVisible=true.
        panel.setFrame(initialFrame, display: true)
        panel.contentView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()

        // React to uiMode changes, layered with stealth auto-hide: when a
        // known screen-share app is frontmost we hide regardless of uiMode.
        // Skip the initial emission - the panel is already ordered front
        // above; the first transition would otherwise orderOut it when
        // ui_mode defaults to "ghost" before Welcome arrives.
        Publishers.CombineLatest(state.$uiMode, state.$hiddenDueToShare)
            .dropFirst()
            .removeDuplicates(by: { $0 == $1 })
            .sink { [weak self] (mode, hidden) in
                if hidden {
                    self?.window?.orderOut(nil)
                } else {
                    self?.applyMode(mode)
                }
            }
            .store(in: &cancellables)

        // Respect runtime alpha tuning - clamp to [0.3, 1.0] so an unset or
        // accidental zero (e.g. uninitialised TOML field) cannot make the
        // panel invisible.
        state.$chatAlpha
            .removeDuplicates()
            .sink { [weak self] alpha in
                let clamped = max(0.3, min(1.0, alpha))
                self?.window?.alphaValue = CGFloat(clamped)
            }
            .store(in: &cancellables)

        // Re-position on chat_position changes. Drop the initial emission to
        // avoid triggering a hidden-window animator path at startup, which
        // was observed to leave the WindowServer composited alpha stuck near
        // zero on the first show.
        state.$chatPosition
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] position in
                guard let self = self, let window = self.window,
                      let screen = window.screen ?? NSScreen.main else { return }
                let frame = Self.computeInitialFrame(screen: screen, position: position)
                window.setFrame(frame, display: true)
            }
            .store(in: &cancellables)

        window?.alphaValue = CGFloat(max(0.3, min(1.0, state.chatAlpha)))
        // Order front WITHOUT stealing focus - the SuggestionPanel proves
        // that for .nonactivatingPanel + .borderless + content view laid out
        // AFTER assignment to panel.contentView, plain orderFrontRegardless
        // is enough for WindowServer to render.
        window?.orderFrontRegardless()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyMode(_ mode: String) {
        switch mode {
        case "chat", "both":
            window?.orderFrontRegardless()
        default:
            window?.orderOut(nil)
        }
    }

    /// User-invoked toggle (e.g. Cmd+Shift+C hotkey in Phase H). Flips visibility
    /// without changing AppState.uiMode.
    func toggleVisibility() {
        guard let window = window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    /// Pick the screen that contains the menu bar (origin at (0,0) in Cocoa coords).
    /// `NSScreen.main` returns the screen with the key window, which for an
    /// accessory app with no key window can be nil or wrong when multiple
    /// displays are connected.
    private static func primaryScreen() -> NSScreen {
        if let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }) {
            return primary
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private static func computeInitialFrame(screen: NSScreen, position: String) -> NSRect {
        let vf = screen.visibleFrame
        let w: CGFloat = 400
        let h: CGFloat = min(700, vf.height - 40)
        let y = vf.maxY - h - 20
        var x: CGFloat
        switch position {
        case "left":
            x = vf.minX + 20
        case "center":
            x = vf.midX - (w / 2)
        default:  // "right"
            x = vf.maxX - w - 20
        }
        return NSRect(x: x, y: y, width: w, height: h)
    }
}

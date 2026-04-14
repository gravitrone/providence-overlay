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

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let initialFrame = Self.computeInitialFrame(screen: screen, position: state.chatPosition)
        let panel = ChatPanel(contentRect: initialFrame)

        let rootView = ChatRootView(
            onSubmit: { [weak bridgeClient] text in
                bridgeClient?.sendUserQuery(text, source: "chat_input")
            },
            onTogglePause: onTogglePause
        ).environmentObject(state)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = hostingView

        super.init(window: panel)

        // Start hidden; showing is decided by uiMode.
        panel.orderOut(nil)

        // React to uiMode changes.
        state.$uiMode
            .removeDuplicates()
            .sink { [weak self] mode in
                self?.applyMode(mode)
            }
            .store(in: &cancellables)

        // Respect runtime alpha tuning.
        state.$chatAlpha
            .removeDuplicates()
            .sink { [weak self] alpha in
                self?.window?.alphaValue = CGFloat(alpha)
            }
            .store(in: &cancellables)

        // Re-position if the user changes chat_position at runtime (future).
        state.$chatPosition
            .removeDuplicates()
            .sink { [weak self] position in
                guard let self = self, let window = self.window,
                      let screen = window.screen ?? NSScreen.main else { return }
                let frame = Self.computeInitialFrame(screen: screen, position: position)
                window.animator().setFrame(frame, display: true)
            }
            .store(in: &cancellables)

        // Apply initial state.
        window?.alphaValue = CGFloat(state.chatAlpha)
        applyMode(state.uiMode)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func applyMode(_ mode: String) {
        switch mode {
        case "chat", "both":
            showWindow(nil)
            window?.orderFrontRegardless()
        default:  // "ghost" or unknown
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

import AppKit
import SwiftUI
import Combine

@MainActor
final class PanelWindowController: NSWindowController {
    private let state: AppState
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let rect = Self.computeInitialFrame(screen: screen, position: state.panelPosition)
        let panel = SuggestionPanel(contentRect: rect)

        let hostingView = NSHostingView(rootView: PanelRootView().environmentObject(state))
        panel.contentView = hostingView
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.alphaValue = 0  // invisible until something to show

        super.init(window: panel)

        // Fade in on assistant deltas
        state.$latestAssistantText
            .dropFirst()
            .sink { [weak self] text in
                if !text.isEmpty {
                    self?.fadeIn()
                }
            }
            .store(in: &cancellables)

        // Phase C (chat overlay): hide the ghost suggestion panel when uiMode=="chat"
        // (chat-only). Show in "ghost" or "both".
        // Stealth auto-hide layered on top: hide whenever a known screen-share
        // app is frontmost, regardless of uiMode.
        Publishers.CombineLatest(state.$uiMode, state.$hiddenDueToShare)
            .removeDuplicates(by: { $0 == $1 })
            .sink { [weak self] (mode, hidden) in
                guard let panel = self?.window else { return }
                if hidden {
                    panel.orderOut(nil)
                    return
                }
                switch mode {
                case "chat":
                    panel.orderOut(nil)
                default:  // ghost or both
                    panel.orderFrontRegardless()
                }
            }
            .store(in: &cancellables)

        // Phase 10: react to runtime position changes from Welcome.
        state.$panelPosition
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] pos in
                guard let self = self, let window = self.window else { return }
                let s = window.screen ?? NSScreen.main ?? NSScreen.screens.first!
                let newFrame = Self.computeInitialFrame(screen: s, position: pos)
                window.setFrame(newFrame, display: true, animate: true)
            }
            .store(in: &cancellables)
    }

    static func computeInitialFrame(screen: NSScreen, position: String) -> NSRect {
        switch position {
        case "bottom-bar":
            let w = screen.frame.width - 40
            let h: CGFloat = 150
            let x = screen.frame.minX + 20
            let y = screen.frame.minY + 20
            return NSRect(x: x, y: y, width: w, height: h)
        default:
            let w: CGFloat = 300
            let h = screen.frame.height - 40
            let x = screen.frame.maxX - w - 10
            let y = screen.frame.minY + 20
            return NSRect(x: x, y: y, width: w, height: h)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func fadeIn() {
        guard let window = window else { return }
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0.9
        }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(fadeOut), object: nil)
        perform(#selector(fadeOut), with: nil, afterDelay: 30)
    }

    @objc private func fadeOut() {
        guard let window = window else { return }
        // Don't auto-fade while panel is interactive (Cmd+Shift+P engaged).
        if let panel = window as? SuggestionPanel, !panel.ignoresMouseEvents { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }
    }

    /// Toggle panel interactivity via Cmd+Shift+P hotkey.
    func toggleClickThrough() {
        guard let panel = window as? SuggestionPanel else { return }
        panel.ignoresMouseEvents.toggle()
        state.panelInteractive = !panel.ignoresMouseEvents
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        if panel.ignoresMouseEvents {
            panel.contentView?.layer?.borderWidth = 0
        } else {
            panel.contentView?.layer?.borderColor = NSColor.systemOrange.cgColor
            panel.contentView?.layer?.borderWidth = 1
            panel.orderFront(nil)
            panel.animator().alphaValue = 0.9
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(fadeOut), object: nil)
        }
        Logger.log("panel: clickThrough=\(panel.ignoresMouseEvents)")
    }
}

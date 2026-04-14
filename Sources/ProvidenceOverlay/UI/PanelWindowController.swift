import AppKit
import SwiftUI
import Combine

@MainActor
final class PanelWindowController: NSWindowController {
    private let state: AppState
    private var cancellables = Set<AnyCancellable>()

    init(state: AppState) {
        self.state = state

        // Default: right-sidebar, 300 wide
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let w: CGFloat = 300
        let h: CGFloat = screen.frame.height - 40
        let x: CGFloat = screen.frame.maxX - w - 10
        let y: CGFloat = screen.frame.minY + 20
        let rect = NSRect(x: x, y: y, width: w, height: h)
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

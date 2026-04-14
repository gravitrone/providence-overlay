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

        // SwiftUI content
        let hostingView = NSHostingView(rootView: PanelRootView().environmentObject(state))
        panel.contentView = hostingView
        panel.alphaValue = 0  // invisible until we have something to show

        super.init(window: panel)

        // Fade in when assistant text appears
        state.$latestAssistantText
            .dropFirst()
            .sink { [weak self] text in
                if !text.isEmpty {
                    self?.fadeIn()
                }
            }
            .store(in: &cancellables)

        panel.orderFront(nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func fadeIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window?.animator().alphaValue = 0.9
        }
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(fadeOut), object: nil)
        perform(#selector(fadeOut), with: nil, afterDelay: 30)
    }

    @objc private func fadeOut() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            window?.animator().alphaValue = 0
        }
    }
}

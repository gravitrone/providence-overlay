import SwiftUI
import ProvidenceOverlayCore

struct ChatRootView: View {
    @EnvironmentObject var state: AppState
    let onSubmit: (String) -> Void

    @State private var inputText: String = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            // Solid opaque backdrop - the VisualEffectBackground alone gave
            // WindowServer almost nothing to composite, leaving CGS alpha
            // near zero and the panel invisible even with alphaValue = 1.
            Color(red: 0.08, green: 0.06, blue: 0.04).opacity(0.92)
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.55)
            VStack(spacing: 0) {
                ChatStatusView()
                Divider().background(Color.white.opacity(0.1))
                messagesList
                Divider().background(Color.white.opacity(0.1))
                ChatInputView(text: $inputText, focused: $inputFocused, onSubmit: handleSubmit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear { inputFocused = true }
    }

    private func handleSubmit() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        // Safety clear in case the child's clear races.
        inputText = ""
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if state.chatMessages.isEmpty && state.latestAssistantText.isEmpty {
                        emptyState
                    } else {
                        ForEach(state.chatMessages) { msg in
                            ChatBubbleView(message: msg)
                                .id(msg.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.animation(.easeIn(duration: 0.12)),
                                    removal: .identity))
                        }
                        if !state.latestAssistantText.isEmpty {
                            StreamingBubbleView(text: state.latestAssistantText)
                                .id("streaming")
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .onChange(of: state.chatMessages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: state.latestAssistantText) { _, _ in
                if !state.latestAssistantText.isEmpty {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = state.chatMessages.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20))
                .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.20).opacity(0.25))
            Text("The Profaned Core listens.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            Text("Speak, type, or wait for context.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

/// NSVisualEffectView bridge - gives us the .hudWindow vibrancy for blur.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = false
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

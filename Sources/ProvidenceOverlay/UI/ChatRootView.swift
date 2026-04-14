import SwiftUI
import ProvidenceOverlayCore

struct ChatRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider().background(Color.white.opacity(0.1))
            messagesList
            Divider().background(Color.white.opacity(0.1))
            inputStub
        }
        .background(
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.audioActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(state.audioActive ? "Listening" : "Idle")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
            Spacer()
            Text("Providence")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if state.chatMessages.isEmpty && state.latestAssistantText.isEmpty {
                        emptyState
                    } else {
                        ForEach(state.chatMessages) { msg in
                            placeholderBubble(for: msg)
                                .id(msg.id)
                        }
                        // Live-streaming assistant bubble (Phase D renders this properly).
                        if !state.latestAssistantText.isEmpty {
                            streamingBubble
                                .id("streaming")
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: state.chatMessages) { _, _ in
                if let last = state.chatMessages.last {
                    withAnimation(.none) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: state.latestAssistantText) { _, _ in
                proxy.scrollTo("streaming", anchor: .bottom)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("Providence is listening.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
            Text("Speak, type, or wait for context.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func placeholderBubble(for msg: ChatMessage) -> some View {
        HStack {
            if msg.role == .user { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                Text(msg.role == .user ? "You" : "Providence")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                Text(msg.text)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(msg.role == .user ? 0.95 : 0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            if msg.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var streamingBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Providence")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                Text(state.latestAssistantText)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
            )
            Spacer(minLength: 40)
        }
    }

    private var inputStub: some View {
        HStack {
            Text("Ask the Profaned Core…")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
            Text("(Phase E)")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.2))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

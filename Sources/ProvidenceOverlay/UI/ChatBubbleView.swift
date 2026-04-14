import SwiftUI
import ProvidenceOverlayCore

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 4) {
                roleLabel
                Text(message.text)
                    .font(.system(size: 13, weight: message.role == .user ? .semibold : .regular, design: .default))
                    .foregroundColor(textColor)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(bubbleBackground)
            .overlay(bubbleBorder)
            if message.role == .assistant { Spacer(minLength: 32) }
        }
    }

    private var roleLabel: some View {
        Text(message.role == .user ? "YOU" : "PROVIDENCE")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(0.6)
            .foregroundColor(labelColor)
    }

    private var textColor: Color {
        switch message.role {
        case .user: Color(red: 0.95, green: 0.85, blue: 0.70)
        case .assistant: Color(white: 0.92)
        }
    }

    private var labelColor: Color {
        switch message.role {
        case .user: Color(red: 1.0, green: 0.65, blue: 0.20).opacity(0.75)
        case .assistant: Color(white: 0.55)
        }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(red: 0.25, green: 0.14, blue: 0.05).opacity(0.55))
        case .assistant:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }

    @ViewBuilder
    private var bubbleBorder: some View {
        switch message.role {
        case .user:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(red: 1.0, green: 0.65, blue: 0.20).opacity(0.25), lineWidth: 0.5)
        case .assistant:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }
    }
}

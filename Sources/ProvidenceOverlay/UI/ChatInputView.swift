import SwiftUI

/// Real chat input field (Phase E). Enter submits, Shift+Enter inserts newline
/// (best-effort via .onKeyPress on macOS 14+). Empty/whitespace input does nothing.
struct ChatInputView: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Ask the Profaned Core…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.95))
                .lineLimit(1...4)
                .focused(focused)
                .onSubmit(submit)
                .onKeyPress(keys: [.return], phases: .down) { press in
                    // Shift+Enter: let TextField insert a newline.
                    // Plain Enter: submit.
                    if press.modifiers.contains(.shift) {
                        return .ignored
                    }
                    submit()
                    return .handled
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )

            Button(action: submit) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.white.opacity(0.2)
                            : Color(red: 1.0, green: 0.65, blue: 0.20)
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit()
        text = ""
    }
}

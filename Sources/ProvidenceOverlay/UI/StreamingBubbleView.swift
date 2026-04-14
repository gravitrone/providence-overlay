import SwiftUI

struct StreamingBubbleView: View {
    let text: String

    @State private var pulse = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text("PROVIDENCE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.20).opacity(0.75))
                    Circle()
                        .fill(Color(red: 1.0, green: 0.65, blue: 0.20))
                        .frame(width: 5, height: 5)
                        .opacity(pulse ? 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                }
                Text(text)
                    .font(.system(size: 13, design: .default))
                    .foregroundColor(Color(white: 0.92))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(red: 1.0, green: 0.65, blue: 0.20).opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(red: 1.0, green: 0.65, blue: 0.20).opacity(0.35), lineWidth: 0.5)
            )
            Spacer(minLength: 32)
        }
        .onAppear { pulse = true }
    }
}

import SwiftUI

struct SuggestionStreamView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if !state.latestAssistantText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top) {
                        Text(state.latestAssistantText)
                            .foregroundColor(.white)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .foregroundColor(.white.opacity(0.6))
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.latestAssistantText)
    }

    private func dismiss() {
        state.latestAssistantText = ""
    }
}

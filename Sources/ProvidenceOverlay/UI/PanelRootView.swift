import SwiftUI

struct PanelRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !state.latestAssistantText.isEmpty {
                Text(state.latestAssistantText)
                    .foregroundColor(.white)
                    .font(.system(size: 13))
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
            }
            Spacer()
        }
        .padding()
    }
}

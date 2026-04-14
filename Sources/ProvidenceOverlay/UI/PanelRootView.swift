import SwiftUI

struct PanelRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ContextIndicatorView()
            TranscriptView()
            SuggestionStreamView()
            Spacer()
            StatusFooterView()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

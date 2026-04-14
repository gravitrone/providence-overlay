import SwiftUI

/// Ghost suggestion panel root - kept minimal post-rewire. Used by the legacy
/// SuggestionPanel surface for assistant deltas that arrive while the chat
/// panel is hidden. Could be removed entirely if uiMode=ghost is dropped.
struct PanelRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SuggestionStreamView()
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

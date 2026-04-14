import SwiftUI

/// Phase 8: meeting-mode transcript panel. Rendered in `PanelRootView` between
/// `ContextIndicatorView` and `SuggestionStreamView`. Only visible when
/// `state.meetingMode == true` and the rolling transcript is non-empty.
struct TranscriptView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.meetingMode && !state.transcript.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.red)
                    Text("Meeting")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.red)
                    Spacer()
                }
                Text(state.transcript)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(4)
                    .truncationMode(.head)
            }
            .padding(8)
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
        }
    }
}

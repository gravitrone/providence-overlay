import SwiftUI
import ProvidenceOverlayCore

struct ContextIndicatorView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(indicator)
                .foregroundColor(.white.opacity(0.7))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4))
        .cornerRadius(8)
    }

    private var dotColor: Color {
        switch state.currentActivity {
        case .meeting: return .red
        case .coding: return .green
        case .browsing: return .blue
        case .writing: return .purple
        case .idle: return .gray
        case .general: return .yellow
        }
    }

    private var indicator: String {
        if state.currentApp.isEmpty { return "-" }
        return "\(state.currentActivity.rawValue) · \(state.currentApp)"
    }
}

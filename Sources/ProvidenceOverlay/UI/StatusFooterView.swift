import SwiftUI

struct StatusFooterView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.connectionStatus == "connected" ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(statusLine)
                .foregroundColor(.white.opacity(0.5))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var statusLine: String {
        let fps = String(format: "%.1ffps", state.currentFPS)
        let engine = state.engine.isEmpty ? "-" : state.engine
        return "\(state.connectionStatus) · \(state.currentActivity.rawValue) · \(fps) · \(engine)"
    }
}

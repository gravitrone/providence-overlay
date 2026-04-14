import SwiftUI

struct ChatStatusView: View {
    @EnvironmentObject var state: AppState
    let onTogglePause: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            flameLogo
            audioIndicator
            captureIndicator
            Spacer()
            tokenPill
            pauseButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var flameLogo: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11))
                .foregroundColor(Color(red: 1.0, green: 0.65, blue: 0.20).opacity(0.85))
            Text("Providence")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.75))
        }
    }

    private var audioIndicator: some View {
        Image(systemName: state.paused ? "mic.slash.fill"
              : state.audioActive ? "mic.fill" : "mic")
            .font(.system(size: 10))
            .foregroundColor(
                state.paused ? Color.white.opacity(0.25) :
                state.audioActive ? Color.green.opacity(0.9) :
                Color.white.opacity(0.35)
            )
            .help(state.paused ? "Paused" : state.audioActive ? "Listening" : "Idle mic")
    }

    private var captureIndicator: some View {
        Image(systemName: state.paused ? "eye.slash.fill"
              : state.captureActive ? "eye.fill" : "eye")
            .font(.system(size: 10))
            .foregroundColor(
                state.paused ? Color.white.opacity(0.25) :
                state.captureActive ? Color(red: 0.55, green: 0.45, blue: 1.0).opacity(0.85) :
                Color.white.opacity(0.35)
            )
            .help(state.paused ? "Paused" : state.captureActive ? "Observing screen" : "Capture idle")
    }

    private var tokenPill: some View {
        Text(formatTokens(state.sessionTokens))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.55))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
            )
            .help("Tokens injected this session")
    }

    private var pauseButton: some View {
        Button(action: onTogglePause) {
            Image(systemName: state.paused ? "play.fill" : "pause.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(
                    state.paused
                        ? Color(red: 1.0, green: 0.65, blue: 0.20)
                        : Color.white.opacity(0.55)
                )
                .frame(width: 20, height: 20)
                .background(
                    Circle().fill(Color.white.opacity(state.paused ? 0.12 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .help(state.paused ? "Resume ambient capture" : "Pause ambient capture")
    }

    private func formatTokens(_ n: Int) -> String {
        if n < 1000 { return "\(n) tok" }
        let k = Double(n) / 1000
        return String(format: "%.1fk tok", k)
    }
}

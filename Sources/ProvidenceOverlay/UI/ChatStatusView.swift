import SwiftUI

struct ChatStatusView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            flameLogo
            micToggle
            eyeToggle
            Spacer()
            tokenPill
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

    private var micToggle: some View {
        Button(action: { state.micEnabled.toggle() }) {
            Image(systemName: micIconName)
                .font(.system(size: 11))
                .foregroundColor(micColor)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(state.micEnabled ? 0.05 : 0.10)))
        }
        .buttonStyle(.plain)
        .help(state.micEnabled
              ? (state.audioActive ? "Listening - tap to mute" : "Mic on - tap to mute")
              : "Mic muted - tap to enable")
    }

    private var eyeToggle: some View {
        Button(action: { state.screenEnabled.toggle() }) {
            Image(systemName: eyeIconName)
                .font(.system(size: 11))
                .foregroundColor(eyeColor)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(state.screenEnabled ? 0.05 : 0.10)))
        }
        .buttonStyle(.plain)
        .help(state.screenEnabled
              ? (state.captureActive ? "Watching screen - tap to hide" : "Screen on - tap to hide")
              : "Screen hidden - tap to enable")
    }

    private var tokenPill: some View {
        Text(formatTokens(state.sessionTokens))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.55))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .help("Tokens injected this session")
    }

    private var micIconName: String {
        if !state.micEnabled { return "mic.slash.fill" }
        return state.audioActive ? "mic.fill" : "mic"
    }
    private var micColor: Color {
        if !state.micEnabled { return Color.red.opacity(0.75) }
        return state.audioActive ? Color.green.opacity(0.9) : Color.white.opacity(0.45)
    }

    private var eyeIconName: String {
        if !state.screenEnabled { return "eye.slash.fill" }
        return state.captureActive ? "eye.fill" : "eye"
    }
    private var eyeColor: Color {
        if !state.screenEnabled { return Color.red.opacity(0.75) }
        return state.captureActive
            ? Color(red: 0.55, green: 0.45, blue: 1.0).opacity(0.9)
            : Color.white.opacity(0.45)
    }

    private func formatTokens(_ n: Int) -> String {
        if n < 1000 { return "\(n) tok" }
        let k = Double(n) / 1000
        return String(format: "%.1fk tok", k)
    }
}

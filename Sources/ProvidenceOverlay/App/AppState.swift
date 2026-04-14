import Foundation
import Combine
import ProvidenceOverlayCore

/// UserDefaults keys for persisted toggles.
private enum DefaultsKey {
    static let micEnabled = "providence.micEnabled"
    static let screenEnabled = "providence.screenEnabled"
    static let chatPosition = "providence.chatPosition"
    static let chatAlpha = "providence.chatAlpha"
    static let uiMode = "providence.uiMode"
}

@MainActor
final class AppState: ObservableObject {
    @Published var connectionStatus: String = "disconnected"
    @Published var latestAssistantText: String = ""
    @Published var captureActive: Bool = false
    @Published var sessionID: String = ""
    @Published var engine: String = ""
    @Published var model: String = ""
    @Published var emberActive: Bool = false

    // Audio + transcript
    @Published var transcript: String = ""
    @Published var latestSegment: String = ""
    @Published var wakeWordArmed: Bool = false
    @Published var audioActive: Bool = false
    @Published var pttActive: Bool = false

    @Published var ttsEnabled: Bool = false
    @Published var panelPosition: String = "right-sidebar"
    @Published var panelInteractive: Bool = false

    // Chat panel (UserDefaults-backed; defaults registered in OverlayApp).
    @Published var uiMode: String {
        didSet { UserDefaults.standard.set(uiMode, forKey: DefaultsKey.uiMode) }
    }
    @Published var chatHistoryLimit: Int = 50
    @Published var chatAlpha: Double {
        didSet { UserDefaults.standard.set(chatAlpha, forKey: DefaultsKey.chatAlpha) }
    }
    @Published var chatPosition: String {
        didSet { UserDefaults.standard.set(chatPosition, forKey: DefaultsKey.chatPosition) }
    }

    @Published var chatMessages: [ChatMessage] = []

    @Published var sessionTokens: Int = 0
    @Published var lastContextReason: String = ""

    /// Independent privacy kill switches. Persist across launches via UserDefaults.
    /// Setting either to false fully stops the corresponding service and blocks
    /// any context_update emission. Setting back to true restarts it.
    @Published var micEnabled: Bool {
        didSet { UserDefaults.standard.set(micEnabled, forKey: DefaultsKey.micEnabled) }
    }
    @Published var screenEnabled: Bool {
        didSet { UserDefaults.standard.set(screenEnabled, forKey: DefaultsKey.screenEnabled) }
    }

    @Published var screenShareAutoHide: Bool = true
    @Published var hiddenDueToShare: Bool = false

    init() {
        let d = UserDefaults.standard
        // First-launch defaults: both toggles ON, chat position right, alpha 0.92.
        d.register(defaults: [
            DefaultsKey.micEnabled: true,
            DefaultsKey.screenEnabled: true,
            DefaultsKey.chatPosition: "right",
            DefaultsKey.chatAlpha: 0.92,
            DefaultsKey.uiMode: "chat",
        ])
        self.micEnabled = d.bool(forKey: DefaultsKey.micEnabled)
        self.screenEnabled = d.bool(forKey: DefaultsKey.screenEnabled)
        self.uiMode = d.string(forKey: DefaultsKey.uiMode) ?? "chat"
        self.chatAlpha = d.double(forKey: DefaultsKey.chatAlpha)
        self.chatPosition = d.string(forKey: DefaultsKey.chatPosition) ?? "right"
    }

    func addChatMessage(role: ChatMessage.Role, text: String) {
        guard !text.isEmpty else { return }
        let msg = ChatMessage(role: role, text: text)
        chatMessages.append(msg)
        chatMessages = ChatHistory.trimmed(chatMessages, limit: chatHistoryLimit)
    }

    func appendAssistantDelta(_ text: String, finished: Bool) {
        latestAssistantText += text
        if finished {
            let committed = latestAssistantText
            latestAssistantText = ""
            addChatMessage(role: .assistant, text: committed)
        }
    }
}

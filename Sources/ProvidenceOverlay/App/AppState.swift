import Foundation
import Combine
import ProvidenceOverlayCore

@MainActor
final class AppState: ObservableObject {
    @Published var connectionStatus: String = "disconnected"
    @Published var latestAssistantText: String = ""
    @Published var captureActive: Bool = false
    @Published var sessionID: String = ""
    @Published var engine: String = ""
    @Published var model: String = ""
    @Published var emberActive: Bool = false

    // Phase 7 additions
    @Published var currentActivity: Activity = .idle
    @Published var currentApp: String = ""
    @Published var currentFPS: Double = 0.2
    @Published var panelInteractive: Bool = false

    // Phase 8 additions
    @Published var meetingMode: Bool = false
    @Published var transcript: String = ""
    @Published var latestSegment: String = ""
    @Published var wakeWordArmed: Bool = false
    @Published var audioActive: Bool = false
    @Published var pttActive: Bool = false

    // Phase 10 additions
    @Published var wakeWordAllowed: Bool = true   // battery-gated
    @Published var ttsEnabled: Bool = false
    @Published var batteryLevel: Double = 1.0
    @Published var onBattery: Bool = false
    @Published var panelPosition: String = "right-sidebar"

    // Phase A (chat overlay): persistent chat window rendering config.
    @Published var uiMode: String = "ghost"
    @Published var chatHistoryLimit: Int = 50
    @Published var chatAlpha: Double = 0.92
    @Published var chatPosition: String = "right"
}

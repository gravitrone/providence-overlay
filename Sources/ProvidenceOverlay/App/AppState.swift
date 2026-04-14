import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var connectionStatus: String = "disconnected"
    @Published var latestAssistantText: String = ""
    @Published var captureActive: Bool = false
    @Published var sessionID: String = ""
    @Published var engine: String = ""
    @Published var model: String = ""
    @Published var emberActive: Bool = false
}

import XCTest
import ProvidenceOverlayCore

// Inline testable mirror of AppState persistence logic.
// Uses an injected UserDefaults suite so each test is fully isolated.
@MainActor
private final class AppStateTestable: ObservableObject {
    private enum K {
        static let micEnabled   = "providence.micEnabled"
        static let screenEnabled = "providence.screenEnabled"
        static let chatPosition = "providence.chatPosition"
        static let chatAlpha    = "providence.chatAlpha"
        static let uiMode       = "providence.uiMode"
    }

    @Published var micEnabled: Bool {
        didSet { defaults.set(micEnabled, forKey: K.micEnabled) }
    }
    @Published var screenEnabled: Bool {
        didSet { defaults.set(screenEnabled, forKey: K.screenEnabled) }
    }
    @Published var uiMode: String {
        didSet { defaults.set(uiMode, forKey: K.uiMode) }
    }
    @Published var chatAlpha: Double {
        didSet { defaults.set(chatAlpha, forKey: K.chatAlpha) }
    }
    @Published var chatPosition: String {
        didSet { defaults.set(chatPosition, forKey: K.chatPosition) }
    }
    @Published var chatMessages: [ChatMessage] = []
    @Published var chatHistoryLimit: Int = 50

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: [
            K.micEnabled:    true,
            K.screenEnabled: true,
            K.chatPosition:  "right",
            K.chatAlpha:     0.92,
            K.uiMode:        "chat",
        ])
        self.micEnabled    = defaults.bool(forKey: K.micEnabled)
        self.screenEnabled = defaults.bool(forKey: K.screenEnabled)
        self.uiMode        = defaults.string(forKey: K.uiMode) ?? "chat"
        self.chatAlpha     = defaults.double(forKey: K.chatAlpha)
        self.chatPosition  = defaults.string(forKey: K.chatPosition) ?? "right"
    }

    func addChatMessage(role: ChatMessage.Role, text: String) {
        guard !text.isEmpty else { return }
        let msg = ChatMessage(role: role, text: text)
        chatMessages.append(msg)
        chatMessages = ChatHistory.trimmed(chatMessages, limit: chatHistoryLimit)
    }

    private static let K2 = K.self // silence unused warning
}

// Helper to create a fresh isolated UserDefaults suite.
private func freshDefaults() -> UserDefaults {
    let suite = "test.\(UUID().uuidString)"
    guard let ud = UserDefaults(suiteName: suite) else {
        fatalError("could not create UserDefaults suite: \(suite)")
    }
    return ud
}

final class AppStateTests: XCTestCase {

    // MARK: - Default value tests

    @MainActor func testMicEnabledDefaultsToTrueOnFirstLaunch() {
        let state = AppStateTestable(defaults: freshDefaults())
        XCTAssertTrue(state.micEnabled)
    }

    @MainActor func testScreenEnabledDefaultsToTrueOnFirstLaunch() {
        let state = AppStateTestable(defaults: freshDefaults())
        XCTAssertTrue(state.screenEnabled)
    }

    @MainActor func testChatAlphaDefaultsTo0_92() {
        let state = AppStateTestable(defaults: freshDefaults())
        XCTAssertEqual(state.chatAlpha, 0.92, accuracy: 0.001)
    }

    @MainActor func testChatPositionDefaultsToRight() {
        let state = AppStateTestable(defaults: freshDefaults())
        XCTAssertEqual(state.chatPosition, "right")
    }

    @MainActor func testUIModeDefaultsToChat() {
        let state = AppStateTestable(defaults: freshDefaults())
        XCTAssertEqual(state.uiMode, "chat")
    }

    // MARK: - didSet write-through tests

    @MainActor func testMicEnabledWritesToUserDefaults() {
        let ud = freshDefaults()
        let state = AppStateTestable(defaults: ud)
        state.micEnabled = false
        XCTAssertFalse(ud.bool(forKey: "providence.micEnabled"))
    }

    @MainActor func testScreenEnabledWritesToUserDefaults() {
        let ud = freshDefaults()
        let state = AppStateTestable(defaults: ud)
        state.screenEnabled = false
        XCTAssertFalse(ud.bool(forKey: "providence.screenEnabled"))
    }

    @MainActor func testChatAlphaRoundtripsThroughDefaults() {
        let ud = freshDefaults()
        let state = AppStateTestable(defaults: ud)
        state.chatAlpha = 0.75
        XCTAssertEqual(ud.double(forKey: "providence.chatAlpha"), 0.75, accuracy: 0.001)
    }

    // MARK: - Persistence across re-init

    @MainActor func testMicEnabledPersistsAcrossInit() {
        let ud = freshDefaults()
        let state1 = AppStateTestable(defaults: ud)
        state1.micEnabled = false
        let state2 = AppStateTestable(defaults: ud)
        XCTAssertFalse(state2.micEnabled)
    }

    @MainActor func testScreenEnabledPersistsAcrossInit() {
        let ud = freshDefaults()
        let state1 = AppStateTestable(defaults: ud)
        state1.screenEnabled = false
        let state2 = AppStateTestable(defaults: ud)
        XCTAssertFalse(state2.screenEnabled)
    }

    // MARK: - chatPosition accepts values

    @MainActor func testChatPositionAcceptsLeftCenterRight() {
        let state = AppStateTestable(defaults: freshDefaults())
        for position in ["left", "center", "right"] {
            state.chatPosition = position
            XCTAssertEqual(state.chatPosition, position)
        }
    }

    // MARK: - Chat history trim

    @MainActor func testAddChatMessageTrimsAtLimit() {
        let state = AppStateTestable(defaults: freshDefaults())
        state.chatHistoryLimit = 5
        for i in 0..<10 {
            state.addChatMessage(role: .user, text: "msg \(i)")
        }
        XCTAssertEqual(state.chatMessages.count, 5)
        // should be the last 5 messages
        XCTAssertEqual(state.chatMessages.last?.text, "msg 9")
        XCTAssertEqual(state.chatMessages.first?.text, "msg 5")
    }
}

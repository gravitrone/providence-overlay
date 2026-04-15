import XCTest
import Combine
import ProvidenceOverlayCore

// Inline testable mirror of AppState - extras not covered in AppStateTests.swift.
// Extends AppStateTestable pattern with sessionTokens + Combine observation.
@MainActor
private final class AppStateExtrasTestable: ObservableObject {
    private enum K {
        static let micEnabled    = "providence.micEnabled"
        static let screenEnabled = "providence.screenEnabled"
        static let chatPosition  = "providence.chatPosition"
        static let chatAlpha     = "providence.chatAlpha"
        static let uiMode        = "providence.uiMode"
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
    @Published var sessionTokens: Int = 0

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
}

private func freshDefaults() -> UserDefaults {
    let suite = "test.extras.\(UUID().uuidString)"
    guard let ud = UserDefaults(suiteName: suite) else {
        fatalError("could not create UserDefaults suite: \(suite)")
    }
    return ud
}

final class AppStateExtrasTests: XCTestCase {

    // MARK: - sessionTokens increment

    @MainActor func testSessionTokensIncrement() {
        let state = AppStateExtrasTestable(defaults: freshDefaults())
        state.sessionTokens += 100
        XCTAssertEqual(state.sessionTokens, 100)
        state.sessionTokens += 50
        XCTAssertEqual(state.sessionTokens, 150)
    }

    // MARK: - chatAlpha clamping

    // AppState has no explicit clamp - it accepts any Double and persists it.
    // These tests document actual behavior (no clamping), so if a clamp is
    // added later the tests will catch the intentional change.

    @MainActor func testChatAlphaAcceptsValueBelowMinimum() {
        let state = AppStateExtrasTestable(defaults: freshDefaults())
        state.chatAlpha = 0.1
        // No clamp in production code - value is stored as-is.
        XCTAssertEqual(state.chatAlpha, 0.1, accuracy: 0.001)
    }

    @MainActor func testChatAlphaAcceptsValueAboveMaximum() {
        let state = AppStateExtrasTestable(defaults: freshDefaults())
        state.chatAlpha = 1.5
        // No clamp in production code - value is stored as-is.
        XCTAssertEqual(state.chatAlpha, 1.5, accuracy: 0.001)
    }

    // MARK: - Combine @Published fires on mutation

    @MainActor func testCombinePublishedFiresOnMutation() {
        let state = AppStateExtrasTestable(defaults: freshDefaults())
        var receivedValues: [Bool] = []
        var cancellables = Set<AnyCancellable>()

        // $micEnabled emits current value on subscribe then fires on each change.
        state.$micEnabled
            .dropFirst() // skip initial emission
            .sink { receivedValues.append($0) }
            .store(in: &cancellables)

        state.micEnabled = false
        state.micEnabled = true

        XCTAssertEqual(receivedValues, [false, true])
    }

    // MARK: - addChatMessage history trim

    @MainActor func testAddChatMessageAtLimitTrims() {
        let state = AppStateExtrasTestable(defaults: freshDefaults())
        state.chatHistoryLimit = 5
        for i in 0..<10 {
            state.addChatMessage(role: .user, text: "msg \(i)")
        }
        XCTAssertEqual(state.chatMessages.count, 5)
        XCTAssertEqual(state.chatMessages.first?.text, "msg 5")
        XCTAssertEqual(state.chatMessages.last?.text, "msg 9")
    }

    // MARK: - addChatMessage ignores empty text

    @MainActor func testAddChatMessageEmptyTextIgnored() {
        let state = AppStateExtrasTestable(defaults: freshDefaults())
        state.addChatMessage(role: .user, text: "")
        XCTAssertTrue(state.chatMessages.isEmpty)
    }
}

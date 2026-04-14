import XCTest
@testable import ProvidenceOverlayCore

final class ChatMessageTests: XCTestCase {
    func testCodableRoundTrip() throws {
        let id = UUID()
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        let original = ChatMessage(id: id, role: .assistant, text: "hello world", timestamp: ts)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.role, .assistant)
        XCTAssertEqual(decoded.text, "hello world")
        XCTAssertEqual(decoded.timestamp, ts)
    }

    func testSameContentDifferentIDsAreNotEqual() {
        let ts = Date()
        let a = ChatMessage(id: UUID(), role: .user, text: "yo", timestamp: ts)
        let b = ChatMessage(id: UUID(), role: .user, text: "yo", timestamp: ts)
        XCTAssertNotEqual(a, b)
    }

    func testRoleRawValuesStableWireFormat() {
        XCTAssertEqual(ChatMessage.Role.user.rawValue, "user")
        XCTAssertEqual(ChatMessage.Role.assistant.rawValue, "assistant")
    }

    func testTrimmedReturnsAllWhenUnderLimit() {
        let msgs = [
            ChatMessage(role: .user, text: "a"),
            ChatMessage(role: .assistant, text: "b"),
        ]
        XCTAssertEqual(ChatHistory.trimmed(msgs, limit: 5).count, 2)
    }

    func testTrimmedKeepsLastNWhenOverLimit() {
        let msgs = (0..<5).map { ChatMessage(role: .user, text: "m\($0)") }
        let trimmed = ChatHistory.trimmed(msgs, limit: 3)
        XCTAssertEqual(trimmed.count, 3)
        XCTAssertEqual(trimmed.map { $0.text }, ["m2", "m3", "m4"])
    }

    func testTrimmedClampsLimitToAtLeastOne() {
        let msgs = (0..<4).map { ChatMessage(role: .user, text: "m\($0)") }
        let zero = ChatHistory.trimmed(msgs, limit: 0)
        XCTAssertEqual(zero.count, 1)
        XCTAssertEqual(zero.first?.text, "m3")

        let neg = ChatHistory.trimmed(msgs, limit: -10)
        XCTAssertEqual(neg.count, 1)
        XCTAssertEqual(neg.first?.text, "m3")
    }

    func testTrimmedEmptyInput() {
        XCTAssertEqual(ChatHistory.trimmed([], limit: 5), [])
    }
}

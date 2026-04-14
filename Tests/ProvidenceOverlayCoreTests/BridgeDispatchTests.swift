// Tests for BridgeClient envelope parsing + type dispatch + fault tolerance.
//
// BridgeClient lives in the executable target ProvidenceOverlay, which Swift's
// @testable import cannot reach. We mirror the production `handleLine` dispatch
// against a FakeAppState + a local JSONLScanner copy (mirroring JSONLScanner
// behavior) so chunk buffering and type routing are exercised end-to-end.
//
// If BridgeClient.swift's handleLine logic diverges, contract tests here will
// need to be re-verified. Contract-based, not regression-based testing.

import XCTest
import Foundation

// MARK: - Mirrored protocol structs

private struct TestEnvelope: Codable {
    let v: Int?
    let type: String
    let id: String?
    let data: TestAnyCodable?
}

private struct TestWelcome: Codable {
    let session_id: String?
    let engine: String?
    let model: String?
    let ember_active: Bool?
    let cwd: String?
    let timestamp: String?
    let tts_enabled: Bool?
}

private struct TestAssistantDelta: Codable {
    let text: String
    let finished: Bool?
}

private struct TestEmberState: Codable {
    let active: Bool
    let paused: Bool?
    let tick_count: Int?
}

private struct TestContextAck: Codable {
    let timestamp: String?
    let accepted: Bool?
    let tokens: Int?
    let reason: String?
    let mode: String?
    let total_session_tokens: Int?
}

private enum TestMsgType {
    static let welcome = "welcome"
    static let assistantDelta = "assistant_delta"
    static let emberState = "ember_state"
    static let contextAck = "context_ack"
    static let bye = "bye"
    static let sessionEvent = "session_event"
}

private struct TestAnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self.value = NSNull()
        } else if let b = try? c.decode(Bool.self) {
            self.value = b
        } else if let i = try? c.decode(Int64.self) {
            self.value = i
        } else if let d = try? c.decode(Double.self) {
            self.value = d
        } else if let s = try? c.decode(String.self) {
            self.value = s
        } else if let arr = try? c.decode([TestAnyCodable].self) {
            self.value = arr.map { $0.value }
        } else if let obj = try? c.decode([String: TestAnyCodable].self) {
            self.value = obj.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "TestAnyCodable: unsupported"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        // unused in tests
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let obj: Any = (value is NSNull) ? NSNull() : value
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Fake AppState

@MainActor
private final class FakeAppState {
    var sessionID: String = ""
    var engine: String = ""
    var model: String = ""
    var emberActive: Bool = false
    var ttsEnabled: Bool = false
    var latestAssistantText: String = ""
    var chatHistory: [(role: String, text: String)] = []
    var sessionTokens: Int = 0
    var lastContextReason: String = ""
    var disconnectCalls: Int = 0

    func appendAssistantDelta(_ text: String, finished: Bool) {
        latestAssistantText += text
        if finished {
            let committed = latestAssistantText
            latestAssistantText = ""
            chatHistory.append((role: "assistant", text: committed))
        }
    }
}

// MARK: - JSONL scanner mirror (mirrors JSONLScanner.swift)

private final class TestScanner {
    private var buffer = Data()

    func feed(_ chunk: Data) -> [String] {
        buffer.append(chunk)
        var lines: [String] = []
        while let newlineIdx = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIdx]
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
            buffer.removeSubrange(..<(newlineIdx + 1))
        }
        return lines
    }
}

// MARK: - Dispatcher mirror (mirrors BridgeClient.handleLine)

@MainActor
private final class BridgeDispatcherTestable {
    let state: FakeAppState
    var onAssistantDelta: ((String, Bool) -> Void)?
    var onWelcome: ((TestWelcome) -> Void)?

    init(state: FakeAppState) { self.state = state }

    func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let env: TestEnvelope
        do {
            env = try JSONDecoder().decode(TestEnvelope.self, from: data)
        } catch {
            return // malformed envelope tolerated
        }

        switch env.type {
        case TestMsgType.welcome:
            if let w = try? env.data?.decode(TestWelcome.self) {
                state.sessionID = w.session_id ?? ""
                state.engine = w.engine ?? ""
                state.model = w.model ?? ""
                state.emberActive = w.ember_active ?? false
                if let tts = w.tts_enabled { state.ttsEnabled = tts }
                onWelcome?(w)
            }
        case TestMsgType.assistantDelta:
            if let d = try? env.data?.decode(TestAssistantDelta.self) {
                state.appendAssistantDelta(d.text, finished: d.finished ?? false)
                onAssistantDelta?(d.text, d.finished ?? false)
            }
        case TestMsgType.emberState:
            if let s = try? env.data?.decode(TestEmberState.self) {
                state.emberActive = s.active
            }
        case TestMsgType.contextAck:
            if let a = try? env.data?.decode(TestContextAck.self) {
                if let total = a.total_session_tokens {
                    state.sessionTokens = total
                }
                if let reason = a.reason {
                    state.lastContextReason = reason
                }
            }
        case TestMsgType.bye:
            state.disconnectCalls += 1
        case TestMsgType.sessionEvent:
            break // log only
        default:
            break // unknown type ignored
        }
    }

    /// Feed raw bytes through scanner and dispatch each complete line.
    func feed(_ scanner: TestScanner, _ chunk: Data) {
        for line in scanner.feed(chunk) {
            handleLine(line)
        }
    }
}

// MARK: - Tests

@MainActor
final class BridgeDispatchTests: XCTestCase {
    private var state: FakeAppState!
    private var dispatcher: BridgeDispatcherTestable!
    private var scanner: TestScanner!

    override func setUp() {
        super.setUp()
        state = FakeAppState()
        dispatcher = BridgeDispatcherTestable(state: state)
        scanner = TestScanner()
    }

    override func tearDown() {
        state = nil
        dispatcher = nil
        scanner = nil
        super.tearDown()
    }

    private func bytes(_ s: String) -> Data { s.data(using: .utf8)! }

    func testWelcomeUpdatesSessionAndEmber() {
        var welcomeFired = false
        dispatcher.onWelcome = { _ in welcomeFired = true }
        let line = #"{"v":1,"type":"welcome","data":{"session_id":"abc","ember_active":true,"engine":"claude","model":"opus"}}"# + "\n"
        dispatcher.feed(scanner, bytes(line))
        XCTAssertEqual(state.sessionID, "abc")
        XCTAssertEqual(state.engine, "claude")
        XCTAssertEqual(state.model, "opus")
        XCTAssertTrue(state.emberActive)
        XCTAssertTrue(welcomeFired)
    }

    func testAssistantDeltaFinishedFalseAppends() {
        let line = #"{"v":1,"type":"assistant_delta","data":{"text":"hi","finished":false}}"# + "\n"
        dispatcher.feed(scanner, bytes(line))
        XCTAssertEqual(state.latestAssistantText, "hi")
        XCTAssertTrue(state.chatHistory.isEmpty, "not yet committed")
    }

    func testAssistantDeltaFinishedTrueCommitsToHistory() {
        let a = #"{"v":1,"type":"assistant_delta","data":{"text":"hello ","finished":false}}"# + "\n"
        let b = #"{"v":1,"type":"assistant_delta","data":{"text":"world","finished":true}}"# + "\n"
        dispatcher.feed(scanner, bytes(a))
        dispatcher.feed(scanner, bytes(b))
        XCTAssertEqual(state.latestAssistantText, "", "latest cleared on commit")
        XCTAssertEqual(state.chatHistory.count, 1)
        XCTAssertEqual(state.chatHistory.first?.text, "hello world")
        XCTAssertEqual(state.chatHistory.first?.role, "assistant")
    }

    func testContextAckUpdatesSessionTokens() {
        let line = #"{"v":1,"type":"context_ack","data":{"tokens":42,"total_session_tokens":100,"reason":"frame"}}"# + "\n"
        dispatcher.feed(scanner, bytes(line))
        XCTAssertEqual(state.sessionTokens, 100)
        XCTAssertEqual(state.lastContextReason, "frame")
    }

    func testEmberStateToggle() {
        state.emberActive = true
        let line = #"{"v":1,"type":"ember_state","data":{"active":false,"paused":false}}"# + "\n"
        dispatcher.feed(scanner, bytes(line))
        XCTAssertFalse(state.emberActive)
    }

    func testByeDisconnects() {
        let line = #"{"v":1,"type":"bye","data":{"reason":"server shutdown"}}"# + "\n"
        dispatcher.feed(scanner, bytes(line))
        XCTAssertEqual(state.disconnectCalls, 1)
    }

    func testMalformedEnvelopeTolerated() {
        dispatcher.feed(scanner, bytes("not json at all\n"))
        // Next envelope still dispatches fine.
        let line = #"{"v":1,"type":"welcome","data":{"session_id":"z"}}"# + "\n"
        dispatcher.feed(scanner, bytes(line))
        XCTAssertEqual(state.sessionID, "z")
    }

    func testUnknownTypeIgnored() {
        let line = #"{"v":1,"type":"unknown_type_xyz","data":{"foo":"bar"}}"# + "\n"
        dispatcher.feed(scanner, bytes(line))
        XCTAssertEqual(state.sessionID, "")
        XCTAssertEqual(state.chatHistory.count, 0)
        XCTAssertEqual(state.disconnectCalls, 0)
    }

    func testPartialLineBuffered() {
        let full = #"{"v":1,"type":"welcome","data":{"session_id":"split"}}"# + "\n"
        let cut = full.index(full.startIndex, offsetBy: 20)
        let first = String(full[..<cut])
        let second = String(full[cut...])
        dispatcher.feed(scanner, bytes(first))
        XCTAssertEqual(state.sessionID, "", "no newline yet, no dispatch")
        dispatcher.feed(scanner, bytes(second))
        XCTAssertEqual(state.sessionID, "split")
    }

    func testMultipleEnvelopesInOneChunk() {
        let a = #"{"v":1,"type":"welcome","data":{"session_id":"one","engine":"claude"}}"# + "\n"
        let b = #"{"v":1,"type":"assistant_delta","data":{"text":"yo","finished":true}}"# + "\n"
        dispatcher.feed(scanner, bytes(a + b))
        XCTAssertEqual(state.sessionID, "one")
        XCTAssertEqual(state.engine, "claude")
        XCTAssertEqual(state.chatHistory.count, 1)
        XCTAssertEqual(state.chatHistory.first?.text, "yo")
    }

    func testWelcomeMissingFieldsDefaultGracefully() {
        // Missing optional fields must not crash - they default to empty/false.
        let line = #"{"v":1,"type":"welcome","data":{}}"# + "\n"
        dispatcher.feed(scanner, bytes(line))
        XCTAssertEqual(state.sessionID, "")
        XCTAssertEqual(state.engine, "")
        XCTAssertFalse(state.emberActive)
    }

    func testSessionEventLoggedNoStateChange() {
        let line = #"{"v":1,"type":"session_event","id":"evt-1","data":{"kind":"interrupt"}}"# + "\n"
        dispatcher.feed(scanner, bytes(line))
        XCTAssertEqual(state.sessionID, "")
        XCTAssertEqual(state.chatHistory.count, 0)
    }
}

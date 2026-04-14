import XCTest
import Foundation

// MARK: - Inline testable copies of Protocol.swift types
// @testable import ProvidenceOverlay is not available (executable target).
// Types below are verbatim copies kept in sync with Sources/ProvidenceOverlay/Bridge/Protocol.swift.

private struct Envelope: Codable {
    let v: Int
    let type: String
    let id: String?
    let data: AnyCodable?
}

private struct Hello: Codable {
    let client_version: String
    let capabilities: [String]
    let pid: Int
}

private struct Goodbye: Codable {
    let reason: String?
}

private struct UserQuery: Codable {
    let text: String
    let source: String
}

private struct EmberRequest: Codable {
    let desired: String
}

private struct Interrupt: Codable {
    let reason: String?
}

private struct UIEvent: Codable {
    let kind: String
    let target: String?
    let meta: [String: String]?
}

private struct ContextUpdate: Codable {
    let timestamp: String
    let screenshot_png_b64: String?
    let transcript: String?
    let change_kind: String
}

private struct Welcome: Codable {
    let session_id: String?
    let engine: String?
    let model: String?
    let ember_active: Bool?
    let cwd: String?
    let timestamp: String?
    let tts_enabled: Bool?
}

private struct AssistantDelta: Codable {
    let text: String
    let finished: Bool?
}

private struct EmberState: Codable {
    let active: Bool
    let paused: Bool
    let tick_count: Int?
}

private struct SessionEvent: Codable {
    let kind: String
    let meta: [String: String]?
}

private struct ContextAck: Codable {
    let timestamp: String?
    let accepted: Bool?
    let tokens: Int?
    let reason: String?
    let mode: String?
    let total_session_tokens: Int?
}

private struct Bye: Codable {
    let reason: String?
}

private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

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
        } else if let arr = try? c.decode([AnyCodable].self) {
            self.value = arr.map { $0.value }
        } else if let obj = try? c.decode([String: AnyCodable].self) {
            self.value = obj.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "AnyCodable: unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try c.encodeNil()
        case let b as Bool:
            try c.encode(b)
        case let i as Int:
            try c.encode(i)
        case let i as Int64:
            try c.encode(i)
        case let d as Double:
            try c.encode(d)
        case let s as String:
            try c.encode(s)
        case let arr as [Any]:
            try c.encode(arr.map { AnyCodable($0) })
        case let obj as [String: Any]:
            try c.encode(obj.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "AnyCodable: cannot encode \(type(of: value))"
                )
            )
        }
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: jsonObject(), options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func jsonObject() -> Any {
        switch value {
        case is NSNull: return NSNull()
        case let arr as [Any]: return arr
        case let obj as [String: Any]: return obj
        default: return value
        }
    }
}

// MARK: - Helpers

private let encoder = JSONEncoder()
private let decoder = JSONDecoder()

private func roundtrip<T: Codable>(_ value: T) throws -> T {
    let data = try encoder.encode(value)
    return try decoder.decode(T.self, from: data)
}

private func anyCodableRoundtrip(json: String) throws -> AnyCodable {
    guard let data = json.data(using: .utf8) else {
        throw NSError(domain: "test", code: 0, userInfo: [NSLocalizedDescriptionKey: "bad utf8"])
    }
    let decoded = try decoder.decode(AnyCodable.self, from: data)
    let reencoded = try encoder.encode(decoded)
    return try decoder.decode(AnyCodable.self, from: reencoded)
}

// MARK: - Tests

final class ProtocolTests: XCTestCase {

    // MARK: AnyCodable JSON kinds

    func testAnyCodableNullRoundtrip() throws {
        let result = try anyCodableRoundtrip(json: "null")
        XCTAssertTrue(result.value is NSNull)
    }

    func testAnyCodableBoolRoundtrip() throws {
        let result = try anyCodableRoundtrip(json: "true")
        guard let b = result.value as? Bool else {
            XCTFail("expected Bool, got \(type(of: result.value))")
            return
        }
        XCTAssertTrue(b)
    }

    func testAnyCodableIntRoundtrip() throws {
        let result = try anyCodableRoundtrip(json: "42")
        guard let i = result.value as? Int64 else {
            XCTFail("expected Int64, got \(type(of: result.value))")
            return
        }
        XCTAssertEqual(i, 42)
    }

    func testAnyCodableDoubleRoundtrip() throws {
        let result = try anyCodableRoundtrip(json: "3.14")
        guard let d = result.value as? Double else {
            XCTFail("expected Double, got \(type(of: result.value))")
            return
        }
        XCTAssertEqual(d, 3.14, accuracy: 1e-10)
    }

    func testAnyCodableStringRoundtrip() throws {
        let result = try anyCodableRoundtrip(json: "\"hello\"")
        guard let s = result.value as? String else {
            XCTFail("expected String, got \(type(of: result.value))")
            return
        }
        XCTAssertEqual(s, "hello")
    }

    func testAnyCodableArrayRoundtrip() throws {
        let result = try anyCodableRoundtrip(json: "[1,2,3]")
        guard let arr = result.value as? [Any] else {
            XCTFail("expected [Any], got \(type(of: result.value))")
            return
        }
        XCTAssertEqual(arr.count, 3)
        guard let first = arr.first as? Int64 else {
            XCTFail("expected Int64 element")
            return
        }
        XCTAssertEqual(first, 1)
    }

    func testAnyCodableObjectRoundtrip() throws {
        let result = try anyCodableRoundtrip(json: #"{"key":"value"}"#)
        guard let obj = result.value as? [String: Any] else {
            XCTFail("expected [String: Any], got \(type(of: result.value))")
            return
        }
        guard let val = obj["key"] as? String else {
            XCTFail("expected String for key")
            return
        }
        XCTAssertEqual(val, "value")
    }

    func testAnyCodableNestedObject() throws {
        let json = #"{"outer":{"inner":42}}"#
        let result = try anyCodableRoundtrip(json: json)
        guard let obj = result.value as? [String: Any],
              let outer = obj["outer"] as? [String: Any],
              let inner = outer["inner"] as? Int64 else {
            XCTFail("nested object structure wrong")
            return
        }
        XCTAssertEqual(inner, 42)
    }

    // MARK: AnyCodable.decode helper

    func testAnyCodableDecodeToConcreteStruct() throws {
        let json = #"{"text":"hi","finished":true}"#
        guard let data = json.data(using: .utf8) else {
            XCTFail("utf8 encode failed")
            return
        }
        let wrapped = try decoder.decode(AnyCodable.self, from: data)
        let delta = try wrapped.decode(AssistantDelta.self)
        XCTAssertEqual(delta.text, "hi")
        XCTAssertEqual(delta.finished, true)
    }

    // MARK: Protocol struct round-trips

    func testHelloRoundtrip() throws {
        let original = Hello(client_version: "1.0.0", capabilities: ["streaming", "tools"], pid: 12345)
        let copy = try roundtrip(original)
        XCTAssertEqual(copy.client_version, original.client_version)
        XCTAssertEqual(copy.capabilities, original.capabilities)
        XCTAssertEqual(copy.pid, original.pid)
    }

    func testWelcomeRoundtripWithAllFields() throws {
        let original = Welcome(
            session_id: "sess-abc",
            engine: "claude",
            model: "claude-sonnet-4-5",
            ember_active: true,
            cwd: "/Users/alxx/Code",
            timestamp: "2026-04-14T00:00:00Z",
            tts_enabled: false
        )
        let copy = try roundtrip(original)
        XCTAssertEqual(copy.session_id, original.session_id)
        XCTAssertEqual(copy.engine, original.engine)
        XCTAssertEqual(copy.model, original.model)
        XCTAssertEqual(copy.ember_active, original.ember_active)
        XCTAssertEqual(copy.cwd, original.cwd)
        XCTAssertEqual(copy.timestamp, original.timestamp)
        XCTAssertEqual(copy.tts_enabled, original.tts_enabled)
    }

    func testWelcomeRoundtripOptionalsAbsent() throws {
        let original = Welcome(
            session_id: nil,
            engine: nil,
            model: nil,
            ember_active: nil,
            cwd: nil,
            timestamp: nil,
            tts_enabled: nil
        )
        let copy = try roundtrip(original)
        XCTAssertNil(copy.session_id)
        XCTAssertNil(copy.engine)
        XCTAssertNil(copy.model)
        XCTAssertNil(copy.ember_active)
        XCTAssertNil(copy.cwd)
        XCTAssertNil(copy.timestamp)
        XCTAssertNil(copy.tts_enabled)
    }

    func testContextUpdateWithScreenshotRoundtrip() throws {
        let original = ContextUpdate(
            timestamp: "2026-04-14T00:00:00Z",
            screenshot_png_b64: "iVBORw0KGgo=",
            transcript: nil,
            change_kind: "frame"
        )
        let copy = try roundtrip(original)
        XCTAssertEqual(copy.timestamp, original.timestamp)
        XCTAssertEqual(copy.screenshot_png_b64, original.screenshot_png_b64)
        XCTAssertNil(copy.transcript)
        XCTAssertEqual(copy.change_kind, original.change_kind)
    }

    func testContextUpdateTranscriptOnlyRoundtrip() throws {
        let original = ContextUpdate(
            timestamp: "2026-04-14T01:00:00Z",
            screenshot_png_b64: nil,
            transcript: "user said something",
            change_kind: "transcript_only"
        )
        let copy = try roundtrip(original)
        XCTAssertEqual(copy.timestamp, original.timestamp)
        XCTAssertNil(copy.screenshot_png_b64)
        XCTAssertEqual(copy.transcript, original.transcript)
        XCTAssertEqual(copy.change_kind, original.change_kind)
    }

    func testAssistantDeltaFinishedTrueRoundtrip() throws {
        let original = AssistantDelta(text: "done", finished: true)
        let copy = try roundtrip(original)
        XCTAssertEqual(copy.text, original.text)
        XCTAssertEqual(copy.finished, true)
    }

    func testAssistantDeltaFinishedFalseRoundtrip() throws {
        let original = AssistantDelta(text: "streaming...", finished: false)
        let copy = try roundtrip(original)
        XCTAssertEqual(copy.text, original.text)
        XCTAssertEqual(copy.finished, false)
    }

    func testEmberStateRoundtrip() throws {
        let original = EmberState(active: true, paused: false, tick_count: 42)
        let copy = try roundtrip(original)
        XCTAssertEqual(copy.active, original.active)
        XCTAssertEqual(copy.paused, original.paused)
        XCTAssertEqual(copy.tick_count, original.tick_count)
    }

    func testContextAckAllFieldsRoundtrip() throws {
        let original = ContextAck(
            timestamp: "2026-04-14T00:00:00Z",
            accepted: true,
            tokens: 1024,
            reason: nil,
            mode: "auto",
            total_session_tokens: 8192
        )
        let copy = try roundtrip(original)
        XCTAssertEqual(copy.timestamp, original.timestamp)
        XCTAssertEqual(copy.accepted, original.accepted)
        XCTAssertEqual(copy.tokens, original.tokens)
        XCTAssertNil(copy.reason)
        XCTAssertEqual(copy.mode, original.mode)
        XCTAssertEqual(copy.total_session_tokens, original.total_session_tokens)
    }

    func testEnvelopeWrappingContextUpdateRoundtrip() throws {
        // Build ContextUpdate, encode to AnyCodable via JSON, then wrap in Envelope.
        let cu = ContextUpdate(
            timestamp: "2026-04-14T00:00:00Z",
            screenshot_png_b64: "abc123==",
            transcript: nil,
            change_kind: "user-invoked"
        )
        let cuData = try encoder.encode(cu)
        guard let cuDict = try JSONSerialization.jsonObject(with: cuData) as? [String: Any] else {
            XCTFail("could not parse ContextUpdate as dict")
            return
        }
        let envelope = Envelope(v: 1, type: "context_update", id: "req-1", data: AnyCodable(cuDict))
        let copy = try roundtrip(envelope)

        XCTAssertEqual(copy.v, 1)
        XCTAssertEqual(copy.type, "context_update")
        XCTAssertEqual(copy.id, "req-1")

        guard let dataValue = copy.data?.value as? [String: Any],
              let ts = dataValue["timestamp"] as? String,
              let ck = dataValue["change_kind"] as? String,
              let shot = dataValue["screenshot_png_b64"] as? String else {
            XCTFail("envelope data did not decode to expected dict")
            return
        }
        XCTAssertEqual(ts, "2026-04-14T00:00:00Z")
        XCTAssertEqual(ck, "user-invoked")
        XCTAssertEqual(shot, "abc123==")
    }
}

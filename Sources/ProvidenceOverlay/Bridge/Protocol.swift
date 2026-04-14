import Foundation

// MARK: - Envelope

struct Envelope: Codable {
    let v: Int
    let type: String
    let id: String?
    let data: AnyCodable?
}

// MARK: - Client -> Server

struct Hello: Codable {
    let client_version: String
    let capabilities: [String]
    let pid: Int
}

struct Goodbye: Codable {
    let reason: String?
}

struct UserQuery: Codable {
    let text: String
    let source: String // "wake_word"|"push_to_talk"|"panel_input"
}

struct EmberRequest: Codable {
    let desired: String  // "active"|"inactive"|"paused"|"resumed"
}

struct Interrupt: Codable {
    let reason: String?
}

struct UIEvent: Codable {
    let kind: String
    let target: String?
    let meta: [String: String]?
}

struct ContextUpdate: Codable {
    let timestamp: String
    let active_app: String
    let window_title: String
    let activity: String
    let ocr_text: String?
    let ax_summary: String?
    let transcript: String?
    let pixel_hash: String?
    let change_kind: String
}

// MARK: - Server -> Client

struct Welcome: Codable {
    let session_id: String?
    let engine: String?
    let model: String?
    let ember_active: Bool?
    let cwd: String?
    let timestamp: String?
}

struct AssistantDelta: Codable {
    let text: String
    let finished: Bool?
}

struct EmberState: Codable {
    let active: Bool
    let paused: Bool
    let tick_count: Int?
}

struct SessionEvent: Codable {
    let kind: String
    let meta: [String: String]?
}

struct ContextAck: Codable {
    let timestamp: String?
    let accepted: Bool?
}

struct Bye: Codable {
    let reason: String?
}

// MARK: - Type constants

enum MessageType {
    static let hello = "hello"
    static let goodbye = "goodbye"
    static let welcome = "welcome"
    static let contextUpdate = "context_update"
    static let userQuery = "user_query"
    static let emberRequest = "ember_request"
    static let interrupt = "interrupt"
    static let uiEvent = "ui_event"
    static let sessionEvent = "session_event"
    static let assistantDelta = "assistant_delta"
    static let emberState = "ember_state"
    static let contextAck = "context_ack"
    static let bye = "bye"
}

// MARK: - AnyCodable
// Minimal JSON-any wrapper. Enough for Phase 6 to round-trip the nested `data` field
// without building explicit Codable structs for every possible envelope payload.
// TODO(phase7+): dedupe with bridge-side AnyCodable by moving this into ProvidenceOverlayCore.
struct AnyCodable: Codable {
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

    /// Helper: round-trip through JSON to decode the wrapped value as a concrete type.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: jsonObject(), options: [.fragmentsAllowed])
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Convert the stored value into something JSONSerialization accepts.
    private func jsonObject() -> Any {
        switch value {
        case is NSNull: return NSNull()
        case let arr as [Any]: return arr
        case let obj as [String: Any]: return obj
        default: return value
        }
    }
}

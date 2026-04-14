import Foundation
import Darwin
import ProvidenceOverlayCore

enum BridgeError: Error {
    case socketCreateFailed(Int32)
    case socketConnectFailed(Int32)
    case pathTooLong
}

@MainActor
final class BridgeClient {
    private let socketPath: String
    private let state: AppState
    private var socket: Int32 = -1
    private var readTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var cancelled = false

    /// Phase 10: hook for TTS + welcome handling. Set by OverlayApp after construction.
    var onAssistantDelta: ((String, Bool) -> Void)?
    var onWelcome: ((Welcome) -> Void)?

    init(socketPath: String, state: AppState) {
        self.socketPath = socketPath
        self.state = state
    }

    func connect() {
        cancelled = false
        readTask = Task { await connectLoop() }
    }

    func disconnect() {
        cancelled = true
        sendGoodbye()
        closeSocket()
        readTask?.cancel()
    }

    /// Reconnect loop with exponential backoff, capped at 30s.
    private func connectLoop() async {
        while !Task.isCancelled && !cancelled {
            state.connectionStatus = "connecting"
            do {
                try connectOnce()
                reconnectAttempt = 0
                await readLoop()
            } catch {
                Logger.log("bridge: connect error: \(error)")
            }
            if cancelled { break }
            state.connectionStatus = "disconnected"
            let backoff = min(30.0, pow(2.0, Double(reconnectAttempt)))
            reconnectAttempt += 1
            try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        }
    }

    private func connectOnce() throws {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if fd < 0 {
            throw BridgeError.socketCreateFailed(errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // sun_path is a fixed-size C array of 104 bytes on macOS.
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        if pathBytes.count >= capacity {
            Darwin.close(fd)
            throw BridgeError.pathTooLong
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) { cptr in
                for (i, b) in pathBytes.enumerated() {
                    cptr[i] = CChar(bitPattern: b)
                }
                cptr[pathBytes.count] = 0
            }
        }

        let rc = withUnsafePointer(to: &addr) { saPtr -> Int32 in
            saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if rc < 0 {
            let e = errno
            Darwin.close(fd)
            throw BridgeError.socketConnectFailed(e)
        }

        self.socket = fd
    }

    private func readLoop() async {
        state.connectionStatus = "connected"
        sendHello()

        let scanner = JSONLScanner()
        let fd = self.socket
        var buffer = [UInt8](repeating: 0, count: 16384)
        while !Task.isCancelled && !cancelled {
            let n = buffer.withUnsafeMutableBufferPointer { buf -> Int in
                Darwin.recv(fd, buf.baseAddress, buf.count, 0)
            }
            if n <= 0 {
                break  // EOF or error
            }
            let data = Data(bytes: buffer, count: n)
            let lines = await scanner.feed(data)
            for line in lines {
                handleLine(line)
            }
        }
        closeSocket()
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            Logger.log("bridge: non-utf8 line: \(line.prefix(120))")
            return
        }
        let env: Envelope
        do {
            env = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            Logger.log("bridge: malformed envelope: \(line.prefix(200)) err=\(error)")
            return
        }

        switch env.type {
        case MessageType.welcome:
            if let w = try? env.data?.decode(Welcome.self) {
                state.sessionID = w.session_id ?? ""
                state.engine = w.engine ?? ""
                state.model = w.model ?? ""
                state.emberActive = w.ember_active ?? false
                if let tts = w.tts_enabled { state.ttsEnabled = tts }
                if let pos = w.position, !pos.isEmpty { state.panelPosition = pos }
                if let mode = w.ui_mode, !mode.isEmpty { state.uiMode = mode }
                if let limit = w.chat_history_limit, limit > 0 { state.chatHistoryLimit = limit }
                Logger.log("bridge: welcome session=\(state.sessionID) engine=\(state.engine) tts=\(state.ttsEnabled) pos=\(state.panelPosition)")
                onWelcome?(w)
            }
        case MessageType.assistantDelta:
            if let d = try? env.data?.decode(AssistantDelta.self) {
                state.appendAssistantDelta(d.text, finished: d.finished ?? false)
                onAssistantDelta?(d.text, d.finished ?? false)
            }
        case MessageType.emberState:
            if let s = try? env.data?.decode(EmberState.self) {
                state.emberActive = s.active
            }
        case MessageType.sessionEvent:
            // Phase 6: log only.
            Logger.log("bridge: session_event \(env.id ?? "")")
        case MessageType.contextAck:
            // Phase 6: log only.
            break
        case MessageType.bye:
            Logger.log("bridge: received bye, disconnecting")
            closeSocket()
        default:
            Logger.log("bridge: unhandled type: \(env.type)")
        }
    }

    // MARK: - Send helpers

    func sendUserQuery(_ text: String, source: String) {
        // Append to local chat history first so UI reflects the send optimistically.
        state.addChatMessage(role: .user, text: text)
        sendEnvelope(type: MessageType.userQuery, data: UserQuery(text: text, source: source))
    }

    func sendContextUpdate(_ update: ContextUpdate) {
        sendEnvelope(type: MessageType.contextUpdate, data: update)
    }

    func sendEmberRequest(_ desired: String) {
        sendEnvelope(type: MessageType.emberRequest, data: EmberRequest(desired: desired))
    }

    func sendInterrupt(reason: String? = nil) {
        sendEnvelope(type: MessageType.interrupt, data: Interrupt(reason: reason))
    }

    func sendUIEvent(_ kind: String, target: String? = nil, meta: [String: String]? = nil) {
        sendEnvelope(type: MessageType.uiEvent, data: UIEvent(kind: kind, target: target, meta: meta))
    }

    private func sendHello() {
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let hello = Hello(client_version: version, capabilities: ["scstream"], pid: pid)
        sendEnvelope(type: MessageType.hello, data: hello)
    }

    private func sendGoodbye() {
        sendEnvelope(type: MessageType.goodbye, data: Goodbye(reason: "quit"))
    }

    private func sendEnvelope<T: Encodable>(type: String, data: T) {
        guard socket >= 0 else { return }
        do {
            // Build inline JSON: {"v":1,"type":"...","data":<payload>}
            let encoder = JSONEncoder()
            let payloadData = try encoder.encode(data)
            guard let payloadStr = String(data: payloadData, encoding: .utf8) else { return }
            let escapedType = type.replacingOccurrences(of: "\"", with: "\\\"")
            let line = "{\"v\":1,\"type\":\"\(escapedType)\",\"data\":\(payloadStr)}\n"
            let bytes = Array(line.utf8)
            var offset = 0
            let fd = socket
            while offset < bytes.count {
                let written = bytes.withUnsafeBufferPointer { buf -> Int in
                    Darwin.send(fd, buf.baseAddress!.advanced(by: offset), buf.count - offset, 0)
                }
                if written <= 0 {
                    Logger.log("bridge: send failed errno=\(errno)")
                    return
                }
                offset += written
            }
        } catch {
            Logger.log("bridge: encode error: \(error)")
        }
    }

    private func closeSocket() {
        if socket >= 0 {
            Darwin.close(socket)
            socket = -1
        }
    }
}

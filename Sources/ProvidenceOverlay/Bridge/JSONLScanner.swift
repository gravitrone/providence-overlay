import Foundation

/// Reads newline-delimited JSON from an AsyncStream of Data.
/// Handles partial line buffering across chunk boundaries.
actor JSONLScanner {
    private var buffer = Data()

    /// Feed a chunk of bytes. Returns any complete lines extracted.
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

    func reset() { buffer.removeAll() }
}

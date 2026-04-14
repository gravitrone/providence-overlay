import Foundation

/// ErrorSignal detects error-like patterns in captured screen text (AX summary,
/// OCR, or speech transcript). Used by ContextCompressor to fast-path emit a
/// context_update with change_kind="error" when something looks broken on the
/// user's screen, bypassing the normal 30s heartbeat gate.
public enum ErrorSignal {
    private static let patterns: [NSRegularExpression] = {
        let strs = [
            #"(?i)\berror[:\s]"#,
            #"(?i)\btraceback\b"#,
            #"(?i)\bfailed\b"#,
            #"(?i)\btest.*fail"#,
            #"(?i)\bpanic:"#,
            #"(?i)\bexception\b"#,
            #"(?i)\bbuild failed\b"#,
            #"(?i)\bcompile[r]? error\b"#,
            #"(?i)\bnot found\b"#,
            #"(?i)\bconnection refused\b"#,
            #"(?i)\btimeout\b"#,
            #"(?i)\bSIGSEGV\b"#,
        ]
        return strs.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Returns true if any of the fields contain an error-like pattern.
    public static func detect(ax: String, ocr: String?, transcript: String?) -> Bool {
        let haystack = [ax, ocr ?? "", transcript ?? ""].joined(separator: "\n")
        if haystack.isEmpty { return false }
        for pattern in patterns {
            let range = NSRange(haystack.startIndex..., in: haystack)
            if pattern.firstMatch(in: haystack, range: range) != nil {
                return true
            }
        }
        return false
    }
}

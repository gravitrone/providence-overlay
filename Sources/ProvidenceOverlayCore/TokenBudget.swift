import Foundation

/// TokenBudget is a rough approximation of the token count of a string,
/// used for accounting purposes only (not for strict context-window math).
///
/// Heuristic: 1 token ≈ 4 UTF-8 bytes of English text. Good enough for
/// logging + `/overlay cost` display.
public enum TokenBudget {
    public static func estimate(_ s: String) -> Int {
        return max(1, s.utf8.count / 4)
    }

    public static func summarize(_ update: ContextUpdateFields) -> Int {
        let parts = [
            update.app,
            update.windowTitle,
            update.axSummary,
            update.ocr ?? "",
            update.transcript ?? "",
        ]
        return estimate(parts.joined(separator: "\n"))
    }
}

/// ContextUpdateFields is the minimal pure-Swift projection of an overlay
/// ContextUpdate needed for token accounting. Keeping it here in the Core
/// target avoids dragging AppKit/Foundation bridge types into tests.
public struct ContextUpdateFields: Sendable {
    public let app: String
    public let windowTitle: String
    public let axSummary: String
    public let ocr: String?
    public let transcript: String?

    public init(app: String, windowTitle: String, axSummary: String, ocr: String?, transcript: String?) {
        self.app = app
        self.windowTitle = windowTitle
        self.axSummary = axSummary
        self.ocr = ocr
        self.transcript = transcript
    }
}

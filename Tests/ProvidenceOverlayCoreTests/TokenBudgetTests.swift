import XCTest
@testable import ProvidenceOverlayCore

final class TokenBudgetTests: XCTestCase {
    func testEstimate100CharsIs25Tokens() {
        let s = String(repeating: "a", count: 100)
        XCTAssertEqual(TokenBudget.estimate(s), 25)
    }

    func testEstimateEmptyStringReturnsAtLeast1() {
        XCTAssertEqual(TokenBudget.estimate(""), 1)
    }

    func testEstimateShortStringReturnsAtLeast1() {
        XCTAssertEqual(TokenBudget.estimate("hi"), 1)
    }

    func testSummarizeCountsAllFields() {
        let fields = ContextUpdateFields(
            app: String(repeating: "a", count: 40),   // 40
            windowTitle: String(repeating: "b", count: 40), // 40
            axSummary: String(repeating: "c", count: 40),   // 40
            ocr: String(repeating: "d", count: 40),         // 40
            transcript: String(repeating: "e", count: 40)   // 40
        )
        // joined with 4 newline separators -> 200 + 4 = 204 bytes -> 51 tokens.
        let tokens = TokenBudget.summarize(fields)
        XCTAssertEqual(tokens, 51)
    }

    func testSummarizeHandlesNilOptionals() {
        let fields = ContextUpdateFields(
            app: "a",
            windowTitle: "b",
            axSummary: "c",
            ocr: nil,
            transcript: nil
        )
        // Should not crash, nil becomes empty string.
        XCTAssertGreaterThanOrEqual(TokenBudget.summarize(fields), 1)
    }
}

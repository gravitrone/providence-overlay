import XCTest
@testable import ProvidenceOverlayCore

final class TranscriptSimilarityTests: XCTestCase {
    func testIdenticalStringsReturnOne() {
        let s = "the quick brown fox jumps over the lazy dog"
        XCTAssertEqual(TranscriptSimilarity.jaccard(s, s), 1.0, accuracy: 1e-9)
    }

    func testDisjointStringsReturnZero() {
        let a = "alpha beta gamma delta epsilon"
        let b = "one two three four five"
        XCTAssertEqual(TranscriptSimilarity.jaccard(a, b), 0.0, accuracy: 1e-9)
    }

    func testBothEmptyReturnsOne() {
        XCTAssertEqual(TranscriptSimilarity.jaccard("", ""), 1.0, accuracy: 1e-9)
    }

    func testOneEmptyReturnsZero() {
        XCTAssertEqual(TranscriptSimilarity.jaccard("hello world friend", ""), 0.0, accuracy: 1e-9)
        XCTAssertEqual(TranscriptSimilarity.jaccard("", "hello world friend"), 0.0, accuracy: 1e-9)
    }

    func testPartialOverlapIsBetweenZeroAndOne() {
        // Shared prefix "the quick brown fox jumps over" + diverging tail.
        let a = "the quick brown fox jumps over the lazy dog"
        let b = "the quick brown fox jumps over a sleepy cat"
        let sim = TranscriptSimilarity.jaccard(a, b)
        XCTAssertGreaterThan(sim, 0.0)
        XCTAssertLessThan(sim, 1.0)
        // Rough bound - at least some trigrams overlap.
        XCTAssertGreaterThan(sim, 0.2)
    }

    func testShortInputFallbackUsesWordSet() {
        // Under 3 words each - fallback path: word-set Jaccard.
        // "hello world" vs "hello there" - intersection={hello}, union={hello,world,there} -> 1/3.
        let sim = TranscriptSimilarity.jaccard("hello world", "hello there")
        XCTAssertEqual(sim, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testPunctuationAndCaseIgnored() {
        let a = "Hello, World! How are you today?"
        let b = "hello world how are you today"
        XCTAssertEqual(TranscriptSimilarity.jaccard(a, b), 1.0, accuracy: 1e-9)
    }
}

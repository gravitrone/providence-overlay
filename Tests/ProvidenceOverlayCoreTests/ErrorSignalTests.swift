import XCTest
@testable import ProvidenceOverlayCore

final class ErrorSignalTests: XCTestCase {
    func testEmptyInputReturnsFalse() {
        XCTAssertFalse(ErrorSignal.detect(ax: "", ocr: nil, transcript: nil))
    }

    func testErrorColonMatches() {
        XCTAssertTrue(ErrorSignal.detect(ax: "error: something broke", ocr: nil, transcript: nil))
    }

    func testErrorWordBoundaryAvoidsFalsePositive() {
        // "error_handler" should NOT match - no colon or space after "error".
        XCTAssertFalse(ErrorSignal.detect(ax: "my error_handler function is fine", ocr: nil, transcript: nil))
    }

    func testTracebackMatches() {
        XCTAssertTrue(ErrorSignal.detect(
            ax: "Traceback (most recent call last):\n  File \"x.py\"",
            ocr: nil,
            transcript: nil
        ))
    }

    func testFailedMatches() {
        XCTAssertTrue(ErrorSignal.detect(ax: "build failed with 3 errors", ocr: nil, transcript: nil))
    }

    func testPanicMatches() {
        XCTAssertTrue(ErrorSignal.detect(ax: "panic: runtime error", ocr: nil, transcript: nil))
    }

    func testExceptionMatches() {
        XCTAssertTrue(ErrorSignal.detect(ax: "", ocr: "uncaught exception at line 42", transcript: nil))
    }

    func testConnectionRefusedMatches() {
        XCTAssertTrue(ErrorSignal.detect(ax: "", ocr: nil, transcript: "connection refused on port 5432"))
    }

    func testTimeoutMatches() {
        XCTAssertTrue(ErrorSignal.detect(ax: "request timeout after 30s", ocr: nil, transcript: nil))
    }

    func testTestFailMatches() {
        XCTAssertTrue(ErrorSignal.detect(ax: "test TestFoo failed", ocr: nil, transcript: nil))
    }

    func testBenignTextDoesNotMatch() {
        XCTAssertFalse(ErrorSignal.detect(
            ax: "func main() { fmt.Println(\"hello\") }",
            ocr: "some readme text here",
            transcript: "we are going to discuss the plan"
        ))
    }

    func testSigsegvMatches() {
        XCTAssertTrue(ErrorSignal.detect(ax: "process died with SIGSEGV", ocr: nil, transcript: nil))
    }

    func testCaseInsensitiveMatches() {
        XCTAssertTrue(ErrorSignal.detect(ax: "ERROR: things broke", ocr: nil, transcript: nil))
    }
}

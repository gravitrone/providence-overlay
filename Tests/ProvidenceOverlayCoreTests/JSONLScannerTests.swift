// Tests for JSONLScanner buffered newline-delimited UTF-8 line extractor.
//
// JSONLScanner lives in the executable target ProvidenceOverlay (which Swift's
// @testable import cannot reach for executables). We mirror the production
// actor here; the test verifies the actor's CONTRACT. If production behavior
// diverges, update both. If the contract itself changes, update these tests.

import XCTest

private actor JSONLScannerTestable {
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

    func reset() { buffer.removeAll() }
}

final class JSONLScannerTests: XCTestCase {
    func testSingleLineSingleChunk() async {
        let s = JSONLScannerTestable()
        let got = await s.feed(Data("hello\n".utf8))
        XCTAssertEqual(got, ["hello"])
    }

    func testMultipleLinesSingleChunk() async {
        let s = JSONLScannerTestable()
        let got = await s.feed(Data("a\nb\nc\n".utf8))
        XCTAssertEqual(got, ["a", "b", "c"])
    }

    func testPartialLineCarriesToNextChunk() async {
        let s = JSONLScannerTestable()
        let first = await s.feed(Data("abc".utf8))
        XCTAssertEqual(first, [], "no newline yet so no lines")
        let second = await s.feed(Data("def\n".utf8))
        XCTAssertEqual(second, ["abcdef"])
    }

    func testEmptyChunkReturnsNoLines() async {
        let s = JSONLScannerTestable()
        let got = await s.feed(Data())
        XCTAssertEqual(got, [])
    }

    func testTrailingNoNewlineBuffersUntilCompletes() async {
        let s = JSONLScannerTestable()
        _ = await s.feed(Data("abc".utf8))
        let got = await s.feed(Data("\n".utf8))
        XCTAssertEqual(got, ["abc"])
    }

    func testEmptyLineBetweenLinesIsDropped() async {
        // Current production behavior: empty lines filtered out.
        let s = JSONLScannerTestable()
        let got = await s.feed(Data("a\n\nb\n".utf8))
        XCTAssertEqual(got, ["a", "b"], "empty lines are dropped by the scanner")
    }

    func testCRLFPreservesCarriageReturn() async {
        // Scanner only splits on \n so the \r stays attached to the prior line.
        let s = JSONLScannerTestable()
        let got = await s.feed(Data("a\r\nb\n".utf8))
        XCTAssertEqual(got, ["a\r", "b"])
    }

    func testVeryLongLineSingleChunk() async {
        let s = JSONLScannerTestable()
        let payload = String(repeating: "x", count: 10_000)
        let got = await s.feed(Data((payload + "\n").utf8))
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got[0].count, 10_000)
    }

    func testInvalidUTF8LineIsDropped() async {
        // Production drops lines that are not valid UTF-8.
        let s = JSONLScannerTestable()
        var bad = Data([0xFF, 0xFE, 0xFD])
        bad.append(Data("\n".utf8))
        let got = await s.feed(bad)
        XCTAssertEqual(got, [], "invalid UTF-8 line is dropped")
    }

    func testMultipleConsumesInterleavedReassembles() async {
        let s = JSONLScannerTestable()
        let first = await s.feed(Data("al".utf8))
        XCTAssertEqual(first, [])
        let second = await s.feed(Data("pha\nbe".utf8))
        XCTAssertEqual(second, ["alpha"])
        let third = await s.feed(Data("ta\n".utf8))
        XCTAssertEqual(third, ["beta"])
    }

    func testResetClearsBuffer() async {
        let s = JSONLScannerTestable()
        _ = await s.feed(Data("partial".utf8))
        await s.reset()
        let got = await s.feed(Data("\n".utf8))
        // After reset, the earlier "partial" is gone; the "\n" yields an
        // empty line which is dropped.
        XCTAssertEqual(got, [])
    }

    func testTwoLinesWithPartialSuffix() async {
        let s = JSONLScannerTestable()
        let got = await s.feed(Data("first\nsecond\nthird".utf8))
        XCTAssertEqual(got, ["first", "second"], "two complete + one pending")
        let finish = await s.feed(Data("\n".utf8))
        XCTAssertEqual(finish, ["third"])
    }
}

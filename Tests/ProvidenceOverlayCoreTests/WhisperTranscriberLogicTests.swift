import XCTest

// Inline testable mirror of WhisperTranscriber buffer + overlap + trim logic.
// No MLX loaded - purely stateless buffer math.
@MainActor
private final class WhisperBufferLogic {
    let windowSamples: Int = 16000 * 5   // 80_000

    var isReady: Bool
    private var audioBuffer: [Float] = []
    var rollingTranscript: String = ""

    // Capture for test assertions
    var transcribeCallCount: Int = 0
    var transcribedSamples: [[Float]] = []

    init(isReady: Bool = true) {
        self.isReady = isReady
    }

    func feed(_ samples: [Float]) {
        guard isReady else { return }
        audioBuffer.append(contentsOf: samples)

        if audioBuffer.count >= windowSamples {
            let chunk = Array(audioBuffer.prefix(windowSamples))
            audioBuffer.removeFirst(windowSamples / 2)
            transcribeCallCount += 1
            transcribedSamples.append(chunk)
            // Simulate appending transcribed text (use placeholder)
            let text = "x"
            let joined = (rollingTranscript + " " + text)
                .trimmingCharacters(in: .whitespaces)
            rollingTranscript = joined.count > 600
                ? String(joined.suffix(600))
                : joined
        }
    }

    func appendTranscript(_ text: String) {
        let joined = (rollingTranscript + " " + text)
            .trimmingCharacters(in: .whitespaces)
        rollingTranscript = joined.count > 600
            ? String(joined.suffix(600))
            : joined
    }

    func clear() {
        audioBuffer.removeAll()
        rollingTranscript = ""
        transcribeCallCount = 0
        transcribedSamples.removeAll()
    }
}

@MainActor
final class WhisperTranscriberLogicTests: XCTestCase {

    // 1. Feed below threshold - no transcribe call
    func testBufferAccumulatesUntilWindowThreshold() {
        let logic = WhisperBufferLogic()
        // 40_000 samples = 0.5 * windowSamples (80_000)
        let samples = [Float](repeating: 0.1, count: 40_000)
        logic.feed(samples)
        XCTAssertEqual(logic.transcribeCallCount, 0)
    }

    // 2. Crossing window threshold triggers exactly 1 transcribe call with windowSamples samples
    func testCrossingWindowThresholdTriggersTranscribe() {
        let logic = WhisperBufferLogic()
        // 80_001 samples crosses the 80_000 threshold
        let samples = [Float](repeating: 0.2, count: 80_001)
        logic.feed(samples)
        XCTAssertEqual(logic.transcribeCallCount, 1)
        XCTAssertEqual(logic.transcribedSamples.first?.count, logic.windowSamples)
    }

    // 3. 50% overlap - second window fires after another windowSamples/2 samples
    func test50PercentOverlapAdvance() {
        let logic = WhisperBufferLogic()
        let half = logic.windowSamples / 2   // 40_000

        // First fill: 80_000 samples -> 1 call, buffer now has 40_000 remaining
        logic.feed([Float](repeating: 0.3, count: logic.windowSamples))
        XCTAssertEqual(logic.transcribeCallCount, 1)

        // Feed another half window (40_000) -> buffer now 80_000 -> 2nd call
        logic.feed([Float](repeating: 0.3, count: half))
        XCTAssertEqual(logic.transcribeCallCount, 2)
    }

    // 4. Rolling transcript trimmed to last 600 chars when it exceeds that
    func testRollingTranscriptTrimmedTo600Chars() {
        let logic = WhisperBufferLogic()
        // Each chunk is 100 chars; 11 chunks = 1110 chars before trimming
        let chunk = String(repeating: "a", count: 100)
        for _ in 0..<11 {
            logic.appendTranscript(chunk)
        }
        // After trimming, rollingTranscript must be at most 600 chars
        XCTAssertLessThanOrEqual(logic.rollingTranscript.count, 600)
        XCTAssertEqual(logic.rollingTranscript.count, 600)
    }

    // 5. !isReady is a no-op - nothing accumulates, no transcribe
    func testNotReadyIsNoOp() {
        let logic = WhisperBufferLogic(isReady: false)
        logic.feed([Float](repeating: 0.5, count: 200_000))
        XCTAssertEqual(logic.transcribeCallCount, 0)
    }

    // 6. clear() resets buffer - subsequent sub-threshold feed won't fire;
    //    but a full window after clear fires exactly once
    func testClearResetsBuffer() {
        let logic = WhisperBufferLogic()
        // Partially fill buffer
        logic.feed([Float](repeating: 0.6, count: 60_000))
        XCTAssertEqual(logic.transcribeCallCount, 0)

        // Clear resets everything
        logic.clear()
        XCTAssertEqual(logic.transcribeCallCount, 0)

        // Sub-threshold after clear - still no call
        logic.feed([Float](repeating: 0.6, count: 40_000))
        XCTAssertEqual(logic.transcribeCallCount, 0)

        // Full window after clear - exactly 1 call
        logic.feed([Float](repeating: 0.6, count: 40_000))
        XCTAssertEqual(logic.transcribeCallCount, 1)
    }
}

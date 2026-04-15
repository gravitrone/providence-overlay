import XCTest
@testable import ProvidenceOverlayCore

// MARK: - Inline-testable BackoffCalculator

/// Pure backoff math extracted from BridgeClient.connectLoop()
/// Formula: min(30.0, pow(2.0, Double(attempt)))
struct BackoffCalculator {
    let cap: Double
    let base: Double

    init(cap: Double = 30.0, base: Double = 1.0) {
        self.cap = cap
        self.base = base
    }

    func delay(attempt: Int) -> Double {
        guard attempt >= 0 else { return base }
        return min(cap, base * pow(2.0, Double(attempt)))
    }
}

// MARK: - Inline-testable ReconnectLoopTestable

/// Simulates the reconnect loop logic without a real socket.
/// Mirrors the BridgeClient.connectLoop() flow:
///   - on each iteration: connectOnce(), reset counter on success, backoff on failure
///   - cancelled flag breaks loop
final class ReconnectLoopTestable {
    var cancelled = false
    private(set) var reconnectAttempt = 0
    private(set) var iterationsRun = 0
    private(set) var connectCalled = 0

    /// When true the next connectOnce call succeeds and resets the counter.
    var simulateSuccess = false

    /// Max iterations safety guard (prevents runaway loops in tests).
    var maxIterations = 10

    func runLoop() {
        while !cancelled && iterationsRun < maxIterations {
            iterationsRun += 1
            connectCalled += 1
            if simulateSuccess {
                reconnectAttempt = 0
                // after success, pretend readLoop exits (EOF), loop continues
                simulateSuccess = false
            } else {
                reconnectAttempt += 1
            }
            if cancelled { break }
        }
    }
}

// MARK: - Socket path length validation (mirrors connectOnce logic)

enum PathValidationResult {
    case ok
    case tooLong
}

func validateSocketPath(_ path: String, capacity: Int = 104) -> PathValidationResult {
    let pathBytes = Array(path.utf8)
    // mirrors: if pathBytes.count >= capacity { throw .pathTooLong }
    return pathBytes.count >= capacity ? .tooLong : .ok
}

// MARK: - Tests

final class BridgeClientBackoffTests: XCTestCase {

    // 1. Attempt 0 returns base delay (1s with default base=1)
    func testBackoffExponential_Attempt0() {
        let calc = BackoffCalculator()
        let delay = calc.delay(attempt: 0)
        // 2^0 * 1 = 1.0
        XCTAssertEqual(delay, 1.0, accuracy: 0.001)
    }

    // 2. Attempt 4 returns 16s (2^4 = 16, still under the 30s cap)
    func testBackoffExponential_Attempt5() {
        let calc = BackoffCalculator()
        // attempt 4: 2^4 = 16 < 30 -> not capped
        let delay = calc.delay(attempt: 4)
        XCTAssertEqual(delay, 16.0, accuracy: 0.001)
        // attempt 5: 2^5 = 32 > 30 -> capped
        let delayCapped = calc.delay(attempt: 5)
        XCTAssertEqual(delayCapped, 30.0, accuracy: 0.001)
    }

    // 3. Large attempt is capped at 30s
    func testBackoffCappedAt30Seconds() {
        let calc = BackoffCalculator()
        // attempt 6 -> 2^6 = 64 > 30 -> should be capped
        let delay = calc.delay(attempt: 6)
        XCTAssertEqual(delay, 30.0, accuracy: 0.001)
        // attempt 100 also capped
        let delayHuge = calc.delay(attempt: 100)
        XCTAssertEqual(delayHuge, 30.0, accuracy: 0.001)
    }

    // 4. Delay is never negative
    func testBackoffNeverNegative() {
        let calc = BackoffCalculator()
        for attempt in 0...20 {
            XCTAssertGreaterThanOrEqual(calc.delay(attempt: attempt), 0.0,
                "delay should never be negative at attempt \(attempt)")
        }
    }

    // 5. cancelled=true before loop starts -> loop body never runs
    func testCancelledFlagBreaksLoop() {
        let loop = ReconnectLoopTestable()
        loop.cancelled = true
        loop.runLoop()
        XCTAssertEqual(loop.iterationsRun, 0, "loop should not run when cancelled=true at start")
    }

    // 6. Successful connect resets reconnectAttempt to 0
    func testReconnectCounterResetsOnSuccess() {
        let loop = ReconnectLoopTestable()
        loop.maxIterations = 3
        // first two iterations fail, third succeeds
        loop.runLoop()
        // After two failures reconnectAttempt == 2, then on third it would be set
        // Let's do a targeted test: set simulateSuccess=true from the start
        let loop2 = ReconnectLoopTestable()
        loop2.simulateSuccess = true
        loop2.maxIterations = 1
        loop2.runLoop()
        XCTAssertEqual(loop2.reconnectAttempt, 0, "counter should reset to 0 after successful connect")
    }

    // 7. Path longer than 104 bytes is rejected
    func testSocketPathLengthValidation() {
        let longPath = String(repeating: "a", count: 104) // exactly capacity -> rejected (>= check)
        let result = validateSocketPath(longPath)
        XCTAssertEqual(result, .tooLong)

        let wayTooLong = "/tmp/" + String(repeating: "x", count: 200)
        XCTAssertEqual(validateSocketPath(wayTooLong), .tooLong)
    }

    // 8. Path under 104 bytes is accepted
    func testSocketPathLengthValid() {
        let shortPath = "/tmp/providence.sock"
        XCTAssertEqual(validateSocketPath(shortPath), .ok)

        let path103 = String(repeating: "a", count: 103) // 103 < 104 -> ok
        XCTAssertEqual(validateSocketPath(path103), .ok)
    }

    // 9. Attempt 0 returns the minimal (base) delay
    func testZeroAttemptReturnsMinimalDelay() {
        let calc = BackoffCalculator(cap: 30.0, base: 1.0)
        let delay = calc.delay(attempt: 0)
        // Should be the smallest possible value, equal to base
        XCTAssertEqual(delay, calc.base, accuracy: 0.001)
        // And nothing produces a smaller delay in the sequence
        for attempt in 1...10 {
            XCTAssertGreaterThanOrEqual(calc.delay(attempt: attempt), delay)
        }
    }

    // 10. Delays are monotonically non-decreasing for attempts 0..5
    func testBackoffMonotonicIncrease() {
        let calc = BackoffCalculator()
        var prev = calc.delay(attempt: 0)
        for attempt in 1...5 {
            let curr = calc.delay(attempt: attempt)
            XCTAssertGreaterThanOrEqual(curr, prev,
                "delay at attempt \(attempt) (\(curr)) should be >= delay at \(attempt-1) (\(prev))")
            prev = curr
        }
    }
}

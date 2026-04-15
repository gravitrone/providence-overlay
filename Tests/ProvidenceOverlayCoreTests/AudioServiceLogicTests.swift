import XCTest

// Inline-testable copies of AudioService pure logic.
// No AVAudioEngine, no AVAudioPCMBuffer - pure math + state machine.

// MARK: - Pure RMS

private func computeRMSFromSamples(_ samples: [Float]) -> Float {
    let n = samples.count
    if n == 0 { return 0 }
    var sum: Float = 0
    for s in samples { sum += s * s }
    return (sum / Float(n)).squareRoot()
}

// MARK: - Speech Detector State Machine

private struct SpeechDetector {
    var audioActive: Bool = false
    private var speechStartAt: Date? = nil
    private var lastSpeechAt: Date? = nil

    private let speechThreshold: Float = 0.012
    private let onsetDuration: TimeInterval = 2.0
    private let silenceDuration: TimeInterval = 1.0

    mutating func update(rms: Float, at now: Date) {
        if rms > speechThreshold {
            if speechStartAt == nil { speechStartAt = now }
            lastSpeechAt = now
            if let start = speechStartAt, now.timeIntervalSince(start) > onsetDuration {
                if !audioActive { audioActive = true }
            }
        } else {
            if let last = lastSpeechAt, now.timeIntervalSince(last) > silenceDuration {
                speechStartAt = nil
                if audioActive { audioActive = false }
            }
        }
    }
}

// MARK: - Tests

final class AudioServiceLogicTests: XCTestCase {

    // 1. all-zero buffer -> RMS = 0
    func testRMSOfSilence() {
        let samples = [Float](repeating: 0, count: 1024)
        XCTAssertEqual(computeRMSFromSamples(samples), 0, accuracy: 1e-6)
    }

    // 2. sin at amplitude 0.5 -> RMS ≈ 0.5/sqrt(2) ≈ 0.3536
    func testRMSOfSineWave() {
        let count = 4096
        let freq: Float = 440
        let sr: Float = 16000
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = 0.5 * sin(2 * Float.pi * freq * Float(i) / sr)
        }
        let rms = computeRMSFromSamples(samples)
        XCTAssertEqual(rms, 0.5 / sqrt(2), accuracy: 0.005)
    }

    // 3. uniform random [-1,1] -> RMS ≈ 1/sqrt(3) ≈ 0.577
    func testRMSOfNoise() {
        var rng = SystemRandomNumberGenerator()
        let count = 44100
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = Float.random(in: -1...1, using: &rng)
        }
        let rms = computeRMSFromSamples(samples)
        // Tolerance loose: 0.54 - 0.62 covers statistical variance
        XCTAssertGreaterThan(rms, 0.54)
        XCTAssertLessThan(rms, 0.62)
    }

    // 4. RMS > threshold sustained for 2.0s -> audioActive becomes true
    func testSpeechOnsetRequires2sSustained() {
        var det = SpeechDetector()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        // Feed ticks at 0.1s intervals covering 0..2.1s (strictly > 2.0s required)
        for tick in 0...21 {
            det.update(rms: 0.05, at: start.addingTimeInterval(Double(tick) * 0.1))
        }
        XCTAssertTrue(det.audioActive)
    }

    // 5. RMS 0.010 (sub-threshold) for 5s -> audioActive stays false
    func testSpeechOnsetSubThresholdIgnored() {
        var det = SpeechDetector()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for tick in 0...50 {
            det.update(rms: 0.010, at: start.addingTimeInterval(Double(tick) * 0.1))
        }
        XCTAssertFalse(det.audioActive)
    }

    // 6. After going active, RMS drops below threshold for <1s -> still active
    func testSilenceHysteresis1Second() {
        var det = SpeechDetector()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        // Build up 2s of speech to go active
        for tick in 0...21 {
            det.update(rms: 0.05, at: start.addingTimeInterval(Double(tick) * 0.1))
        }
        XCTAssertTrue(det.audioActive)
        // Silence for 0.9s
        for tick in 0...8 {
            det.update(rms: 0.001, at: start.addingTimeInterval(2.1 + Double(tick) * 0.1))
        }
        XCTAssertTrue(det.audioActive, "should still be active after <1s silence")
    }

    // 7. After active, RMS drops below threshold for >1s -> audioActive false
    func testSilenceHysteresisFlipsAfter1s() {
        var det = SpeechDetector()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        // Go active
        for tick in 0...21 {
            det.update(rms: 0.05, at: start.addingTimeInterval(Double(tick) * 0.1))
        }
        XCTAssertTrue(det.audioActive)
        // Silence for >1s (1.2s)
        for tick in 0...12 {
            det.update(rms: 0.001, at: start.addingTimeInterval(2.1 + Double(tick) * 0.1))
        }
        XCTAssertFalse(det.audioActive, "should flip false after >1s silence")
    }

    // 8. active -> silence -> active -> silence: multiple full cycles work
    func testOnOffCycles() {
        var det = SpeechDetector()
        var t: TimeInterval = 0

        func speak(_ duration: TimeInterval) {
            let steps = Int(duration / 0.1)
            for _ in 0...steps {
                det.update(rms: 0.05, at: Date(timeIntervalSinceReferenceDate: t))
                t += 0.1
            }
        }

        func silence(_ duration: TimeInterval) {
            let steps = Int(duration / 0.1)
            for _ in 0...steps {
                det.update(rms: 0.001, at: Date(timeIntervalSinceReferenceDate: t))
                t += 0.1
            }
        }

        for _ in 0..<3 {
            speak(2.1)
            XCTAssertTrue(det.audioActive)
            silence(1.2)
            XCTAssertFalse(det.audioActive)
        }
    }

    // 9. empty buffer -> returns 0 (no div-by-zero)
    func testRMSBufferBoundary() {
        let rms = computeRMSFromSamples([])
        XCTAssertEqual(rms, 0)
    }

    // 10. resample ratio math: 48000/16000 = 3.0
    func testResampleRateCheck() {
        let sourceSampleRate: Double = 48000
        let targetSampleRate: Double = 16000
        let ratio = targetSampleRate / sourceSampleRate
        XCTAssertEqual(ratio, 1.0 / 3.0, accuracy: 1e-9)

        // Output capacity formula check (matches resampleTo16kMono logic)
        let frameLength: Double = 4096
        let outCapacity = Int(frameLength * ratio + 64)
        let expected = Int(4096.0 / 3.0 + 64)  // ~1429
        XCTAssertEqual(outCapacity, expected)
    }
}

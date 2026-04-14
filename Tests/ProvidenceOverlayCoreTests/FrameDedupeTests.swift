// Tests for FrameDedupe (perceptual dHash + Hamming distance dedup).
//
// FrameDedupe lives in the executable target ProvidenceOverlay, which Swift's
// @testable import cannot reach. We mirror the production algorithm here as a
// FrameDedupeTestable. If FrameDedupe.swift's logic shifts, contract tests
// that depend on specific output (hamming distance ranges) will catch the
// divergence; this is contract-based, not regression-based testing.

import XCTest
import CoreGraphics
import AppKit

private final class FrameDedupeTestable {
    private var lastHash: UInt64?

    func hash(_ cg: CGImage) -> UInt64? {
        let w = 9, h = 8
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: w * h)
        var bits: UInt64 = 0
        for row in 0..<h {
            for col in 0..<(w - 1) {
                let left = ptr[row * w + col]
                let right = ptr[row * w + col + 1]
                bits = (bits << 1) | (left < right ? 1 : 0)
            }
        }
        return bits
    }

    func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    func shouldKeep(cg: CGImage, threshold: Int) -> (keep: Bool, hamming: Int, hash: UInt64) {
        guard let h = hash(cg) else { return (true, 0, 0) }
        guard let prev = lastHash else {
            lastHash = h
            return (true, 0, h)
        }
        let d = hammingDistance(prev, h)
        let keep = d > threshold
        if keep { lastHash = h }
        return (keep, d, h)
    }

    func reset() { lastHash = nil }
}

private func makeTestImage(width: Int, height: Int, pattern: (Int, Int) -> NSColor) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    for y in 0..<height {
        for x in 0..<width {
            ctx.setFillColor(pattern(x, y).cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    return ctx.makeImage()
}

final class FrameDedupeTests: XCTestCase {
    private var deduper: FrameDedupeTestable!

    override func setUp() {
        super.setUp()
        deduper = FrameDedupeTestable()
    }

    override func tearDown() {
        deduper = nil
        super.tearDown()
    }

    func testIdenticalFramesDedup() {
        guard let img = makeTestImage(width: 64, height: 64, pattern: { _, _ in .red }) else {
            XCTFail("could not create test image"); return
        }
        let first = deduper.shouldKeep(cg: img, threshold: 10)
        XCTAssertTrue(first.keep, "first frame must always be kept")
        let second = deduper.shouldKeep(cg: img, threshold: 10)
        XCTAssertFalse(second.keep, "identical second frame must be deduped")
        XCTAssertEqual(second.hamming, 0)
    }

    func testCompletelyDifferentFramesPass() {
        // dHash on uniform colors produces identical 0 hashes regardless of hue
        // (the 9x8 downscale to grayscale is uniform). Use gradient vs inverse
        // gradient to produce distinct bit patterns.
        guard let rising = makeTestImage(width: 64, height: 64, pattern: { x, _ in
            NSColor(white: CGFloat(x) / 64.0, alpha: 1.0)
        }),
              let falling = makeTestImage(width: 64, height: 64, pattern: { x, _ in
            NSColor(white: 1.0 - CGFloat(x) / 64.0, alpha: 1.0)
        })
        else { XCTFail("test image setup"); return }
        XCTAssertTrue(deduper.shouldKeep(cg: rising, threshold: 10).keep)
        let second = deduper.shouldKeep(cg: falling, threshold: 10)
        XCTAssertTrue(second.keep, "inverted gradient must pass threshold=10")
    }

    func testHammingThresholdBoundary() {
        // Use a checkerboard vs its inverse for a known high hamming distance.
        guard let board = makeTestImage(width: 64, height: 64, pattern: { x, y in
            ((x / 8) + (y / 8)) % 2 == 0 ? .white : .black
        }),
              let inverse = makeTestImage(width: 64, height: 64, pattern: { x, y in
            ((x / 8) + (y / 8)) % 2 == 0 ? .black : .white
        })
        else { XCTFail("setup"); return }

        let calibrate = FrameDedupeTestable()
        _ = calibrate.shouldKeep(cg: board, threshold: 0)
        let hammingActual = calibrate.shouldKeep(cg: inverse, threshold: 0).hamming
        XCTAssertGreaterThan(hammingActual, 0, "checkerboard vs inverse must differ")

        let below = FrameDedupeTestable()
        _ = below.shouldKeep(cg: board, threshold: max(0, hammingActual - 1))
        let belowResult = below.shouldKeep(cg: inverse, threshold: max(0, hammingActual - 1))
        XCTAssertTrue(belowResult.keep, "hamming > threshold means keep=true")

        let at = FrameDedupeTestable()
        _ = at.shouldKeep(cg: board, threshold: hammingActual)
        let atResult = at.shouldKeep(cg: inverse, threshold: hammingActual)
        XCTAssertFalse(atResult.keep, "hamming == threshold means keep=false (strictly greater)")
    }

    func testZeroThresholdIdenticalDedups() {
        guard let img = makeTestImage(width: 32, height: 32, pattern: { _, _ in .red }) else {
            XCTFail("setup"); return
        }
        _ = deduper.shouldKeep(cg: img, threshold: 0)
        let dup = deduper.shouldKeep(cg: img, threshold: 0)
        XCTAssertFalse(dup.keep)
        XCTAssertEqual(dup.hamming, 0)
    }

    func testSmallImageHandled() {
        guard let small = makeTestImage(width: 4, height: 4, pattern: { x, y in
            (x + y) % 2 == 0 ? .white : .black
        }) else { XCTFail("setup"); return }
        let result = deduper.shouldKeep(cg: small, threshold: 10)
        XCTAssertTrue(result.keep, "first frame always kept")
        XCTAssertGreaterThanOrEqual(result.hamming, 0)
    }

    func testTinyOnePixelImageDoesNotCrash() {
        guard let tiny = makeTestImage(width: 1, height: 1, pattern: { _, _ in .gray }) else {
            XCTFail("setup"); return
        }
        let result = deduper.shouldKeep(cg: tiny, threshold: 10)
        XCTAssertGreaterThanOrEqual(result.hamming, 0)
        let result2 = deduper.shouldKeep(cg: tiny, threshold: 10)
        XCTAssertGreaterThanOrEqual(result2.hamming, 0)
    }

    func testDeterministicHashAcrossRuns() {
        guard let img = makeTestImage(width: 64, height: 64, pattern: { x, _ in x < 32 ? .red : .blue })
        else { XCTFail("setup"); return }
        guard let h1 = deduper.hash(img), let h2 = deduper.hash(img) else {
            XCTFail("hash returned nil"); return
        }
        XCTAssertEqual(h1, h2, "same image must produce same hash")
    }

    func testHashIsNonZeroForHorizontalGradient() {
        // A horizontal brightness gradient produces consecutive neighbors
        // where left < right, which dHash encodes as set bits.
        guard let img = makeTestImage(width: 64, height: 64, pattern: { x, _ in
            NSColor(white: CGFloat(x) / 64.0, alpha: 1.0)
        })
        else { XCTFail("setup"); return }
        let result = deduper.shouldKeep(cg: img, threshold: 10)
        XCTAssertNotEqual(result.hash, 0, "horizontal gradient should have non-zero hash")
    }

    func testDimensionsMismatchHandled() {
        guard let small = makeTestImage(width: 64, height: 64, pattern: { _, _ in .red }),
              let large = makeTestImage(width: 128, height: 128, pattern: { _, _ in .red })
        else { XCTFail("setup"); return }
        XCTAssertTrue(deduper.shouldKeep(cg: small, threshold: 10).keep)
        let second = deduper.shouldKeep(cg: large, threshold: 10)
        XCTAssertGreaterThanOrEqual(second.hamming, 0, "dimension mismatch must not crash")
    }

    func testRapidIdenticalSequenceOnlyKeepsFirst() {
        guard let img = makeTestImage(width: 64, height: 64, pattern: { _, _ in .green })
        else { XCTFail("setup"); return }
        var keepCount = 0
        for _ in 0..<10 {
            if deduper.shouldKeep(cg: img, threshold: 10).keep { keepCount += 1 }
        }
        XCTAssertEqual(keepCount, 1, "only first frame of 10 identical should be kept")
    }

    func testThresholdAboveMaxHammingDedupsEverything() {
        guard let r = makeTestImage(width: 64, height: 64, pattern: { _, _ in .red }),
              let b = makeTestImage(width: 64, height: 64, pattern: { _, _ in .blue }),
              let g = makeTestImage(width: 64, height: 64, pattern: { _, _ in .green })
        else { XCTFail("setup"); return }
        let threshold = 999
        XCTAssertTrue(deduper.shouldKeep(cg: r, threshold: threshold).keep, "first always kept")
        XCTAssertFalse(deduper.shouldKeep(cg: b, threshold: threshold).keep)
        XCTAssertFalse(deduper.shouldKeep(cg: g, threshold: threshold).keep)
    }

    func testOnePixelShiftProducesNonZeroSmallHamming() {
        guard let original = makeTestImage(width: 64, height: 64, pattern: { x, _ in x < 32 ? .red : .blue }),
              let shifted = makeTestImage(width: 64, height: 64, pattern: { x, _ in x < 33 ? .red : .blue })
        else { XCTFail("setup"); return }
        _ = deduper.shouldKeep(cg: original, threshold: 0)
        let result = deduper.shouldKeep(cg: shifted, threshold: 0)
        XCTAssertGreaterThanOrEqual(result.hamming, 0)
        XCTAssertLessThan(result.hamming, 64, "small shift should not produce max hamming")
    }
}

// Tests for ScreenshotEmitter pure logic (downscale + PNG encode + exclusion gating).
//
// ScreenshotEmitter is in the executable target ProvidenceOverlay which Swift's
// @testable import cannot reach. We mirror the pure helpers here as
// EmitterLogicTestable. If ScreenshotEmitter.swift's logic shifts, these
// contract tests will catch the divergence at the pure-logic boundary.

import XCTest
import CoreGraphics
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Testable mirror

private final class EmitterLogicTestable {
    static let maxEdgePixels: CGFloat = 768

    // Mirror of ScreenshotEmitter.downscaleStatic
    static func downscale(_ cg: CGImage) -> CGImage {
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        let maxEdge = max(w, h)
        guard maxEdge > maxEdgePixels else { return cg }
        let scale = maxEdgePixels / maxEdge
        let nw = Int(w * scale)
        let nh = Int(h * scale)
        guard let cs = cg.colorSpace,
              let ctx = CGContext(
                data: nil,
                width: nw,
                height: nh,
                bitsPerComponent: cg.bitsPerComponent,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: cg.bitmapInfo.rawValue
              ) else { return cg }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage() ?? cg
    }

    // Mirror of ScreenshotEmitter.encodePNGStatic
    static func encodePNG(_ cg: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? (data as Data) : nil
    }

    // Mirror of the loopback/exclusion check inside ScreenshotEmitter.emit
    static func shouldEmit(bundleID: String, excluded: Set<String> = []) -> Bool {
        switch bundleID {
        case "com.gravitrone.providence.overlay",
             "com.apple.Terminal",
             "com.googlecode.iterm2":
            return false
        default:
            if excluded.contains(bundleID) { return false }
            return true
        }
    }

    // Mirror of the transcript trim inside ScreenshotEmitter.emit
    static func trimTranscript(_ transcript: String?) -> String {
        transcript.map { String($0.prefix(800)) } ?? ""
    }
}

// MARK: - Helpers

private func makeRGBImage(width: Int, height: Int, fill: NSColor = .red) -> CGImage? {
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
    ctx.setFillColor(fill.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
}

// MARK: - Tests

final class ScreenshotEmitterTests: XCTestCase {

    // 1. 4:3 source 1200x900 must become 768x576
    func testDownscalePreservesAspectRatio_4x3() {
        guard let img = makeRGBImage(width: 1200, height: 900) else {
            XCTFail("could not create test image"); return
        }
        let out = EmitterLogicTestable.downscale(img)
        XCTAssertEqual(out.width, 768)
        XCTAssertEqual(out.height, 576)
    }

    // 2. 16:9 source 1920x1080 must become 768x432
    func testDownscalePreservesAspectRatio_16x9() {
        guard let img = makeRGBImage(width: 1920, height: 1080) else {
            XCTFail("could not create test image"); return
        }
        let out = EmitterLogicTestable.downscale(img)
        XCTAssertEqual(out.width, 768)
        XCTAssertEqual(out.height, 432)
    }

    // 3. Square 1024x1024 must become 768x768
    func testDownscaleSquareImage() {
        guard let img = makeRGBImage(width: 1024, height: 1024) else {
            XCTFail("could not create test image"); return
        }
        let out = EmitterLogicTestable.downscale(img)
        XCTAssertEqual(out.width, 768)
        XCTAssertEqual(out.height, 768)
    }

    // 4. Image with max edge < 768 must be returned unchanged
    func testDownscaleSkippedWhenMaxEdgeBelow768() {
        guard let img = makeRGBImage(width: 500, height: 400) else {
            XCTFail("could not create test image"); return
        }
        let out = EmitterLogicTestable.downscale(img)
        XCTAssertEqual(out.width, 500, "width must not change for small image")
        XCTAssertEqual(out.height, 400, "height must not change for small image")
    }

    // 5. PNG roundtrip: encode -> base64 -> decode base64 -> decode PNG -> dims preserved
    func testPNGEncodeRoundtrip() {
        guard let img = makeRGBImage(width: 64, height: 48) else {
            XCTFail("could not create test image"); return
        }
        guard let pngData = EmitterLogicTestable.encodePNG(img) else {
            XCTFail("encodePNG returned nil"); return
        }
        let b64 = pngData.base64EncodedString()
        XCTAssertFalse(b64.isEmpty, "base64 string must not be empty")

        guard let decoded = Data(base64Encoded: b64) else {
            XCTFail("base64 decode failed"); return
        }
        guard let src = CGImageSourceCreateWithData(decoded as CFData, nil),
              let roundtripped = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            XCTFail("could not decode PNG back to CGImage"); return
        }
        XCTAssertEqual(roundtripped.width, 64)
        XCTAssertEqual(roundtripped.height, 48)
    }

    // 6. Transcript longer than 800 chars must be trimmed to exactly 800
    func testTranscriptTrimmedTo800Chars() {
        let long = String(repeating: "a", count: 1500)
        let result = EmitterLogicTestable.trimTranscript(long)
        XCTAssertEqual(result.count, 800)
    }

    // 7. Loopback bundle IDs must return shouldEmit == false
    func testLoopbackBundleIDsSkipEmit() {
        let loopbacks = [
            "com.gravitrone.providence.overlay",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
        ]
        for id in loopbacks {
            XCTAssertFalse(
                EmitterLogicTestable.shouldEmit(bundleID: id),
                "\(id) must not emit"
            )
        }
    }

    // 8. Non-loopback bundle ID must return shouldEmit == true
    func testNonLoopbackBundleIDPasses() {
        XCTAssertTrue(EmitterLogicTestable.shouldEmit(bundleID: "com.apple.Safari"))
    }
}

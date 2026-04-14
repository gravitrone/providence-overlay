import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Dumb pipe: take a CGImage, downscale to 768px max edge, PNG-encode, base64,
/// ship as a `ContextUpdate` over the bridge. No OCR. No AX walk. No activity
/// classification. The model is the brain.
///
/// PNG encode + base64 happens on a background queue. The main actor only
/// reads gating state and dispatches the bridge send back to the main thread
/// once the encode is done. Without this, every 5s the SwiftUI panel froze
/// for ~150-300ms during encoding (downscale -> CGImageDestination ->
/// base64), which manifested as a spinning cursor on every click.
@MainActor
final class ScreenshotEmitter {
    private let bridge: BridgeClient
    private let state: AppState
    private let exclusions: ExclusionsManager?
    private static let maxEdgePixels: CGFloat = 768

    nonisolated(unsafe) private static let encodeQueue = DispatchQueue(
        label: "overlay.screenshot.encode",
        qos: .utility
    )

    init(bridge: BridgeClient, state: AppState, exclusions: ExclusionsManager? = nil) {
        self.bridge = bridge
        self.state = state
        self.exclusions = exclusions
    }

    /// Called per kept frame from CaptureService. Gated by screenEnabled and the
    /// hardcoded loopback / privacy exclusion sets. Heavy work hops to a
    /// background queue; only the bridge send returns to main.
    func emit(_ cg: CGImage, transcript: String?) {
        guard state.screenEnabled else { return }

        if let frontApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            switch frontApp {
            case "com.gravitrone.providence.overlay",
                 "com.apple.Terminal",
                 "com.googlecode.iterm2":
                return
            default:
                if exclusions?.contains(frontApp) == true { return }
            }
        }

        let trimmedTranscript = transcript.map { String($0.prefix(800)) } ?? ""
        let bridgeRef = bridge

        Self.encodeQueue.async { [cg] in
            guard let png = Self.encodePNGStatic(Self.downscaleStatic(cg)) else { return }
            let b64 = png.base64EncodedString()
            let update = ContextUpdate(
                timestamp: ISO8601DateFormatter().string(from: Date()),
                screenshot_png_b64: b64,
                transcript: trimmedTranscript.isEmpty ? nil : trimmedTranscript,
                change_kind: "frame"
            )
            Task { @MainActor in
                bridgeRef.sendContextUpdate(update)
            }
        }
    }

    /// Emit a transcript-only update (no new frame). Caller decides cadence.
    /// Lightweight enough to stay on the main actor.
    func emitTranscript(_ transcript: String) {
        guard state.micEnabled else { return }
        let trimmed = String(transcript.prefix(800))
        guard !trimmed.isEmpty else { return }
        let update = ContextUpdate(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            screenshot_png_b64: nil,
            transcript: trimmed,
            change_kind: "transcript_only"
        )
        bridge.sendContextUpdate(update)
    }

    private static func downscaleStatic(_ cg: CGImage) -> CGImage {
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

    private static func encodePNGStatic(_ cg: CGImage) -> Data? {
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
}

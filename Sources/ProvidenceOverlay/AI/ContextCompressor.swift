import Foundation
import AppKit
import ProvidenceOverlayCore

@MainActor
final class ContextCompressor {
    private let bridge: BridgeClient
    private var lastSent: Date = .distantPast
    private var lastActivity: Activity = .idle
    private var lastBundleID: String = ""
    private var lastHash: UInt64 = 0

    init(bridge: BridgeClient) {
        self.bridge = bridge
    }

    /// Called after each kept frame. Decides whether to emit a context_update.
    func consider(
        axSnapshot: AXSnapshot,
        frameHash: UInt64,
        transcript: String,
        activityHint: Activity,
        changeKind: String
    ) {
        // Loopback: skip if active app is Providence itself (TUI terminal or overlay).
        if let b = axSnapshot.bundleID,
           b == "com.gravitrone.providence.overlay" ||
            b == "com.apple.Terminal" ||
            b == "com.googlecode.iterm2" {
            lastHash = frameHash
            return
        }

        let activity = activityHint
        let now = Date()
        let sinceLast = now.timeIntervalSince(lastSent)
        let hammingDelta = (frameHash ^ lastHash).nonzeroBitCount
        let activityChanged = activity != lastActivity
        let appChanged = (axSnapshot.bundleID ?? "") != lastBundleID
        let lowerSummary = axSnapshot.summary.lowercased()
        let lowerTranscript = transcript.lowercased()
        let errorSignal = lowerSummary.contains("error") ||
                          lowerSummary.contains("failed") ||
                          lowerTranscript.contains("error")

        let shouldEmit = changeKind == "user-invoked" ||
                         activityChanged ||
                         appChanged ||
                         errorSignal ||
                         (sinceLast > 30 && hammingDelta >= 8)

        if shouldEmit {
            let kind: String
            if changeKind == "user-invoked" {
                kind = changeKind
            } else if errorSignal {
                kind = "error"
            } else if activityChanged || appChanged {
                kind = "pattern"
            } else {
                kind = changeKind
            }

            let update = ContextUpdate(
                timestamp: ISO8601DateFormatter().string(from: now),
                active_app: axSnapshot.bundleID ?? axSnapshot.appName,
                window_title: axSnapshot.windowTitle,
                activity: activity.rawValue,
                ocr_text: nil,
                ax_summary: axSnapshot.summary,
                transcript: transcript.isEmpty ? nil : transcript,
                pixel_hash: String(format: "%016llx", frameHash),
                change_kind: kind,
                origin: "overlay"
            )
            bridge.sendContextUpdate(update)
            lastSent = now
            Logger.log("compressor: emit kind=\(kind) app=\(update.active_app) activity=\(activity.rawValue) hamming=\(hammingDelta)")
        }

        lastActivity = activity
        lastBundleID = axSnapshot.bundleID ?? ""
        lastHash = frameHash
    }
}

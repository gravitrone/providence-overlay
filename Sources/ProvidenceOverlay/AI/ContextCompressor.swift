import Foundation
import AppKit
import ProvidenceOverlayCore

@MainActor
final class ContextCompressor {
    private let bridge: BridgeClient
    private var lastSent: Date = .distantPast
    private var lastSummaryHash: Int = 0
    private var lastActivity: Activity = .idle
    private var lastBundleID: String = ""
    private var lastErrorSent: Date = .distantPast
    /// Last transcript string we emitted on. Used by the Phase G delta gate:
    /// transcript-only changes must diverge > 30% (Jaccard < 0.70) from this
    /// value before they trigger a new emission.
    private var lastEmittedTranscript: String = ""

    /// Phase G: minimum seconds between heartbeat emissions. Dropped from 30s
    /// to 5s so the always-on chat window feels live, while still throttling
    /// the steady-state cost when nothing changes.
    private static let heartbeatInterval: TimeInterval = 5

    /// Toggled by the TUI via config. "system_reminder" (default) piggy-backs
    /// on the next user turn. "synthetic_user" injects directly - the compressor
    /// does not need to behave differently on emit, the TUI-side bridge decides
    /// what to do with each update.
    var contextInjectionMode: String = "system_reminder"

    /// Phase 10: runtime-mutable bundle ID exclusion list.
    /// Nil disables the extra check (still applies the hardcoded loopback set).
    var exclusions: ExclusionsManager?

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
        Logger.log("compressor: consider app=\(axSnapshot.bundleID ?? "nil") activity=\(activityHint.rawValue) changeKind=\(changeKind)")

        // Loopback: skip if active app is Providence itself (TUI terminal or overlay).
        if let b = axSnapshot.bundleID,
           b == "com.gravitrone.providence.overlay" ||
            b == "com.apple.Terminal" ||
            b == "com.googlecode.iterm2" {
            Logger.log("compressor: skipped (loopback app=\(b))")
            return
        }

        // Phase 10: runtime privacy exclusions (1Password, Keychain, etc).
        if let b = axSnapshot.bundleID, exclusions?.contains(b) == true {
            Logger.log("compressor: skipped (exclusion app=\(b))")
            return
        }

        // Field truncation caps BEFORE we build the ContextUpdate.
        let axTrimmed = String(axSnapshot.summary.prefix(1200))
        let ocrTrimmed = axSnapshot.focusedElementValue.map { String($0.prefix(800)) }
        let transcriptTrimmed = String(transcript.prefix(400))

        // Content hash over the stable fields - excludes timestamp/frame-hash
        // so identical consecutive states dedupe cleanly.
        var hasher = Hasher()
        hasher.combine(axSnapshot.bundleID ?? "")
        hasher.combine(axTrimmed)
        hasher.combine(ocrTrimmed ?? "")
        hasher.combine(transcriptTrimmed)
        let contentHash = hasher.finalize()

        let hasError = ErrorSignal.detect(ax: axTrimmed, ocr: ocrTrimmed, transcript: transcriptTrimmed)

        let now = Date()
        let activityChanged = activityHint != lastActivity
        let appChanged = (axSnapshot.bundleID ?? "") != lastBundleID
        let userInvoked = changeKind == "user-invoked"
        let dedupe = contentHash == lastSummaryHash
        let sinceLast = now.timeIntervalSince(lastSent)

        // Phase G transcript-delta gate. When a transcript is present and
        // nothing else observable changed, require the transcript to diverge
        // >30% (Jaccard < 0.70) from the last emitted one before we burn
        // tokens on it. Screen-only updates (empty transcript) are unaffected.
        let transcriptSimilarity = TranscriptSimilarity.jaccard(transcriptTrimmed, lastEmittedTranscript)
        let transcriptChangedMaterially = !transcriptTrimmed.isEmpty && transcriptSimilarity < 0.70

        // Priority-ordered gate. Error fast-path fires within 1s regardless of
        // dedupe, but is throttled to 1/sec to avoid spamming on long error text.
        let emitReason: String?
        if userInvoked {
            emitReason = "user-invoked"
        } else if hasError && now.timeIntervalSince(lastErrorSent) > 1 {
            emitReason = "error"
        } else if !dedupe && appChanged {
            emitReason = "pattern"
        } else if !dedupe && activityChanged {
            emitReason = "pattern"
        } else if !dedupe && transcriptChangedMaterially {
            emitReason = "transcript"
        } else if !dedupe && sinceLast > Self.heartbeatInterval {
            // Only emit a heartbeat when SOMETHING real is different. A pure
            // transcript shift that failed the similarity gate should stay
            // silent; otherwise we'd trivially re-emit every 5s.
            if transcriptTrimmed.isEmpty || transcriptChangedMaterially || appChanged || activityChanged {
                emitReason = "heartbeat"
            } else {
                emitReason = nil
            }
        } else {
            emitReason = nil
        }

        guard let reason = emitReason else {
            Logger.log("compressor: no emit (dedupe=\(dedupe) appChanged=\(appChanged) activityChanged=\(activityChanged) sinceLast=\(Int(sinceLast))s)")
            return
        }

        let tokens = TokenBudget.summarize(ContextUpdateFields(
            app: axSnapshot.bundleID ?? axSnapshot.appName,
            windowTitle: axSnapshot.windowTitle,
            axSummary: axTrimmed,
            ocr: ocrTrimmed,
            transcript: transcriptTrimmed.isEmpty ? nil : transcriptTrimmed
        ))

        let update = ContextUpdate(
            timestamp: ISO8601DateFormatter().string(from: now),
            active_app: axSnapshot.bundleID ?? axSnapshot.appName,
            window_title: axSnapshot.windowTitle,
            activity: activityHint.rawValue,
            ocr_text: ocrTrimmed,
            ax_summary: axTrimmed,
            transcript: transcriptTrimmed.isEmpty ? nil : transcriptTrimmed,
            pixel_hash: String(format: "%016llx", frameHash),
            change_kind: reason,
            origin: "overlay"
        )
        bridge.sendContextUpdate(update)

        Logger.log("compressor: emit reason=\(reason) tokens=\(tokens) mode=\(contextInjectionMode) app=\(axSnapshot.bundleID ?? "?") activity=\(activityHint.rawValue)")

        lastSent = now
        lastSummaryHash = contentHash
        lastActivity = activityHint
        lastBundleID = axSnapshot.bundleID ?? ""
        lastEmittedTranscript = transcriptTrimmed
        if hasError { lastErrorSent = now }
    }
}

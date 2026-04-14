import Foundation
@preconcurrency import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics
import CoreImage
import AppKit
import Combine
import ProvidenceOverlayCore

/// Thread-safe frame counter for the nonisolated sample callback. Used only for
/// diagnostic "every-Nth-frame" logging - not load-bearing for capture correctness.
final class FrameCounter: @unchecked Sendable {
    private var value: UInt64 = 0
    private let lock = NSLock()
    func incrementAndGet() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        value &+= 1
        return value
    }
}

/// Phase 7: Adaptive SCStream -> dedupe -> AX snapshot -> classify -> compress/emit.
@MainActor
final class CaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    private let state: AppState
    private let scheduler: AdaptiveScheduler
    private let dedupe: FrameDedupe
    private let compressor: ContextCompressor

    private var stream: SCStream?
    private var cancellables = Set<AnyCancellable>()
    nonisolated private let processingQueue = DispatchQueue(label: "overlay.capture.process", qos: .utility)
    // Persistent sample handler queue - allocating inline per start() would let ARC
    // reclaim it as soon as startStream returned, killing the callback path.
    nonisolated private let sampleQueue = DispatchQueue(label: "overlay.capture.samples", qos: .userInitiated)
    nonisolated private let frameCounter = FrameCounter()
    private var currentFPS: Double = 0.2
    private var started: Bool = false

    init(
        state: AppState,
        scheduler: AdaptiveScheduler,
        dedupe: FrameDedupe,
        compressor: ContextCompressor
    ) {
        self.state = state
        self.scheduler = scheduler
        self.dedupe = dedupe
        self.compressor = compressor
        super.init()

        // React to scheduler fps changes
        scheduler.$fps
            .sink { [weak self] newFPS in
                Task { @MainActor in
                    self?.state.currentFPS = newFPS
                    await self?.applyFPS(newFPS)
                }
            }
            .store(in: &cancellables)
    }

    func start() async {
        let initialFPS = scheduler.fps
        Logger.log("capture: start() invoked, initialFPS=\(initialFPS)")
        await startStream(fps: initialFPS)
    }

    func stop() async {
        if let s = stream {
            try? await s.stopCapture()
        }
        stream = nil
        started = false
        state.captureActive = false
    }

    private func startStream(fps: Double) async {
        if started {
            Logger.log("capture: startStream skipped - already started")
            return
        }
        do {
            Logger.log("capture: querying shareable content")
            // excludingDesktopWindows form triggers a fresh TCC permission check
            // and sidesteps any stale cached SCShareableContent from a prior
            // denied state. If permission is genuinely absent this throws.
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            Logger.log("capture: shareable content -> \(content.displays.count) displays, \(content.windows.count) windows")
            if let display = content.displays.first {
                try await configureAndStart(display: display, fps: fps)
                return
            }
            Logger.log("capture: no displays available - retrying in 1.5s")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let retry = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            Logger.log("capture: retry -> \(retry.displays.count) displays")
            guard let retryDisplay = retry.displays.first else {
                Logger.log("capture: still no displays after retry - giving up (permission likely denied)")
                return
            }
            try await configureAndStart(display: retryDisplay, fps: fps)
        } catch {
            Logger.log("capture: start error: \(error.localizedDescription) [\(type(of: error))]")
        }
    }

    private func configureAndStart(display: SCDisplay, fps: Double) async throws {
        Logger.log("capture: chose display=\(display.displayID) size=\(display.width)x\(display.height)")
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let ts = Int32(max(1, Int(round(1000.0 / max(0.1, fps)))))
        config.minimumFrameInterval = CMTime(value: CMTimeValue(ts), timescale: 1000)
        config.width = display.width / 2
        config.height = display.height / 2
        config.pixelFormat = kCVPixelFormatType_32BGRA
        Logger.log("capture: configuring stream fps=\(fps) w=\(config.width) h=\(config.height) interval=\(ts)/1000s")
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        Logger.log("capture: stream output added, calling startCapture()")
        do {
            try await s.startCapture()
            Logger.log("capture: startCapture() returned success")
        } catch {
            Logger.log("capture: startCapture() threw: \(error.localizedDescription) [\(type(of: error))]")
            throw error
        }
        self.stream = s
        self.currentFPS = fps
        self.started = true
        state.captureActive = true
        Logger.log("capture: started at \(fps) fps")
    }

    private func applyFPS(_ fps: Double) async {
        guard let s = stream else { return }
        if abs(fps - currentFPS) < 0.01 { return }
        do {
            let newConfig = SCStreamConfiguration()
            let ts = Int32(max(1, Int(round(1000.0 / max(0.1, fps)))))
            newConfig.minimumFrameInterval = CMTime(value: CMTimeValue(ts), timescale: 1000)
            if let display = try? await SCShareableContent.current.displays.first {
                newConfig.width = display.width / 2
                newConfig.height = display.height / 2
            }
            newConfig.pixelFormat = kCVPixelFormatType_32BGRA
            try await s.updateConfiguration(newConfig)
            currentFPS = fps
            Logger.log("capture: fps updated -> \(fps)")
        } catch {
            Logger.log("capture: fps update failed: \(error)")
        }
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        guard sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let count = frameCounter.incrementAndGet()
        if count == 1 || count % 10 == 0 {
            Logger.log("capture: frame \(count) received")
        }

        // Convert to CGImage on the current (sample handler) queue, then hop to main.
        guard let cg = Self.cgImage(from: pixelBuffer) else { return }
        Task { @MainActor [cg] in
            self.processFrame(cg)
        }
    }

    @MainActor
    private func processFrame(_ cg: CGImage) {
        let result = dedupe.shouldKeep(cg, threshold: 3)
        if !result.keep {
            // Keep this sparse - dedupe skips are extremely common.
            return
        }
        let snap = AXReader.snapshot() ?? AXSnapshot(
            appName: "",
            bundleID: nil,
            windowTitle: "",
            focusedElementValue: nil,
            summary: ""
        )
        Logger.log("capture: kept frame hamming=\(result.hamming) app=\(snap.bundleID ?? "nil") title=\(snap.windowTitle.prefix(40))")

        let input = ClassifierInput(
            bundleID: snap.bundleID,
            windowTitle: snap.windowTitle,
            axSummary: snap.summary,
            ocrText: nil,
            audioActive: state.audioActive
        )
        let activity = ActivityClassifier.classify(input)
        Logger.log("capture: classified activity=\(activity.rawValue)")

        // Publish for UI.
        let wasMeeting = state.currentActivity == .meeting
        state.currentActivity = activity
        state.currentApp = snap.appName

        // Phase 8: meeting mode transitions drive transcript visibility + scheduler hints.
        let isMeeting = activity == .meeting
        if isMeeting != wasMeeting {
            state.meetingMode = isMeeting
            if isMeeting {
                scheduler.markMeetingDetected()
            } else {
                scheduler.markMeetingEnded()
            }
        }

        compressor.consider(
            axSnapshot: snap,
            frameHash: result.hash,
            transcript: "",
            activityHint: activity,
            changeKind: "pixel"
        )
    }

    nonisolated private static func cgImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext(options: nil)
        return ctx.createCGImage(ci, from: ci.extent)
    }

    // MARK: - SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Logger.log("capture: stream stopped: \(error)")
    }
}

import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics
import CoreImage
import AppKit
import Combine
import ProvidenceOverlayCore

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
    private var currentFPS: Double = 0.2

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
        await startStream(fps: initialFPS)
    }

    func stop() async {
        if let s = stream {
            try? await s.stopCapture()
        }
        stream = nil
        state.captureActive = false
    }

    private func startStream(fps: Double) async {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                Logger.log("capture: no displays available")
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let ts = Int32(max(1, Int(round(1000.0 / max(0.1, fps)))))
            // minimumFrameInterval in seconds: 1/fps. Use timescale=1000 to allow fractional fps.
            config.minimumFrameInterval = CMTime(value: CMTimeValue(ts), timescale: 1000)
            config.width = display.width / 2
            config.height = display.height / 2
            config.pixelFormat = kCVPixelFormatType_32BGRA
            let s = SCStream(filter: filter, configuration: config, delegate: self)
            try s.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "overlay.capture")
            )
            try await s.startCapture()
            self.stream = s
            self.currentFPS = fps
            state.captureActive = true
            Logger.log("capture: started at \(fps) fps")
        } catch {
            Logger.log("capture: start error: \(error)")
        }
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
            return
        }
        let snap = AXReader.snapshot() ?? AXSnapshot(
            appName: "",
            bundleID: nil,
            windowTitle: "",
            focusedElementValue: nil,
            summary: ""
        )

        let input = ClassifierInput(
            bundleID: snap.bundleID,
            windowTitle: snap.windowTitle,
            axSummary: snap.summary,
            ocrText: nil,
            audioActive: state.audioActive
        )
        let activity = ActivityClassifier.classify(input)

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

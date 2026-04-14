import Foundation
@preconcurrency import ScreenCaptureKit
import CoreMedia
import CoreVideo
import CoreGraphics
import CoreImage
import AppKit
import Combine
import ProvidenceOverlayCore

/// Thread-safe frame counter for the nonisolated sample callback. Diagnostic only.
final class FrameCounter: @unchecked Sendable {
    private var value: UInt64 = 0
    private let lock = NSLock()
    func incrementAndGet() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        value &+= 1
        return value
    }
}

/// Dumb capture pipe: SCStream at fixed 5s cadence -> dHash dedup -> ScreenshotEmitter.
/// No activity classification, no AX walk, no OCR. The model is the brain.
@MainActor
final class CaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    private let state: AppState
    private let dedupe: FrameDedupe
    private let emitter: ScreenshotEmitter

    private var stream: SCStream?
    nonisolated private let sampleQueue = DispatchQueue(label: "overlay.capture.samples", qos: .userInitiated)
    nonisolated private let frameCounter = FrameCounter()
    private var started: Bool = false

    /// Fixed 5s capture cadence (0.2 fps). We trade liveness for cost: at vision
    /// token rates, faster cadence is unaffordable for 24/7 ambient. dHash dedup
    /// drops still frames before they ever leave the overlay.
    private static let captureIntervalMS: Int32 = 5000

    init(state: AppState, dedupe: FrameDedupe, emitter: ScreenshotEmitter) {
        self.state = state
        self.dedupe = dedupe
        self.emitter = emitter
        super.init()
    }

    func start() async {
        Logger.log("capture: start() invoked, fixed cadence 5s")
        await startStream()
    }

    func stop() async {
        if let s = stream {
            try? await s.stopCapture()
        }
        stream = nil
        started = false
        state.captureActive = false
        Logger.log("capture: stopped")
    }

    private func startStream() async {
        if started {
            Logger.log("capture: startStream skipped - already started")
            return
        }
        do {
            Logger.log("capture: querying shareable content")
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            Logger.log("capture: shareable content -> \(content.displays.count) displays, \(content.windows.count) windows")
            if let display = content.displays.first {
                try await configureAndStart(display: display)
                return
            }
            Logger.log("capture: no displays available - retrying in 1.5s")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let retry = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let retryDisplay = retry.displays.first else {
                Logger.log("capture: still no displays after retry - giving up (permission likely denied)")
                return
            }
            try await configureAndStart(display: retryDisplay)
        } catch {
            Logger.log("capture: start error: \(error.localizedDescription) [\(type(of: error))]")
        }
    }

    private func configureAndStart(display: SCDisplay) async throws {
        Logger.log("capture: chose display=\(display.displayID) size=\(display.width)x\(display.height)")
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: CMTimeValue(Self.captureIntervalMS), timescale: 1000)
        config.width = display.width / 2
        config.height = display.height / 2
        config.pixelFormat = kCVPixelFormatType_32BGRA
        Logger.log("capture: configuring stream w=\(config.width) h=\(config.height) interval=\(Self.captureIntervalMS)/1000s")
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await s.startCapture()
        Logger.log("capture: startCapture() returned success")
        self.stream = s
        self.started = true
        state.captureActive = true
        Logger.log("capture: started")
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

        guard let cg = Self.cgImage(from: pixelBuffer) else { return }
        Task { @MainActor [cg] in
            self.processFrame(cg)
        }
    }

    @MainActor
    private func processFrame(_ cg: CGImage) {
        // Loose dedup threshold (was 3, now 5) since 5s cadence already throttles.
        let result = dedupe.shouldKeep(cg, threshold: 5)
        if !result.keep { return }
        let transcript = state.transcript
        emitter.emit(cg, transcript: transcript.isEmpty ? nil : transcript)
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

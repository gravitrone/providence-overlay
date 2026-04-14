import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

// TODO(phase7+): Consolidate with ProvidenceCaptureKit from providence-core/bridge/swift-mac/.
// Phase 6 scope: bare SCStream at 1 fps, drop frames. No dedup, no classification.

@MainActor
final class CaptureService: NSObject, SCStreamOutput, SCStreamDelegate {
    private let state: AppState
    private var stream: SCStream?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func start(fps: Int) async {
        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                Logger.log("capture: no displays available")
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(fps))
            config.width = display.width / 2   // downsample for perf in idle mode
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
            state.captureActive = true
            Logger.log("capture: started at \(fps) fps")
        } catch {
            Logger.log("capture: start error: \(error)")
        }
    }

    func stop() async {
        if let s = stream {
            try? await s.stopCapture()
        }
        stream = nil
        state.captureActive = false
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        // Phase 6: no-op. Dedupe + classification come in Phase 7.
    }

    // MARK: - SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Logger.log("capture: stream stopped: \(error)")
    }
}

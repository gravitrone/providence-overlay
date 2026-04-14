import Foundation
import CoreAudio
import AVFoundation

enum AudioError: Error {
    case tapCreateFailed(Int)
    case aggregateDeviceFailed(Int)
    case unavailable(String)
}

/// Phase 8: SystemAudioTap is a stub.
///
/// The real implementation requires CATapDescription + AudioHardwareCreateProcessTap
/// (macOS 14.2+) plus aggregate-device wiring to pipe the tap into AVAudioEngine.
/// That pipeline has many failure modes (sparse docs, fragile aggregate device
/// teardown, permissions), and mic-only is a shippable Phase 8 baseline.
///
/// TODO(phase-9+): implement full system-audio tap.
@available(macOS 14.2, *)
final class SystemAudioTap {
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    init() {}

    func start() async throws {
        Logger.log("audio: system tap attempted - stubbed in phase 8, mic-only")
        throw AudioError.unavailable("SystemAudioTap not fully implemented in Phase 8")
    }

    func stop() async {
        // no-op
    }
}

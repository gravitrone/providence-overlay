import Foundation
import Speech
import AVFoundation

/// Phase 8: wake-phrase detection via on-device SFSpeechRecognizer.
///
/// Porcupine would be the long-term choice (<1% CPU, dedicated small model),
/// but it ships as a vendored .xcframework and is scope-heavy for phase 8.
/// SFSpeechRecognizer with `requiresOnDeviceRecognition = true` gives us a
/// reasonable substitute with zero extra deps.
///
/// TODO(phase-10+): swap for Porcupine if battery impact is noticeable.
@MainActor
final class WakeWordService: ObservableObject {
    @Published private(set) var triggered = false
    @Published private(set) var armed = false

    private let phrase = "hey providence"
    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    var onDetect: (() -> Void)?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func start() async throws {
        let ok = await requestAuthorization()
        guard ok else {
            Logger.log("wake word: authorization denied")
            throw NSError(
                domain: "WakeWord",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "speech authorization denied"]
            )
        }
        Logger.log("wake word: authorization granted")
        try startTask()
        armed = true
    }

    private func startTask() throws {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw NSError(
                domain: "WakeWord",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "recognizer unavailable"]
            )
        }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        self.request = req

        recognitionTask = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                Logger.log("wake word: recognition error: \(error)")
                return
            }
            guard let result = result else { return }
            let text = result.bestTranscription.formattedString.lowercased()
            if text.contains(self.phrase) {
                Task { @MainActor in
                    self.triggered = true
                    self.onDetect?()
                    // Reset recognition to keep armed state without runaway buffers.
                    self.restart()
                }
            }
        }
    }

    /// Call with raw mic buffers (native format, not the 16kHz resampled).
    func feed(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    func stop() {
        recognitionTask?.cancel()
        request?.endAudio()
        recognitionTask = nil
        request = nil
        armed = false
    }

    private func restart() {
        recognitionTask?.cancel()
        request?.endAudio()
        recognitionTask = nil
        request = nil
        triggered = false
        do {
            try startTask()
        } catch {
            Logger.log("wake word: restart failed: \(error)")
        }
    }
}

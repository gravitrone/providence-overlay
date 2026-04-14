import Foundation
import AVFoundation

#if canImport(WhisperKit)
import WhisperKit
#endif

/// Phase 8: streaming transcription via WhisperKit on Neural Engine.
///
/// Consumes 16kHz mono Float32 PCM buffers. Transcribes overlapping 5s windows
/// with 50% overlap. Publishes `latestSegment` (most recent chunk text) and
/// `rollingTranscript` (last ~600 chars).
///
/// If WhisperKit is unavailable or fails to load, this stays in a no-op mode
/// and the rest of the pipeline continues fine.
@MainActor
final class WhisperTranscriber: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var latestSegment = ""
    @Published private(set) var rollingTranscript = ""

    private var modelLoaded = false
    private var audioBuffer: [Float] = []
    private let sampleRate: Double = 16000
    private let windowDuration: Double = 5
    private var transcribing = false

    #if canImport(WhisperKit)
    private var whisper: WhisperKit?
    #endif

    func load() async {
        #if canImport(WhisperKit)
        do {
            let w = try await WhisperKit(model: "tiny.en", verbose: false)
            self.whisper = w
            isReady = true
            modelLoaded = true
            Logger.log("whisper: load succeeded (tiny.en)")
        } catch {
            Logger.log("whisper: load failed: \(error)")
        }
        #else
        Logger.log("whisper: WhisperKit not available - transcription disabled")
        #endif
    }

    /// Accepts 16kHz mono Float32 PCM buffers.
    func feed(_ buffer: AVAudioPCMBuffer) async {
        guard modelLoaded else { return }
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        if frames == 0 { return }
        audioBuffer.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frames))

        let windowSamples = Int(sampleRate * windowDuration)
        if audioBuffer.count >= windowSamples && !transcribing {
            let chunk = Array(audioBuffer.prefix(windowSamples))
            audioBuffer.removeFirst(windowSamples / 2)  // 50% overlap
            transcribing = true
            await transcribe(chunk)
            transcribing = false
        }
    }

    private func transcribe(_ samples: [Float]) async {
        #if canImport(WhisperKit)
        guard let w = whisper else { return }
        do {
            let results = try await w.transcribe(audioArray: samples)
            let text = results.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                latestSegment = text
                let joined = (rollingTranscript + " " + text)
                    .trimmingCharacters(in: .whitespaces)
                rollingTranscript = joined.count > 600
                    ? String(joined.suffix(600))
                    : joined
            }
        } catch {
            Logger.log("whisper: transcribe error: \(error)")
        }
        #else
        _ = samples
        #endif
    }

    func clear() {
        audioBuffer.removeAll()
        latestSegment = ""
        rollingTranscript = ""
    }
}

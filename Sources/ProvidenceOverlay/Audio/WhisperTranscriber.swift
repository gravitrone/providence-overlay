import Foundation
import AVFoundation
import MLX
import MLXAudio

/// Streaming transcription via MLX on Apple Silicon (whisper-large-v3-turbo).
///
/// Consumes 16kHz mono Float32 PCM buffers. Transcribes overlapping 5s windows
/// with 50% overlap. Publishes `latestSegment` (most recent chunk text) and
/// `rollingTranscript` (last ~600 chars).
///
/// The MLX path accepts an `MLXArray` directly, so no temp WAV files are needed
/// per chunk. Model weights are loaded from the HuggingFace cache at
/// `~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo/`
/// (first launch downloads if missing).
@MainActor
final class WhisperTranscriber: ObservableObject {
    @Published private(set) var isReady = false
    @Published private(set) var latestSegment = ""
    @Published private(set) var rollingTranscript = ""

    private var engine: WhisperEngine?
    private var audioBuffer: [Float] = []
    private let sampleRate: Double = 16000
    private let windowDuration: Double = 5
    private var transcribing = false

    func load() async {
        let eng = STT.whisper(model: .largeTurbo, quantization: .fp16)
        do {
            try await eng.load()
            self.engine = eng
            isReady = true
            Logger.log("whisper: load succeeded (large-v3-turbo fp16)")
        } catch {
            Logger.log("whisper: load failed: \(error)")
        }
    }

    /// Accepts 16kHz mono Float32 PCM buffers.
    func feed(_ buffer: AVAudioPCMBuffer) async {
        guard isReady else { return }
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
        guard let engine = engine else { return }
        let array = MLXArray(samples)
        do {
            let result = try await engine.transcribe(array, language: .english)
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
    }

    func clear() {
        audioBuffer.removeAll()
        latestSegment = ""
        rollingTranscript = ""
    }
}

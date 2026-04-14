import Foundation
import AVFoundation
import CoreAudio

/// Phase 8: coordinates mic capture (always) and system audio tap (stubbed).
///
/// Emits 16kHz mono Float32 PCM buffers via `audioStream()`. Also tracks a
/// sustained-speech flag `audioActive` (true after >2s of speech-level input,
/// false after 1s of silence) that `ActivityClassifier` consumes for the
/// `.meeting` heuristic.
@MainActor
final class AudioService: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var recentLevel: Float = 0  // RMS for level meter
    @Published private(set) var audioActive = false     // sustained speech >2s

    private var engine: AVAudioEngine?
    private var systemTap: Any?  // SystemAudioTap on 14.2+, stored as Any for availability
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private let targetFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!
    }()

    private var speechStartAt: Date? = nil
    private var lastSpeechAt: Date? = nil

    // Raw (non-resampled) mic buffer consumers. Used by WakeWordService which
    // talks to SFSpeechRecognizer and prefers the mic's native format.
    private var rawContinuations: [UUID: AsyncStream<AVAudioPCMBuffer>.Continuation] = [:]
    // 16k mono consumers. Used by WhisperTranscriber.
    private var continuations: [UUID: AsyncStream<AVAudioPCMBuffer>.Continuation] = [:]

    /// 16kHz mono Float32 resampled stream (for Whisper).
    func audioStream() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { cont in
            let id = UUID()
            self.continuations[id] = cont
            cont.onTermination = { _ in
                Task { @MainActor in self.continuations.removeValue(forKey: id) }
            }
        }
    }

    /// Raw mic-format stream (for SFSpeechRecognizer wake word).
    func rawAudioStream() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { cont in
            let id = UUID()
            self.rawContinuations[id] = cont
            cont.onTermination = { _ in
                Task { @MainActor in self.rawContinuations.removeValue(forKey: id) }
            }
        }
    }

    /// Start mic (always) + system audio tap (if available).
    func start() async throws {
        // 1. Mic via AVAudioEngine input
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let fmt = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Capture raw buffer for wake word, and resample for whisper.
            let resampled = self.resampleTo16kMono(buffer, sourceFormat: fmt)
            Task { @MainActor in
                self.publishRaw(buffer)
                if let r = resampled { self.publish(r) } else { self.publish(buffer) }
            }
        }
        try engine.start()
        self.engine = engine
        Logger.log("audio: mic engine started format=\(fmt)")

        // 2. System audio tap (14.2+) - stubbed
        if #available(macOS 14.2, *) {
            let tap = SystemAudioTap()
            tap.onBuffer = { [weak self] buffer in
                Task { @MainActor in self?.publish(buffer) }
            }
            do {
                try await tap.start()
                self.systemTap = tap
            } catch {
                Logger.log("audio: system tap unavailable: \(error)")
            }
        }

        isActive = true
    }

    func stop() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        if #available(macOS 14.2, *), let tap = systemTap as? SystemAudioTap {
            Task { await tap.stop() }
        }
        systemTap = nil
        isActive = false
        for (_, c) in continuations { c.finish() }
        continuations.removeAll()
        for (_, c) in rawContinuations { c.finish() }
        rawContinuations.removeAll()
    }

    private func publish(_ buffer: AVAudioPCMBuffer) {
        let rms = computeRMS(buffer)
        recentLevel = rms
        updateSpeechDetection(rms: rms)
        for (_, c) in continuations { c.yield(buffer) }
    }

    private func publishRaw(_ buffer: AVAudioPCMBuffer) {
        for (_, c) in rawContinuations { c.yield(buffer) }
    }

    private func updateSpeechDetection(rms: Float) {
        let speechThreshold: Float = 0.012
        let now = Date()
        if rms > speechThreshold {
            if speechStartAt == nil { speechStartAt = now }
            lastSpeechAt = now
            if let start = speechStartAt, now.timeIntervalSince(start) > 2 {
                if !audioActive { audioActive = true }
            }
        } else {
            if let last = lastSpeechAt, now.timeIntervalSince(last) > 1 {
                // Silence for 1s after speech -> end of utterance.
                speechStartAt = nil
                if audioActive { audioActive = false }
            }
        }
    }

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let ch = channelData[0]
        let n = Int(buffer.frameLength)
        if n == 0 { return 0 }
        var sum: Float = 0
        for i in 0..<n {
            let s = ch[i]
            sum += s * s
        }
        return (sum / Float(n)).squareRoot()
    }

    private func resampleTo16kMono(
        _ buffer: AVAudioPCMBuffer,
        sourceFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        // Cache converter for the source format.
        if converter == nil || converterInputFormat?.sampleRate != sourceFormat.sampleRate
            || converterInputFormat?.channelCount != sourceFormat.channelCount {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            converterInputFormat = sourceFormat
        }
        guard let conv = converter else { return nil }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 64)
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outCapacity
        ) else { return nil }

        var err: NSError?
        var sourceConsumed = false
        let status = conv.convert(to: outBuffer, error: &err, withInputFrom: { _, outStatus in
            if sourceConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            sourceConsumed = true
            outStatus.pointee = .haveData
            return buffer
        })
        if status == .error || err != nil {
            return nil
        }
        return outBuffer
    }
}

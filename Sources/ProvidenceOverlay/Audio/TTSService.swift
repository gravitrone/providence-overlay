import Foundation
import AVFoundation

/// Phase 8: TTS wrapper around AVSpeechSynthesizer.
/// Disabled by default - Phase 10 wires menu-bar toggle.
@MainActor
final class TTSService {
    private let synth: AVSpeechSynthesizer
    private(set) var enabled: Bool

    init(enabled: Bool = false) {
        self.synth = AVSpeechSynthesizer()
        self.enabled = enabled
    }

    func setEnabled(_ e: Bool) { enabled = e }

    func speak(_ text: String, rate: Float = 0.5) {
        guard enabled, !text.isEmpty else { return }
        let utt = AVSpeechUtterance(string: text)
        utt.rate = rate
        utt.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utt)
    }

    func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
    }
}

import Foundation
import AVFoundation

/// Phase 8: TTS wrapper around AVSpeechSynthesizer.
/// Phase 10: adds routing - only speak replies to queries sourced from wake
/// word or push-to-talk. Other replies stay silent.
@MainActor
final class TTSService {
    private let synth: AVSpeechSynthesizer
    private(set) var enabled: Bool

    /// Source of the current in-flight user turn, if the next assistant reply
    /// should be spoken. nil means "stay silent".
    private var pendingSpeakForTurnFromSource: String? = nil
    private var accumulatedText: String = ""

    init(enabled: Bool = false) {
        self.synth = AVSpeechSynthesizer()
        self.enabled = enabled
    }

    func setEnabled(_ e: Bool) { enabled = e }

    /// Arm the service so the next streaming assistant reply is spoken when it
    /// finishes. Only wake_word and push_to_talk sources trigger TTS.
    func armForNextReply(source: String) {
        if source == "wake_word" || source == "push_to_talk" {
            pendingSpeakForTurnFromSource = source
            accumulatedText = ""
        }
    }

    /// Feed a streaming assistant_delta. When finished == true and the turn
    /// was armed, speak the accumulated text.
    func feedDelta(_ text: String, finished: Bool) {
        guard enabled, pendingSpeakForTurnFromSource != nil else { return }
        accumulatedText += text
        if finished {
            let toSpeak = accumulatedText
            pendingSpeakForTurnFromSource = nil
            accumulatedText = ""
            if !toSpeak.isEmpty {
                speak(toSpeak)
            }
        }
    }

    func speak(_ text: String, rate: Float = 0.5) {
        guard !text.isEmpty else { return }
        let utt = AVSpeechUtterance(string: text)
        utt.rate = rate
        utt.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utt)
    }

    func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
    }
}

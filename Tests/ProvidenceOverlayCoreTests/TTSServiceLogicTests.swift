import XCTest

// Inline testable mirror of TTSService logic.
// AVSpeechSynthesizer is NOT called - speak() is stubbed out so tests
// run headlessly without audio hardware.
@MainActor
private final class TTSServiceTestable {
    private(set) var enabled: Bool
    private var pendingSpeakForTurnFromSource: String? = nil
    private(set) var accumulatedText: String = ""
    private(set) var spokenTexts: [String] = [] // capture speak() calls

    init(enabled: Bool = true) {
        self.enabled = enabled
    }

    func setEnabled(_ e: Bool) { enabled = e }

    func armForNextReply(source: String) {
        if source == "wake_word" || source == "push_to_talk" {
            pendingSpeakForTurnFromSource = source
            accumulatedText = ""
        }
    }

    var isArmed: Bool { pendingSpeakForTurnFromSource != nil }

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

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        spokenTexts.append(text)
    }
}

final class TTSServiceLogicTests: XCTestCase {

    // MARK: - arming

    @MainActor func testArmForNextReplyOnlyForWakeWordOrPTT() {
        let svc = TTSServiceTestable()

        svc.armForNextReply(source: "random")
        XCTAssertFalse(svc.isArmed, "random source should not arm")

        svc.armForNextReply(source: "wake_word")
        XCTAssertTrue(svc.isArmed, "wake_word should arm")

        // reset by consuming
        svc.feedDelta("done", finished: true)

        svc.armForNextReply(source: "push_to_talk")
        XCTAssertTrue(svc.isArmed, "push_to_talk should arm")
    }

    // MARK: - delta accumulation

    @MainActor func testFeedDeltaAccumulatesWhenArmed() {
        let svc = TTSServiceTestable()
        svc.armForNextReply(source: "wake_word")
        svc.feedDelta("Hello", finished: false)
        svc.feedDelta(", world", finished: false)
        XCTAssertEqual(svc.accumulatedText, "Hello, world")
    }

    // MARK: - speak on finished

    @MainActor func testSpeaksOnFinishedTrueWithAccumulatedText() {
        let svc = TTSServiceTestable()
        svc.armForNextReply(source: "wake_word")
        svc.feedDelta("Hello", finished: false)
        svc.feedDelta("!", finished: true)
        XCTAssertEqual(svc.spokenTexts, ["Hello!"])
    }

    // MARK: - buffer cleared after speak

    @MainActor func testAccumulatedTextClearedAfterSpeak() {
        let svc = TTSServiceTestable()
        svc.armForNextReply(source: "push_to_talk")
        svc.feedDelta("Some text", finished: true)
        XCTAssertEqual(svc.accumulatedText, "")
    }

    // MARK: - non-armed deltas ignored

    @MainActor func testNonArmedDeltasIgnored() {
        let svc = TTSServiceTestable()
        // not armed - no armForNextReply call
        svc.feedDelta("ghost", finished: false)
        svc.feedDelta("ghost2", finished: true)
        XCTAssertEqual(svc.accumulatedText, "")
        XCTAssertTrue(svc.spokenTexts.isEmpty)
    }

    // MARK: - disabled suppresses speak

    @MainActor func testSetEnabledFalseSuppressesSpeak() {
        let svc = TTSServiceTestable(enabled: true)
        svc.armForNextReply(source: "wake_word")
        svc.setEnabled(false)
        svc.feedDelta("should not speak", finished: true)
        XCTAssertTrue(svc.spokenTexts.isEmpty)
    }
}

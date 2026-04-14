// Tests for HotkeyService pure dispatch logic + four-char-code conversion.
//
// HotkeyService lives in the executable target ProvidenceOverlay, which Swift's
// @testable import cannot reach. We mirror the pure helpers here:
//   - fourCharCode UInt32 encoding/decoding
//   - eventID -> callback dispatch (mirrors handlePress switch)
//   - hotkey ID uniqueness
//
// Carbon registration (RegisterEventHotKey, GetApplicationEventTarget) is NOT
// tested here - that requires Accessibility grant and a running event loop.
// Contract-based, not regression-based testing.

import XCTest

// MARK: - Inline-testable copy of HotkeyService pure logic

/// Mirrors HotkeyService's static event IDs (production source: HotkeyService.swift).
private enum HotkeyID {
    static let toggle: UInt32 = 0xBEE5
    static let ptt: UInt32 = 0xBEE6
    static let chat: UInt32 = 0xBEE7
}

/// Pure four-char-code helpers (mirrors OSType encoding used in HotkeyService).
private func fourCharCodeToUInt32(_ s: String) -> UInt32? {
    let scalars = s.unicodeScalars
    guard scalars.count == 4 else { return nil }
    var result: UInt32 = 0
    for scalar in scalars {
        result = (result << 8) | scalar.value
    }
    return result
}

private func uInt32ToFourCharCode(_ v: UInt32) -> String {
    var chars: [Character] = []
    for shift in stride(from: 24, through: 0, by: -8) {
        let byte = UInt8((v >> shift) & 0xFF)
        chars.append(Character(UnicodeScalar(byte)))
    }
    return String(chars)
}

/// Mirrors HotkeyService.handlePress dispatch logic.
private final class HotkeyDispatchTestable {
    var onToggle: (() -> Void)?
    var onPushToTalk: (() -> Void)?
    var onChatToggle: (() -> Void)?

    func handlePress(_ eventID: UInt32) {
        switch eventID {
        case HotkeyID.toggle:
            onToggle?()
        case HotkeyID.ptt:
            onPushToTalk?()
        case HotkeyID.chat:
            onChatToggle?()
        default:
            break
        }
    }
}

// MARK: - Tests

final class HotkeyServiceLogicTests: XCTestCase {

    // MARK: 1. Four-char-code roundtrip

    func testFourCharCodeRoundtrip() {
        let input = "PRVH"
        guard let encoded = fourCharCodeToUInt32(input) else {
            XCTFail("fourCharCodeToUInt32 returned nil for \(input)"); return
        }
        let decoded = uInt32ToFourCharCode(encoded)
        XCTAssertEqual(decoded, input, "PRVH -> UInt32 -> String must roundtrip")
    }

    // MARK: 2. Distinct four-char-codes produce distinct UInt32s

    func testFourCharCodeMaxValue() {
        let codes = ["PRVA", "PRVB", "PRVC", "PRVD"]
        var seen = Set<UInt32>()
        for code in codes {
            guard let v = fourCharCodeToUInt32(code) else {
                XCTFail("nil for \(code)"); return
            }
            XCTAssertFalse(seen.contains(v), "\(code) collides with a prior four-char-code")
            seen.insert(v)
        }
        XCTAssertEqual(seen.count, codes.count)
    }

    // MARK: 3. PTT event invokes PTT callback exactly once

    func testDispatchPTTEventInvokesPTTCallback() {
        let svc = HotkeyDispatchTestable()
        var pttCount = 0
        var toggleCount = 0
        var chatCount = 0
        svc.onPushToTalk = { pttCount += 1 }
        svc.onToggle     = { toggleCount += 1 }
        svc.onChatToggle = { chatCount += 1 }

        svc.handlePress(HotkeyID.ptt)

        XCTAssertEqual(pttCount, 1, "PTT callback must fire exactly once")
        XCTAssertEqual(toggleCount, 0, "toggle must not fire on PTT event")
        XCTAssertEqual(chatCount, 0, "chat must not fire on PTT event")
    }

    // MARK: 4. Chat toggle event invokes chat callback exactly once

    func testDispatchChatToggleInvokesChatCallback() {
        let svc = HotkeyDispatchTestable()
        var pttCount = 0
        var toggleCount = 0
        var chatCount = 0
        svc.onPushToTalk = { pttCount += 1 }
        svc.onToggle     = { toggleCount += 1 }
        svc.onChatToggle = { chatCount += 1 }

        svc.handlePress(HotkeyID.chat)

        XCTAssertEqual(chatCount, 1, "chat callback must fire exactly once")
        XCTAssertEqual(pttCount, 0, "PTT must not fire on chat event")
        XCTAssertEqual(toggleCount, 0, "toggle must not fire on chat event")
    }

    // MARK: 5. Unknown eventID fires no callback

    func testDispatchUnknownEventDoesNotFire() {
        let svc = HotkeyDispatchTestable()
        var fired = false
        svc.onPushToTalk = { fired = true }
        svc.onToggle     = { fired = true }
        svc.onChatToggle = { fired = true }

        svc.handlePress(0xDEAD)

        XCTAssertFalse(fired, "unknown eventID must not fire any callback")
    }

    // MARK: 6. Nil callbacks do not crash

    func testCallbacksNilSafe() {
        let svc = HotkeyDispatchTestable()
        // All callbacks left nil
        // None of these must crash
        svc.handlePress(HotkeyID.toggle)
        svc.handlePress(HotkeyID.ptt)
        svc.handlePress(HotkeyID.chat)
        svc.handlePress(0xDEAD)
        // If we get here without crash, test passes
    }

    // MARK: 7. All three hotkey IDs are unique

    func testHotkeyIDsAreUnique() {
        let ids: [UInt32] = [HotkeyID.toggle, HotkeyID.ptt, HotkeyID.chat]
        let unique = Set(ids)
        XCTAssertEqual(unique.count, ids.count, "toggle/ptt/chat IDs must all be distinct")
        XCTAssertNotEqual(HotkeyID.toggle, HotkeyID.ptt)
        XCTAssertNotEqual(HotkeyID.ptt, HotkeyID.chat)
        XCTAssertNotEqual(HotkeyID.toggle, HotkeyID.chat)
    }

    // MARK: 8. noErr == 0 (OSStatus contract)

    func testStatusNoErrIsZero() {
        // HotkeyService uses `if ts == noErr` to gate hotkey registration.
        // The Carbon contract is noErr = 0. Verify this assumption holds
        // so the guard logic in install() is sound.
        let noErrValue: OSStatus = noErr
        XCTAssertEqual(noErrValue, 0, "Carbon noErr must equal 0")

        // Simulate success path: noErr triggers the registration branch
        let simulatedStatus: OSStatus = 0
        XCTAssertEqual(simulatedStatus, noErr, "status 0 must match noErr")

        // Simulate failure path: non-zero is an error
        let errorStatus: OSStatus = -1
        XCTAssertNotEqual(errorStatus, noErr, "non-zero status must not match noErr")
    }
}

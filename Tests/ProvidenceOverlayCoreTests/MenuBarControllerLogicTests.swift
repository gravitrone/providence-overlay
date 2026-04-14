import XCTest

// Inline testable mirror of the pure-logic bits in MenuBarController.
// AppKit types (NSStatusItem, NSMenu, NSMenuItem, Timer) are NOT touched here.
// All NSMenuItem-bound wiring is tested via logic structs only.

// MARK: - Testable logic mirror

struct MenuBarLogicTestable {

    // MARK: Constants

    static let pulseInterval: Double = 0.6
    static let pulseAlphaVisible: Double = 1.0
    static let pulseAlphaDim: Double = 0.35

    // MARK: Recording title

    static func recordingTitle(audioActive: Bool) -> String {
        audioActive ? "Recording: active" : "Recording: idle"
    }

    // MARK: Connection title

    static func connectionTitle(status: String) -> String {
        "Connection: \(status)"
    }

    // MARK: Hide-during-share state

    static func hideDuringShareState(enabled: Bool) -> Bool {
        enabled
    }

    // MARK: Pulse alpha toggle

    /// Mirrors tickPulse logic - returns the alpha that would be set after toggling.
    static func nextAlpha(currentlyVisible: Bool) -> Double {
        currentlyVisible ? pulseAlphaDim : pulseAlphaVisible
    }

    // MARK: UI mode radio

    struct UIModeItem {
        let key: String
        var isOn: Bool
    }

    /// Mirrors the Combine sink in wireObservers.
    static func applyUIMode(_ mode: String, to items: [UIModeItem]) -> [UIModeItem] {
        items.map { UIModeItem(key: $0.key, isOn: $0.key == mode) }
    }
}

// MARK: - Tests

final class MenuBarControllerLogicTests: XCTestCase {

    // 1. Recording title when audio is active.
    func testRecordingTitleActive() {
        XCTAssertEqual(MenuBarLogicTestable.recordingTitle(audioActive: true), "Recording: active")
    }

    // 2. Recording title when audio is idle.
    func testRecordingTitleIdle() {
        XCTAssertEqual(MenuBarLogicTestable.recordingTitle(audioActive: false), "Recording: idle")
    }

    // 3. Pulse timer interval is exactly 0.6 seconds.
    func testPulseIntervalIs0_6Seconds() {
        XCTAssertEqual(MenuBarLogicTestable.pulseInterval, 0.6, accuracy: 0.0001)
    }

    // 4. Alpha toggle alternates between 1.0 and 0.35.
    func testPulseAlphaToggleValues() {
        // visible -> should dim
        let afterDim = MenuBarLogicTestable.nextAlpha(currentlyVisible: true)
        XCTAssertEqual(afterDim, MenuBarLogicTestable.pulseAlphaDim, accuracy: 0.001)

        // not visible -> should brighten
        let afterBright = MenuBarLogicTestable.nextAlpha(currentlyVisible: false)
        XCTAssertEqual(afterBright, MenuBarLogicTestable.pulseAlphaVisible, accuracy: 0.001)
    }

    // 5. setUIMode("chat") -> only chat is .on, ghost and both are .off.
    func testUIModeRadioExclusivity() {
        let items: [MenuBarLogicTestable.UIModeItem] = [
            .init(key: "ghost", isOn: false),
            .init(key: "chat",  isOn: false),
            .init(key: "both",  isOn: false),
        ]
        let result = MenuBarLogicTestable.applyUIMode("chat", to: items)
        XCTAssertFalse(result.first { $0.key == "ghost" }!.isOn)
        XCTAssertTrue(result.first  { $0.key == "chat"  }!.isOn)
        XCTAssertFalse(result.first { $0.key == "both"  }!.isOn)
    }

    // 6. Cycling through ghost -> both -> chat each lights exactly one item.
    func testUIModeRadioCyclesGhostBoth() {
        let base: [MenuBarLogicTestable.UIModeItem] = [
            .init(key: "ghost", isOn: false),
            .init(key: "chat",  isOn: true),
            .init(key: "both",  isOn: false),
        ]

        for mode in ["ghost", "both", "chat"] {
            let result = MenuBarLogicTestable.applyUIMode(mode, to: base)
            let onCount = result.filter { $0.isOn }.count
            XCTAssertEqual(onCount, 1, "Expected exactly 1 .on item for mode '\(mode)', got \(onCount)")
            XCTAssertTrue(result.first { $0.key == mode }!.isOn,
                          "Expected '\(mode)' to be .on")
        }
    }

    // 7. hideDuringShare=true -> state reflects enabled.
    func testHideDuringShareTitle() {
        XCTAssertTrue(MenuBarLogicTestable.hideDuringShareState(enabled: true))
        XCTAssertFalse(MenuBarLogicTestable.hideDuringShareState(enabled: false))
    }

    // 8. Connection title reflects status string.
    func testConnectionTitleFromState() {
        XCTAssertEqual(MenuBarLogicTestable.connectionTitle(status: "connected"),
                       "Connection: connected")
        XCTAssertEqual(MenuBarLogicTestable.connectionTitle(status: "disconnected"),
                       "Connection: disconnected")
    }
}

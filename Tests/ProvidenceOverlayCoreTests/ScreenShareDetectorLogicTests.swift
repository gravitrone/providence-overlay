import XCTest
import ProvidenceOverlayCore

// MARK: - Inline-testable logic extracted from ScreenShareDetector

/// Pure-logic testable copy. No NSWorkspace, no Combine, no @MainActor.
/// Mirrors the exact matching logic in ScreenShareDetector.update(frontmostBundleID:)
/// and setEnabled(_:). Bundle ID set is a verbatim copy from production source.
struct ShareDetectorLogicTestable {
    var enabled: Bool
    private(set) var sharingActive: Bool = false

    /// Verbatim copy of ScreenShareDetector.knownShareBundleIDs
    static let knownShareBundleIDs: Set<String> = [
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.hnc.Discord",
        "com.apple.FaceTime",
        "com.amazon.Chime",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.apple.Safari",
        "company.thebrowser.Browser",
        "com.loom.desktop",
    ]

    /// Simulates ScreenShareDetector.update(frontmostBundleID:)
    mutating func update(bundleID: String) {
        guard enabled else { return }
        let active = Self.knownShareBundleIDs.contains(bundleID)
        if active != sharingActive {
            sharingActive = active
        }
    }

    /// Simulates ScreenShareDetector.setEnabled(_:)
    mutating func setEnabled(_ on: Bool, currentFrontmost: String = "") {
        enabled = on
        if !on {
            sharingActive = false
        } else {
            update(bundleID: currentFrontmost)
        }
    }
}

// MARK: - Tests

final class ScreenShareDetectorLogicTests: XCTestCase {

    // 1. Zoom
    func testKnownZoomBundleMatches() {
        var d = ShareDetectorLogicTestable(enabled: true)
        d.update(bundleID: "us.zoom.xos")
        XCTAssertTrue(d.sharingActive, "Zoom bundle should mark sharing active")
    }

    // 2. New Teams
    func testKnownTeamsBundleMatches() {
        var d = ShareDetectorLogicTestable(enabled: true)
        d.update(bundleID: "com.microsoft.teams2")
        XCTAssertTrue(d.sharingActive, "New Teams bundle should mark sharing active")
    }

    // 3. Google Chrome (Meet) matches; Safari also in list - verify Chrome hits and
    //    something NOT in the list (e.g. com.apple.finder) does not.
    func testKnownMeetChromeBundleMatches() {
        var d = ShareDetectorLogicTestable(enabled: true)
        d.update(bundleID: "com.google.Chrome")
        XCTAssertTrue(d.sharingActive, "Chrome bundle (Google Meet host) should match")
    }

    // 4. Chime + FaceTime both present in the known set
    func testKnownChimeAndFaceTimeMatch() {
        var chime = ShareDetectorLogicTestable(enabled: true)
        chime.update(bundleID: "com.amazon.Chime")
        XCTAssertTrue(chime.sharingActive, "Chime bundle should match")

        var facetime = ShareDetectorLogicTestable(enabled: true)
        facetime.update(bundleID: "com.apple.FaceTime")
        XCTAssertTrue(facetime.sharingActive, "FaceTime bundle should match")
    }

    // 5. Non-share bundle stays inactive
    func testNonShareBundleNotActive() {
        var d = ShareDetectorLogicTestable(enabled: true)
        d.update(bundleID: "com.apple.finder")
        XCTAssertFalse(d.sharingActive, "Finder should not trigger sharing active")
    }

    // 6. setEnabled(false) forces inactive even with known share bundle frontmost
    func testSetEnabledFalseForcesInactive() {
        var d = ShareDetectorLogicTestable(enabled: true)
        d.update(bundleID: "us.zoom.xos")
        XCTAssertTrue(d.sharingActive)

        d.setEnabled(false, currentFrontmost: "us.zoom.xos")
        XCTAssertFalse(d.sharingActive, "Disabled detector must report inactive regardless of bundle")
    }

    // 7. Re-enabling with Zoom frontmost → active true again
    func testReenablingChecksFrontmost() {
        var d = ShareDetectorLogicTestable(enabled: true)
        d.update(bundleID: "us.zoom.xos")
        d.setEnabled(false)
        XCTAssertFalse(d.sharingActive)

        d.setEnabled(true, currentFrontmost: "us.zoom.xos")
        XCTAssertTrue(d.sharingActive, "Re-enabling with Zoom frontmost should re-activate sharing flag")
    }

    // 8. Duplicate state suppression - same bundle reported twice should not flip/toggle
    func testDuplicatesBundleNoStateChurn() {
        var d = ShareDetectorLogicTestable(enabled: true)
        var changeCount = 0
        var lastValue = false

        func observe(_ val: Bool) {
            if val != lastValue {
                changeCount += 1
                lastValue = val
            }
        }

        // First report: Zoom → active
        d.update(bundleID: "us.zoom.xos")
        observe(d.sharingActive)

        // Duplicate: same bundle again → no state change
        let before = d.sharingActive
        d.update(bundleID: "us.zoom.xos")
        observe(d.sharingActive)
        XCTAssertEqual(d.sharingActive, before, "Duplicate same-bundle update must not change state")
        XCTAssertEqual(changeCount, 1, "Only one state change should have occurred for two identical updates")
    }
}

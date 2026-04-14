import XCTest
@testable import ProvidenceOverlayCore

final class ProvidenceOverlayCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(ProvidenceOverlayCore.version, "0.1.0-phase6")
    }

    func testClassifyMeeting() {
        let input = ClassifierInput(
            bundleID: "us.zoom.xos",
            windowTitle: "Zoom Meeting",
            axSummary: "",
            ocrText: nil,
            audioActive: true
        )
        XCTAssertEqual(ActivityClassifier.classify(input), .meeting)
    }

    func testClassifyCoding() {
        let input = ClassifierInput(
            bundleID: "com.microsoft.VSCode",
            windowTitle: "main.go",
            axSummary: "editor",
            ocrText: nil,
            audioActive: false
        )
        XCTAssertEqual(ActivityClassifier.classify(input), .coding)
    }

    func testClassifyBrowsingFallsThrough() {
        let input = ClassifierInput(
            bundleID: "com.google.Chrome",
            windowTitle: "example.com",
            axSummary: "link",
            ocrText: nil,
            audioActive: false
        )
        XCTAssertEqual(ActivityClassifier.classify(input), .browsing)
    }

    func testClassifyChromeMeetWithAudio() {
        let input = ClassifierInput(
            bundleID: "com.google.Chrome",
            windowTitle: "Meet",
            axSummary: "meeting ui",
            ocrText: nil,
            audioActive: true
        )
        XCTAssertEqual(ActivityClassifier.classify(input), .meeting)
    }

    func testClassifyIdleWhenEverythingEmpty() {
        let input = ClassifierInput(
            bundleID: nil,
            windowTitle: "",
            axSummary: "",
            ocrText: nil,
            audioActive: false
        )
        XCTAssertEqual(ActivityClassifier.classify(input), .idle)
    }

    func testClassifyGeneralFallback() {
        let input = ClassifierInput(
            bundleID: "com.example.unknown",
            windowTitle: "whatever",
            axSummary: "stuff",
            ocrText: nil,
            audioActive: false
        )
        XCTAssertEqual(ActivityClassifier.classify(input), .general)
    }
}

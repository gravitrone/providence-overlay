import XCTest
@testable import ProvidenceOverlayCore

final class ProvidenceOverlayCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(ProvidenceOverlayCore.version, "0.1.0-phase6")
    }
}

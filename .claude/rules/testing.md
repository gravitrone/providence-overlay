---
paths: ["Tests/**/*.swift"]
---

# Testing Conventions

- Every test MUST assert something meaningful. No `XCTAssertNoThrow` as the sole assertion.
- Test names describe the scenario: `testAddChatMessageTrimsAtLimit`, `testJaccardBothEmptyReturnsOne`.
- Use `XCTAssertEqual`/`XCTAssertTrue` etc. over custom comparators when possible.
- PREFER table-driven tests over copy-paste test functions.
- Pure-logic tests live in `Tests/ProvidenceOverlayCoreTests/` (no AppKit/ScreenCaptureKit - unit-test friendly).
- UI + framework-dependent code is manually verified; no XCTest for NSPanel, NSWorkspace observers, SCStream callbacks.
- Use `FileManager.default.temporaryDirectory` for filesystem tests; clean up in `tearDown`.
- No network calls - mock with in-memory doubles.
- `swift test` runs in ~5s on a clean build. Keep it fast - fail fast.

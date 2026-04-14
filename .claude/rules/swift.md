---
paths: ["Sources/**/*.swift"]
---

# Swift Conventions

- Module imports in this order, blank line between groups: Foundation/stdlib, Apple frameworks (AppKit, SwiftUI, Combine, AVFoundation...), third-party SPM packages (WhisperKit), local targets (ProvidenceOverlayCore).
- Section separators `// --- Section Name ---` with proper capitalization.
- Public types and methods documented with triple-slash comments (///). Exported symbols in `ProvidenceOverlayCore` MUST be documented.
- `@MainActor` on any class that touches AppKit/SwiftUI state. UI mutations go through MainActor.
- Prefer value types (struct) for data; reference types (class) only for identity-bearing objects (controllers, services, the app delegate).
- `@Published` + `ObservableObject` for SwiftUI state. Never expose `@Published` setters to background threads.
- `AsyncStream<T>` + `async`/`await` for long-lived producers. No Combine `Subject` chains for new code - use `@Published` or `AsyncStream`.
- Errors: throw typed `enum ... Error: Error` with localized descriptions when user-facing. Internal failures can use `struct BridgeError`.
- NEVER force-unwrap (`!`) on values that aren'''t compile-time guaranteed. Prefer `guard let ... else { return }` or nil-safe chains.
- NEVER use `try!` - catch or propagate.
- Sendable warnings are real - annotate `@unchecked Sendable` only with a serial queue explanation in a comment. `@preconcurrency import` is acceptable for framework-originated warnings (AVFoundation, ScreenCaptureKit).
- Callbacks that might outlive the owner capture `[weak self]`. Unowned only when lifetime is provably tied.
- NSPanel subclasses set every relevant window property in init, not later. Autosave names (`setFrameAutosaveName`) for any user-draggable window.

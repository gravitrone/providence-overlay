# Providence Overlay

Always-on transparent chat panel for Providence Core. Watches screen + audio, whispers suggestions. macOS 14+, Swift 5.9+.

This file is the canonical project rules for BOTH Claude Code and OpenAI Codex CLI.

## Critical Rules

- ALWAYS match Providence flame theme: gold #FFA50F primary, ember dark #422414, cream #F0D7B4 text
- ALWAYS use `.nonactivatingPanel` NSPanel with `.floating` level + `[.canJoinAllSpaces, .fullScreenAuxiliary]` collection behavior for any overlay window
- ALWAYS set `sharingType = .none` on panels for baseline stealth (works for legacy capture + Teams/Meet/Chime)
- ALWAYS run `swift build -c release` + `swift test` before committing
- PREFER feature branches (`feat/<name>`, `fix/<name>`, `chore/<name>`) - never commit to main directly

## Architecture

- Two SPM targets: `ProvidenceOverlay` (executable, AppKit + SwiftUI) + `ProvidenceOverlayCore` (pure logic, unit-testable)
- `AppState` (@MainActor, @Published) is the single source of truth. All UI binds to it
- Services wired at `OverlayApp.applicationDidFinishLaunching`: BridgeClient (UDS to TUI), CaptureService, AudioService, WhisperTranscriber, WakeWordService, ContextCompressor, ScreenShareDetector
- Two render surfaces: `SuggestionPanel` (ghost, click-through, auto-fade 30s) + `ChatPanel` (persistent, interactive, scrollable history)
- Window visibility via `Publishers.CombineLatest(state.$uiMode, state.$hiddenDueToShare)` - ghost/chat/both modes respect screen-share auto-hide
- UDS protocol: newline-delimited JSON `{"v":1,"type":"...","data":{...}}` at `~/.providence/run/overlay.sock`
- Context flow: overlay emits `context_update` → TUI prepends as `<system-reminder origin="overlay">` on next user turn

## Stack Decisions (Locked)

- Swift 5.9+, targeting macOS 14.2+ (Core Audio taps, on-device SFSpeechRecognizer)
- WhisperKit (SPM) for local Neural Engine transcription (tiny.en model)
- NSPanel + SwiftUI via NSHostingView - no standalone NSWindow
- NSVisualEffectView `.hudWindow` material for vibrancy blur
- Ad-hoc codesign for dev; `.app` bundle at `~/Applications/Providence Overlay.app` for stable TCC identity
- No third-party UI libraries; no UIKit (this is macOS)

## Commands

```
make build     # swift build -c release + ad-hoc codesign
make app       # wrap into Providence Overlay.app bundle
make install   # copy to ~/Applications + shim at ~/.providence/bin
make test      # swift test
make clean     # wipe .build + build/
```

Tests need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` when running outside Xcode.

## Implementation Pitfalls

- `DispatchQueue` passed to `SCStream.addStreamOutput(sampleHandlerQueue:)` is NOT retained by ScreenCaptureKit. Store as a property or ARC drops it and sample callbacks never fire.
- `sharingType = .none` is IGNORED by macOS 15+ ScreenCaptureKit. Legacy capture + Teams/Meet/Chime still respect it. `ScreenShareDetector` auto-hide covers the SCK gap.
- TCC responsibility chain: when providence-core spawns the overlay via `exec.Command`, macOS attributes screen-recording requests back to providence. Use `[overlay].spawn = false` + launch from a fresh shell to break the chain.
- `SCShareableContent` returns stale cache for ~500ms after TCC permission flips. Retry once with backoff if displays array is empty.
- Force-unwrapping (`!`) on framework returns crashes silently in release. Always `guard let ... else { return }` or chain nil-safely.
- `@MainActor` mutations dispatched from background threads need `await MainActor.run { ... }` or the @Published update silently races.
- Sendable warnings on AVFoundation closures: `@preconcurrency import AVFoundation` is acceptable. Don't blanket-silence via `@unchecked Sendable` without a serial queue explanation.

## Commit Style

Conventional commits: `feat|fix|refactor|docs|infra|test|chore(scope): description`

- Subject imperative mood, under 72 chars
- Body explains "why" for non-trivial changes
- NEVER add co-author tags or "Generated with Claude Code" attribution

## Compact Instructions

Always preserve: current branch, active phase work, TCC permission state, AppState fields being added, worktrees in flight, stealth/capture/audio pipeline wiring decisions, and the "responsible process" TCC workaround context.

## Do NOT

- Use long dashes; use "-" or commas
- Force-unwrap (`!`) or force-try (`try!`) - guard + propagate instead
- Import UIKit or iOS-only frameworks (this is macOS)
- Use private macOS APIs without a risk + fallback comment
- Commit `.build/`, `build/`, `.DS_Store`, or generated `.app` bundles

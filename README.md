# providence-overlay

Ambient AI overlay companion to the Providence Core TUI. Runs as a macOS menu bar app, connects over a Unix Domain Socket to the TUI process, and renders an always-on `NSPanel` for proactive suggestions.

## Requirements

- macOS 14.0+
- Swift 5.9+ toolchain (Xcode 15 or a standalone Swift.org toolchain)
- Screen Recording permission (for ScreenCaptureKit capture)
- Accessibility permission (for future AX tree reads, Phase 7+)
- Microphone permission (for future wake-phrase + meeting audio, Phase 7+)

## Build

```
make build      # release build + ad-hoc codesign with entitlements
make install    # copy binary into ~/.providence/bin/
make test       # run ProvidenceOverlayCore unit tests
make clean      # nuke .build/
```

## Launch

The overlay is normally spawned by the TUI via `/overlay start`. For manual dev runs:

```
~/.providence/bin/providence-overlay --socket=/tmp/providence-overlay.sock
```

Default socket path is `~/.providence/run/overlay.sock`.

## Protocol

Newline-delimited JSON envelopes:

```
{"v":1,"type":"<message type>","id":"<optional>","data":{...}}
```

Message types are defined in `Sources/ProvidenceOverlay/Bridge/Protocol.swift` and must match the Go-side spec in `providence-core`.

### Phase 6 messages

Client to server:

- `hello` at connect (`client_version`, `capabilities`, `pid`)
- `goodbye` at quit

Server to client:

- `welcome` at connect (session/engine/model/ember_active)
- `assistant_delta` (appended to panel text, triggers fade-in)
- `ember_state`
- `bye` (triggers disconnect and reconnect with exponential backoff)

## Phase 6 scope

Scaffold + UDS client + basic 1 fps `SCStream` (drops frames) + empty fade-in panel.

## Phase 7 scope

Ambient capture pipeline:

- `AdaptiveScheduler` - 0.2 / 1 / 2 / 5 fps modes (idle / active / meeting / burst) driven by `NSWorkspace.didActivateApplicationNotification`
- `FrameDedupe` - 64-bit dHash (9x8 grayscale via vImage), skip frames with < 3 bits changed
- `AXReader.snapshot()` - frontmost-app focused-window title + focus value, ~500 char summary, non-crashing when AX perm missing
- `ActivityClassifier` (in `ProvidenceOverlayCore`) - rule-based: coding / browsing / meeting / writing / idle / general
- `ContextCompressor` - gates `context_update` emission on (activity change | app change | error signal | 30s+ elapsed and hamming >= 8 | user-invoked). Loopback suppression for Providence TUI and overlay.
- Panel chrome: `ContextIndicatorView`, `SuggestionStreamView` with dismiss, `StatusFooterView`, 30s auto-fade
- `HotkeyService` - Cmd+Shift+P toggles panel `ignoresMouseEvents` with a 1px orange border accent when interactive

`ContextUpdate` gained an `origin` field (`"overlay"`).

Deferred:

- Audio capture + wake phrase
- OCR pipeline
- Plugin tab contributions

## Directory layout

```
Sources/
  ProvidenceOverlay/        # executable target
    App/                    # NSApplicationDelegate, menu bar, shared state, HotkeyService
    AI/                     # ContextCompressor
    Bridge/                 # UDS client, JSONL framing, envelope codecs
    Capture/                # SCStream + AdaptiveScheduler + FrameDedupe + AXReader
    UI/                     # SuggestionPanel + SwiftUI views (indicator, stream, footer)
    Util/                   # Logger
  ProvidenceOverlayCore/    # pure-logic library (ActivityClassifier lives here)
Tests/
  ProvidenceOverlayCoreTests/
```

## Relationship to providence-core

`providence-core` (separate repo) hosts the Go TUI, engine orchestration, and the UDS server. Its `bridge/swift-mac/` directory contains `ProvidenceCaptureKit` which will be consolidated with this repo in a later phase - for Phase 6 we intentionally avoid cross-repo SPM coupling and reimplement the minimal SCStream wrapper here.

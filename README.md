# providence-overlay

Ambient AI overlay companion to the Providence Core TUI. Runs as a macOS menu bar app, connects over a Unix Domain Socket to the TUI process, and renders an always-on `NSPanel` for proactive suggestions.

## Requirements

- macOS 14.0+
- Swift 5.9+ toolchain (Xcode 15 or a standalone Swift.org toolchain)
- Screen Recording permission (for ScreenCaptureKit capture)
- Accessibility permission (for future AX tree reads, Phase 7+)
- Microphone permission (for future wake-phrase + meeting audio, Phase 7+)

## Build & Install

```
make install
```

This wraps the binary in a proper `.app` bundle at `~/Applications/Providence Overlay.app` and installs a shim at `~/.providence/bin/providence-overlay` that execs the .app's binary. TCC identifies the app by its bundle ID (`com.gravitrone.providence.overlay`).

After install, macOS will prompt for Screen Recording + Accessibility permissions on first use. To reset permission decisions:

```
tccutil reset ScreenCapture com.gravitrone.providence.overlay
tccutil reset Accessibility com.gravitrone.providence.overlay
```

The binary the TUI spawns (`providence-overlay`) is the shim - but TCC sees the underlying .app bundle.

Other targets:

```
make build      # swift release build only (no bundle)
make app        # build + wrap into build/Providence Overlay.app
make test       # run ProvidenceOverlayCore unit tests
make clean      # nuke .build/ and build/
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

Deferred (phase 7):

- OCR pipeline
- Plugin tab contributions

## Phase 8 scope

Audio pipeline:

- `AudioService` - `AVAudioEngine` mic capture, RMS level meter, sustained-speech detector (`audioActive` flips true after >2s of speech-level input, false after 1s silence). Publishes 16kHz mono Float32 buffers via an AsyncStream plus a raw-format stream.
- `SystemAudioTap` - **stubbed** in phase 8. Real implementation needs `CATapDescription` + `AudioHardwareCreateProcessTap` (macOS 14.2+) plus aggregate-device wiring, which is large scope. The stub throws `.unavailable` so `AudioService` falls back to mic-only. Meeting transcripts come from mic audio only for now.
- `WhisperTranscriber` - wraps WhisperKit (`tiny.en` on Neural Engine). 5s rolling windows with 50% overlap. First launch downloads the model (~80MB) from HuggingFace. Graceful fallback: `#if canImport(WhisperKit)` means the rest of the pipeline still builds and runs if the SPM dep fails to resolve.
- `WakeWordService` - `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` matching the phrase `"hey providence"`. Not as efficient as Porcupine, but no vendored framework. Porcupine is the phase 10 upgrade path.
- `TTSService` - `AVSpeechSynthesizer` wrapper, disabled by default.
- Meeting mode: `ActivityClassifier` receives `audioActive` from `AppState`; when activity flips to `.meeting`, `CaptureService` sets `state.meetingMode = true` and calls `scheduler.markMeetingDetected()`. Meeting ending reverses both.
- `TranscriptView` - visible in `PanelRootView` only when `meetingMode && transcript != ""`. Shows last ~600 chars of rolling transcript.
- PTT hotkey: `Cmd+Option+Space` opens a 10s transcription window. A second press closes it early. On close, whatever Whisper has is sent as `user_query` with `source: "push_to_talk"`. (`Fn`-only would require IOKit HID event taps, deferred.)

Simplifications taken:

- `SystemAudioTap` stubbed - mic-only pipeline ships.
- Porcupine replaced with `SFSpeechRecognizer` on-device match.
- PTT is tap-based (not held), since `Fn` key needs IOKit HID.

Deferred (phase 8):

- Real system audio tap via `CATapDescription`
- Porcupine wake-word model
- Runtime menu-bar toggles (TTS on/off, wake-word disable)

## Phase 10

Final polish - runtime privacy, stealth, battery-aware capture, TTS routing.

### TTS routing

`TTSService` now speaks assistant replies only when the preceding user turn
came from `wake_word` or `push_to_talk`. Panel-typed queries and ambient
`context_update` replies stay silent. Enable via `[overlay] tts_enabled = true`
in `~/.providence/config.toml`.

### Stealth mode

The overlay panel sets `NSWindow.sharingType = .none` at launch, which hides
it from legacy screen-capture APIs (`CGDisplayCreateImage`, `screencapture` CLI)
and from all major screen-sharing tools (Zoom, Google Meet, Microsoft Teams,
Chime - all still use the legacy capture path as of 2026).

**Caveat:** Apple broke `sharingType = .none` for `ScreenCaptureKit` starting
in macOS 15. Apps using `SCStream` (including this overlay's own
`CaptureService`) see the panel regardless. There is no public workaround.
If you need true stealth on macOS 15+, don't share the display.

### Battery-aware capture

`AdaptiveScheduler` polls `BatteryMonitor` every second. When the machine is
on battery and level < 20 %, mode is forced to `.idle` (0.2 fps) and the
wake-word trigger is gated off. Restored when charging or level >= 25 %
(hysteresis prevents flapping at the threshold).

### Privacy exclusions

Menu-bar > *Privacy Exclusions* toggles a small set of common sensitive
apps (1Password, Keychain Access, Signal, Slack, Arc). `ContextCompressor`
drops any frame whose frontmost app's bundle ID is in the list. Persisted
to `~/.providence/overlay/exclusions.json` (best-effort; missing/corrupt
files tolerated). The TUI can preload the list via `overlay.exclude_apps`
in `config.toml`, which arrives in the `Welcome` envelope.

### Menu bar recording indicator

A pulsing flame animates the status item whenever `audioActive` or
`meetingMode` is on. The pulse uses a 0.6 s timer and flips `alphaValue` -
measured < 1 % CPU. **Never suppressed.** Privacy requirement: when we're
recording, you see it.

### Welcome protocol extensions

`Welcome` now carries optional `tts_enabled`, `position`, and
`excluded_apps` so TUI config drives overlay behaviour at runtime.
`PanelWindowController` animates to the new frame when `position` changes
between `right-sidebar` (default) and `bottom-bar`.

### Simplifications taken

- `ExclusionsManager` is in-memory + JSON; no iCloud sync or encryption.
- Menu-bar pulse uses `alphaValue` toggle, not a smooth spring animation.
- Exclusions submenu is a static list of five apps; no "add custom bundle ID"
  dialog (add via config or the JSON file for now).
- Wake-word suppression on low battery is silent - no user-facing toast.

## UI Modes

The overlay exposes two panels: the ghost suggestion panel (proactive
`assistant_delta` fade-ins) and a persistent transparent chat window.
Which one is visible is controlled by `[overlay].ui_mode` in
`~/.providence/config.toml` and by the menu bar *UI Mode* submenu.

Values:

- `ghost` - suggestions panel only (default, matches pre-Phase-C behaviour)
- `chat`  - persistent chat window only
- `both`  - both panels visible

Example config:

```toml
[overlay]
enable = true
ui_mode = "chat"
chat_history_limit = 50
chat_alpha = 0.92
chat_position = "right"
daily_token_budget = 50000
```

### Hotkeys

- `Cmd+Shift+P` - toggle ghost panel click-through (interactive vs ambient)
- `Cmd+Shift+C` - toggle chat window visibility (does not mutate `ui_mode`)
- `Cmd+Option+Space` - push-to-talk (10s transcription window; second tap ends early)

### Menu bar

- *UI Mode* submenu - switch between `ghost` / `chat` / `both` at runtime
- *Privacy Exclusions* - per-app capture suppression
- *Hide during screen share* - stealth auto-hide toggle (default ON)

## Directory layout

```
Sources/
  ProvidenceOverlay/        # executable target
    App/                    # NSApplicationDelegate, menu bar, shared state, HotkeyService
    AI/                     # ContextCompressor
    Audio/                  # mic pipeline, WhisperKit, wake word, TTS
    Bridge/                 # UDS client, JSONL framing, envelope codecs
    Capture/                # SCStream + AdaptiveScheduler + FrameDedupe + AXReader
    Privacy/                # StealthMode, ExclusionsManager (phase 10)
    UI/                     # SuggestionPanel + SwiftUI views (indicator, stream, footer)
    Util/                   # Logger + BatteryMonitor
  ProvidenceOverlayCore/    # pure-logic library (ActivityClassifier lives here)
Tests/
  ProvidenceOverlayCoreTests/
```

## Relationship to providence-core

`providence-core` (separate repo) hosts the Go TUI, engine orchestration, and the UDS server. Its `bridge/swift-mac/` directory contains `ProvidenceCaptureKit` which will be consolidated with this repo in a later phase - for Phase 6 we intentionally avoid cross-repo SPM coupling and reimplement the minimal SCStream wrapper here.

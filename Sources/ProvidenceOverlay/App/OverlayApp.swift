import AppKit
import Combine

@main
@MainActor
final class OverlayApp: NSObject, NSApplicationDelegate {
    var socketPath: String = ""
    private var menuBar: MenuBarController?
    private var bridgeClient: BridgeClient?
    private var panel: PanelWindowController?
    private var chatWindowController: ChatWindowController?
    private var captureService: CaptureService?
    private var appState: AppState!
    private var frameDedupe: FrameDedupe?
    private var emitter: ScreenshotEmitter?
    private var hotkeyService: HotkeyService?

    private var audioService: AudioService?
    private var whisper: WhisperTranscriber?
    private var wakeWord: WakeWordService?
    private var tts: TTSService?
    private var cancellables = Set<AnyCancellable>()
    private var pttWindowTask: Task<Void, Never>?
    private var pttActive = false

    private var exclusions: ExclusionsManager?
    private var screenShareDetector: ScreenShareDetector?

    static func main() {
        let delegate = OverlayApp()

        var socketPath = "\(NSHomeDirectory())/.providence/run/overlay.sock"
        for arg in CommandLine.arguments {
            if arg.hasPrefix("--socket=") {
                socketPath = String(arg.dropFirst("--socket=".count))
            }
        }
        delegate.socketPath = socketPath

        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        exclusions = ExclusionsManager()
        menuBar = MenuBarController(state: appState, exclusions: exclusions)
        bridgeClient = BridgeClient(socketPath: socketPath, state: appState)
        panel = PanelWindowController(state: appState)
        chatWindowController = ChatWindowController(
            state: appState,
            bridgeClient: bridgeClient!
        )

        if let w = panel?.window {
            StealthMode.apply(to: w, enabled: true)
        }

        let detector = ScreenShareDetector()
        detector.setEnabled(appState.screenShareAutoHide)
        screenShareDetector = detector

        detector.$screenSharingActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.appState.hiddenDueToShare = active
            }
            .store(in: &cancellables)

        appState.$screenShareAutoHide
            .dropFirst()
            .sink { [weak self] on in
                self?.screenShareDetector?.setEnabled(on)
            }
            .store(in: &cancellables)

        let dedupe = FrameDedupe()
        let emit = ScreenshotEmitter(bridge: bridgeClient!, state: appState, exclusions: exclusions)
        frameDedupe = dedupe
        emitter = emit

        captureService = CaptureService(state: appState, dedupe: dedupe, emitter: emit)

        hotkeyService = HotkeyService(state: appState, panelController: panel!)
        hotkeyService?.onPushToTalk = { [weak self] in
            Task { @MainActor in self?.handlePTT() }
        }
        hotkeyService?.onChatToggle = { [weak self] in
            self?.chatWindowController?.toggleVisibility()
        }
        hotkeyService?.install()

        audioService = AudioService()
        whisper = WhisperTranscriber()
        wakeWord = WakeWordService()
        tts = TTSService(enabled: false)
        wireAudio()

        bridgeClient?.onAssistantDelta = { [weak self] text, finished in
            self?.tts?.feedDelta(text, finished: finished)
        }
        bridgeClient?.onWelcome = { [weak self] w in
            guard let self = self else { return }
            if let tts = w.tts_enabled {
                self.appState?.ttsEnabled = tts
                self.tts?.setEnabled(tts)
            }
        }

        appState.$ttsEnabled
            .sink { [weak self] e in self?.tts?.setEnabled(e) }
            .store(in: &cancellables)

        // Independent toggle sinks: each privacy kill switch fully stops or
        // restarts its underlying service. Drop-first so we don't double-start
        // on the initial @Published emission below.
        appState.$micEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self = self else { return }
                Task { await self.applyMic(enabled: enabled) }
            }
            .store(in: &cancellables)

        appState.$screenEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                guard let self = self else { return }
                Task { await self.applyScreen(enabled: enabled) }
            }
            .store(in: &cancellables)

        bridgeClient?.connect()

        // Boot services only if their toggle is on. First-launch defaults are
        // both true so this is the typical path; persisted-off is respected.
        let capture = captureService
        if appState.screenEnabled {
            Task { await capture?.start() }
        }

        let w = whisper
        let audio = audioService
        let wake = wakeWord
        let micOn = appState.micEnabled
        Task {
            await w?.load()
            if micOn {
                do {
                    try await audio?.start()
                } catch {
                    Logger.log("audio: start failed: \(error)")
                }
                do {
                    try await wake?.start()
                } catch {
                    Logger.log("wake word: start failed: \(error)")
                }
            }
        }
    }

    private func applyMic(enabled: Bool) async {
        if enabled {
            do { try await audioService?.start() } catch {
                Logger.log("mic: start failed: \(error)")
            }
            do { try await wakeWord?.start() } catch {
                Logger.log("mic: wake word start failed: \(error)")
            }
        } else {
            audioService?.stop()
            wakeWord?.stop()
            whisper?.clear()
            await MainActor.run {
                self.appState.transcript = ""
                self.appState.audioActive = false
            }
        }
    }

    private func applyScreen(enabled: Bool) async {
        if enabled {
            await captureService?.start()
        } else {
            await captureService?.stop()
        }
    }

    private func wireAudio() {
        guard let audio = audioService,
              let wake = wakeWord,
              let whisper = whisper else { return }

        wake.onDetect = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.tts?.armForNextReply(source: "wake_word")
                self.bridgeClient?.sendUserQuery("hey providence listening", source: "wake_word")
            }
        }

        // Always-on transcription when mic is enabled. No more meeting-mode gating.
        Task { [weak self] in
            guard let self = self else { return }
            for await buffer in audio.rawAudioStream() {
                guard let wake = self.wakeWord else { break }
                wake.feed(buffer)
            }
        }
        Task { [weak self] in
            guard let self = self else { return }
            for await buffer in audio.audioStream() {
                guard self.appState.micEnabled else { continue }
                await self.whisper?.feed(buffer)
            }
        }

        audio.$audioActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.appState?.audioActive = active
            }
            .store(in: &cancellables)

        whisper.$rollingTranscript
            .receive(on: DispatchQueue.main)
            .sink { [weak self] t in
                self?.appState?.transcript = t
            }
            .store(in: &cancellables)
        whisper.$latestSegment
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seg in
                self?.appState?.latestSegment = seg
            }
            .store(in: &cancellables)
        wake.$armed
            .receive(on: DispatchQueue.main)
            .sink { [weak self] armed in
                self?.appState?.wakeWordArmed = armed
            }
            .store(in: &cancellables)
    }

    /// PTT: first tap opens a 10s transcription window. Second tap inside the window
    /// ends it early. On end, whatever Whisper has is sent as a user_query.
    private func handlePTT() {
        if pttActive {
            finishPTT()
            return
        }
        pttActive = true
        appState.pttActive = true
        whisper?.clear()
        Logger.log("ptt: window opened (10s)")
        pttWindowTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            await MainActor.run {
                if self?.pttActive == true {
                    self?.finishPTT()
                }
            }
        }
    }

    private func finishPTT() {
        pttWindowTask?.cancel()
        pttWindowTask = nil
        pttActive = false
        appState.pttActive = false
        let text = whisper?.rollingTranscript ?? ""
        Logger.log("ptt: window closed, text=\(text.prefix(80))")
        if !text.isEmpty {
            tts?.armForNextReply(source: "push_to_talk")
            bridgeClient?.sendUserQuery(text, source: "push_to_talk")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridgeClient?.disconnect()
        let capture = captureService
        Task { await capture?.stop() }
        audioService?.stop()
        wakeWord?.stop()
    }
}

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
    private var adaptiveScheduler: AdaptiveScheduler?
    private var frameDedupe: FrameDedupe?
    private var compressor: ContextCompressor?
    private var hotkeyService: HotkeyService?

    // Phase 8
    private var audioService: AudioService?
    private var whisper: WhisperTranscriber?
    private var wakeWord: WakeWordService?
    private var tts: TTSService?
    private var cancellables = Set<AnyCancellable>()
    private var pttWindowTask: Task<Void, Never>?
    private var pttActive = false

    // Phase 10
    private var exclusions: ExclusionsManager?

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
        chatWindowController = ChatWindowController(state: appState, bridgeClient: bridgeClient!)

        // Phase 10: stealth - hide overlay panel from screen capture.
        // sharingType = .none works for legacy APIs and most screen-share apps;
        // macOS 15+ ScreenCaptureKit ignores it (documented limitation).
        if let w = panel?.window {
            StealthMode.apply(to: w, enabled: true)
        }

        let scheduler = AdaptiveScheduler(state: appState)
        let dedupe = FrameDedupe()
        let comp = ContextCompressor(bridge: bridgeClient!)
        comp.exclusions = exclusions
        adaptiveScheduler = scheduler
        frameDedupe = dedupe
        compressor = comp

        captureService = CaptureService(
            state: appState,
            scheduler: scheduler,
            dedupe: dedupe,
            compressor: comp
        )

        hotkeyService = HotkeyService(state: appState, panelController: panel!)
        hotkeyService?.onPushToTalk = { [weak self] in
            Task { @MainActor in self?.handlePTT() }
        }
        hotkeyService?.install()

        // Phase 8: audio pipeline
        audioService = AudioService()
        whisper = WhisperTranscriber()
        wakeWord = WakeWordService()
        tts = TTSService(enabled: false)
        wireAudio()

        // Phase 10: route assistant deltas through TTS. TTS only speaks when
        // armed by armForNextReply (wake_word/push_to_talk). Ambient replies silent.
        bridgeClient?.onAssistantDelta = { [weak self] text, finished in
            self?.tts?.feedDelta(text, finished: finished)
        }
        bridgeClient?.onWelcome = { [weak self] w in
            guard let self = self else { return }
            if let tts = w.tts_enabled {
                self.appState?.ttsEnabled = tts
                self.tts?.setEnabled(tts)
            }
            if let apps = w.excluded_apps, !apps.isEmpty {
                self.exclusions?.setInitial(apps)
            }
        }

        // Propagate ttsEnabled changes to the TTS service.
        appState.$ttsEnabled
            .sink { [weak self] e in self?.tts?.setEnabled(e) }
            .store(in: &cancellables)

        bridgeClient?.connect()

        let capture = captureService
        Task { await capture?.start() }

        let w = whisper
        let audio = audioService
        let wake = wakeWord
        Task {
            await w?.load()
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

    private func wireAudio() {
        guard let audio = audioService,
              let wake = wakeWord,
              let whisper = whisper else { return }

        wake.onDetect = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                // Phase 10: wake word gated by battery-aware scheduler.
                guard self.appState?.wakeWordAllowed != false else {
                    Logger.log("wake: suppressed (battery low)")
                    return
                }
                self.tts?.armForNextReply(source: "wake_word")
                self.bridgeClient?.sendUserQuery("hey providence listening", source: "wake_word")
                self.adaptiveScheduler?.beginBurst(duration: 3)
            }
        }

        // Feed raw buffers to wake word (always) and 16k buffers to whisper (meeting mode only).
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
                let shouldFeed = self.appState.meetingMode || self.pttActive
                if shouldFeed {
                    await self.whisper?.feed(buffer)
                }
            }
        }

        // AudioService.audioActive -> AppState.audioActive (consumed by ActivityClassifier).
        audio.$audioActive
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in
                self?.appState?.audioActive = active
            }
            .store(in: &cancellables)

        // WhisperTranscriber.rollingTranscript -> AppState.transcript
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

        // When meeting mode ends, clear the transcript buffer.
        appState.$meetingMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meeting in
                if !meeting {
                    self?.whisper?.clear()
                }
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

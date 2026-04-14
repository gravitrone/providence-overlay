import AppKit

@main
@MainActor
final class OverlayApp: NSObject, NSApplicationDelegate {
    var socketPath: String = ""
    private var menuBar: MenuBarController?
    private var bridgeClient: BridgeClient?
    private var panel: PanelWindowController?
    private var captureService: CaptureService?
    private var appState: AppState!
    private var adaptiveScheduler: AdaptiveScheduler?
    private var frameDedupe: FrameDedupe?
    private var compressor: ContextCompressor?
    private var hotkeyService: HotkeyService?

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
        menuBar = MenuBarController(state: appState)
        bridgeClient = BridgeClient(socketPath: socketPath, state: appState)
        panel = PanelWindowController(state: appState)

        let scheduler = AdaptiveScheduler(state: appState)
        let dedupe = FrameDedupe()
        let comp = ContextCompressor(bridge: bridgeClient!)
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
        hotkeyService?.install()

        bridgeClient?.connect()

        let capture = captureService
        Task { await capture?.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridgeClient?.disconnect()
        let capture = captureService
        Task { await capture?.stop() }
    }
}

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

    static func main() {
        let delegate = OverlayApp()

        // Parse --socket=<path> arg
        var socketPath = "\(NSHomeDirectory())/.providence/run/overlay.sock"
        for arg in CommandLine.arguments {
            if arg.hasPrefix("--socket=") {
                socketPath = String(arg.dropFirst("--socket=".count))
            }
        }
        delegate.socketPath = socketPath

        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)  // reinforce LSUIElement at runtime
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()
        menuBar = MenuBarController(state: appState)

        bridgeClient = BridgeClient(socketPath: socketPath, state: appState)
        panel = PanelWindowController(state: appState)
        captureService = CaptureService(state: appState)

        // Connect
        bridgeClient?.connect()

        // Start capture at 1 fps (Phase 6 baseline)
        let capture = captureService
        Task { await capture?.start(fps: 1) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridgeClient?.disconnect()
        let capture = captureService
        Task { await capture?.stop() }
    }
}

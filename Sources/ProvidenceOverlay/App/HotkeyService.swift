import AppKit
import Carbon
import Carbon.HIToolbox

@MainActor
final class HotkeyService {
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let state: AppState
    private weak var panelController: PanelWindowController?
    private static let eventID: UInt32 = 0xBEE5

    init(state: AppState, panelController: PanelWindowController) {
        self.state = state
        self.panelController = panelController
    }

    func install() {
        let typeSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var specs = [typeSpec]
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotkeyHandler,
            1,
            &specs,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        let id = EventHotKeyID(signature: OSType(0x50524F56), id: Self.eventID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(cmdKey | shiftKey),
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotkeyRef = ref
            Logger.log("hotkey: Cmd+Shift+P registered")
        } else {
            Logger.log("hotkey: register failed status=\(status)")
        }
    }

    fileprivate func handlePress() {
        panelController?.toggleClickThrough()
    }

    private static let hotkeyHandler: EventHandlerUPP = { _, _, userData in
        guard let userData = userData else { return noErr }
        let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in service.handlePress() }
        return noErr
    }

    deinit {
        if let r = hotkeyRef { UnregisterEventHotKey(r) }
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}

import AppKit
import Carbon
import Carbon.HIToolbox

@MainActor
final class HotkeyService {
    private var toggleHotkeyRef: EventHotKeyRef?
    private var pttHotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let state: AppState
    private weak var panelController: PanelWindowController?
    private static let toggleEventID: UInt32 = 0xBEE5
    private static let pttEventID: UInt32 = 0xBEE6

    /// Callback: fires on PTT press (Cmd+Option+Space). Treated as a momentary tap
    /// that opens a 10s transcription window; a second press early-finishes it.
    var onPushToTalk: (() -> Void)?

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

        // Cmd+Shift+P -> toggle panel click-through
        let toggleID = EventHotKeyID(signature: OSType(0x50524F56), id: Self.toggleEventID)
        var tref: EventHotKeyRef?
        let ts = RegisterEventHotKey(
            UInt32(kVK_ANSI_P),
            UInt32(cmdKey | shiftKey),
            toggleID,
            GetApplicationEventTarget(),
            0,
            &tref
        )
        if ts == noErr {
            toggleHotkeyRef = tref
            Logger.log("hotkey: Cmd+Shift+P registered")
        } else {
            Logger.log("hotkey: toggle register failed status=\(ts)")
        }

        // Cmd+Option+Space -> PTT (Fn alternative since Fn needs IOKit HID)
        let pttID = EventHotKeyID(signature: OSType(0x50524F56), id: Self.pttEventID)
        var pref: EventHotKeyRef?
        let ps = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | optionKey),
            pttID,
            GetApplicationEventTarget(),
            0,
            &pref
        )
        if ps == noErr {
            pttHotkeyRef = pref
            Logger.log("hotkey: Cmd+Option+Space (PTT) registered")
        } else {
            Logger.log("hotkey: PTT register failed status=\(ps)")
        }
    }

    fileprivate func handlePress(_ eventID: UInt32) {
        switch eventID {
        case Self.toggleEventID:
            panelController?.toggleClickThrough()
        case Self.pttEventID:
            onPushToTalk?()
        default:
            break
        }
    }

    private static let hotkeyHandler: EventHandlerUPP = { _, event, userData in
        guard let userData = userData, let event = event else { return noErr }
        var hk = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hk
        )
        if status != noErr { return noErr }
        let id = hk.id
        let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
        Task { @MainActor in service.handlePress(id) }
        return noErr
    }

    deinit {
        if let r = toggleHotkeyRef { UnregisterEventHotKey(r) }
        if let r = pttHotkeyRef { UnregisterEventHotKey(r) }
        if let h = handlerRef { RemoveEventHandler(h) }
    }
}

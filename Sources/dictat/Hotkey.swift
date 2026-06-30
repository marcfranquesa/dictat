import AppKit
import Carbon.HIToolbox

/// Registers a single system-wide hotkey and fires `onPress` when it's pressed.
/// The key combo can be changed at runtime via `apply(_:)`.
final class Hotkey {
    var onPress: () -> Void = {}

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id = EventHotKeyID(signature: OSType(0x44494354 /* "DICT" */), id: 1)

    init() {
        installHandler()
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }

    /// (Re)register the global hotkey to the given shortcut.
    func apply(_ shortcut: Shortcut) {
        unregister()
        RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Carbon needs a C callback, so route through the userData pointer.
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let hotkey = Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID
                )
                // Ignore the hotkey while the user is recording a new one.
                if hkID.id == 1, !ShortcutRecorder.isCapturing {
                    DispatchQueue.main.async { hotkey.onPress() }
                }
                return noErr
            },
            1, &eventType, selfPtr, &handler
        )
    }
}

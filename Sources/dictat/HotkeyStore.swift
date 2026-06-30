import AppKit
import Carbon.HIToolbox
import Combine

/// A user-chosen global shortcut: a virtual key code plus modifier flags.
struct Shortcut: Equatable, Codable {
    var keyCode: UInt16
    var modifierFlagsRaw: UInt   // NSEvent.ModifierFlags rawValue, masked to the four we allow
    var keyLabel: String         // pretty name for the key, captured at record time

    static let `default` = Shortcut(
        keyCode: UInt16(kVK_Space),
        modifierFlagsRaw: NSEvent.ModifierFlags([.control, .option]).rawValue,
        keyLabel: "Space"
    )

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlagsRaw) }

    /// Menu-bar / button display, e.g. "⌃⌥Space".
    var display: String {
        var s = ""
        if modifierFlags.contains(.control) { s += "⌃" }
        if modifierFlags.contains(.option) { s += "⌥" }
        if modifierFlags.contains(.shift) { s += "⇧" }
        if modifierFlags.contains(.command) { s += "⌘" }
        return s + keyLabel
    }

    /// Carbon modifier mask for RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        var c: UInt32 = 0
        if modifierFlags.contains(.control) { c |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { c |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { c |= UInt32(shiftKey) }
        if modifierFlags.contains(.command) { c |= UInt32(cmdKey) }
        return c
    }

    /// Build a Shortcut from a captured key-down event (modifiers already validated non-empty).
    static func from(event: NSEvent) -> Shortcut {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return Shortcut(keyCode: event.keyCode, modifierFlagsRaw: mods.rawValue, keyLabel: label(for: event))
    }

    private static func label(for event: NSEvent) -> String {
        if let special = specialKeys[event.keyCode] { return special }
        if let chars = event.charactersIgnoringModifiers?.uppercased(),
           let first = chars.first,
           first.isLetter || first.isNumber || "`-=[]\\;',./".contains(first) {
            return String(first)
        }
        return "Key \(event.keyCode)"
    }

    private static let specialKeys: [UInt16: String] = [
        49: "Space", 36: "Return", 76: "Enter", 48: "Tab", 51: "Delete", 117: "Fwd Del",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "PgUp", 121: "PgDn",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
}

/// Persists the chosen shortcut and publishes changes so the app can re-register the
/// global hotkey and refresh its UI.
final class HotkeyStore: ObservableObject {
    static let shared = HotkeyStore()
    private let defaultsKey = "dictat.shortcut"

    @Published var shortcut: Shortcut { didSet { save() } }

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(Shortcut.self, from: data) {
            shortcut = decoded
        } else {
            shortcut = .default
        }
    }

    func reset() { shortcut = .default }

    private func save() {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

/// Captures the next key combo the user presses, via a local event monitor that only
/// fires while the (focused) Settings window is active. Esc cancels; a combo with no
/// modifier is rejected (and swallowed) so you can't bind a bare key by accident.
final class ShortcutRecorder: ObservableObject {
    /// True while any recorder is listening — the global hotkey checks this so pressing
    /// the *current* shortcut mid-recording doesn't also trigger dictation.
    static private(set) var isCapturing = false

    @Published var isRecording = false
    var onCapture: (Shortcut) -> Void = { _ in }

    private var monitor: Any?

    func start() {
        guard !isRecording else { return }
        isRecording = true
        ShortcutRecorder.isCapturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.isRecording else { return event }
            if event.keyCode == UInt16(kVK_Escape) { self.stop(); return nil }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return nil }   // require a modifier; swallow the key
            self.onCapture(Shortcut.from(event: event))
            self.stop()
            return nil
        }
    }

    func stop() {
        isRecording = false
        ShortcutRecorder.isCapturing = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}

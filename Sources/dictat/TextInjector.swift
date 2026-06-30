import AppKit

/// Puts text on the clipboard and pastes it into the frontmost app at the cursor by
/// synthesizing ⌘V. The text is left on the clipboard by design (the user asked for both
/// "type at cursor" and "copy to clipboard").
enum TextInjector {
    /// Returns true if the app is trusted for Accessibility (required to post key events).
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Copy text to the clipboard without pasting.
    static func copyToClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Copy to the clipboard and paste at the cursor (⌘V).
    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        copyToClipboard(text)
        // Don't paste while the user is still holding the hotkey's modifiers — a held
        // ⌃/⌥/⇧ combines with the synthetic ⌘V and the paste silently does nothing.
        // Wait for them to clear (up to ~0.75s), then paste.
        pasteWhenModifiersClear()
    }

    private static func pasteWhenModifiersClear(remainingAttempts: Int = 25) {
        let held = CGEventSource.flagsState(.combinedSessionState)
        let interfering: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        if remainingAttempts <= 0 || held.isDisjoint(with: interfering) {
            paste()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                pasteWhenModifiersClear(remainingAttempts: remainingAttempts - 1)
            }
        }
    }

    private static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // "v"

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

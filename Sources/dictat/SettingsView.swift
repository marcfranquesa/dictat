import AppKit
import SwiftUI

/// The Settings panel: a clean shortcut recorder. Click the chip, press your combo, done.
struct SettingsView: View {
    @ObservedObject private var store = HotkeyStore.shared
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dictation shortcut").font(.headline)

            HStack(spacing: 12) {
                Button(action: toggleRecording) {
                    Text(recorder.isRecording ? "Press keys…" : store.shortcut.display)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .frame(minWidth: 130)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(recorder.isRecording
                                      ? Color.accentColor.opacity(0.18)
                                      : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(recorder.isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                              lineWidth: recorder.isRecording ? 2 : 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !recorder.isRecording {
                    Button("Reset") { store.reset() }
                        .buttonStyle(.link)
                }
            }

            Text(recorder.isRecording
                 ? "Press a key with at least one modifier (⌘ ⌥ ⌃ ⇧). Esc to cancel."
                 : "Press it anywhere to start/stop dictation.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(width: 320)
        .onAppear { recorder.onCapture = { store.shortcut = $0 } }
        .onDisappear { recorder.stop() }
    }

    private func toggleRecording() {
        recorder.isRecording ? recorder.stop() : recorder.start()
    }
}

/// Hosts `SettingsView` in a small, reusable window. The app is a menu-bar accessory,
/// so we activate the app and bring the window to the front explicitly.
/// Only ever used on the main thread (from menu-bar actions).
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: host)
            w.title = "dictat Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

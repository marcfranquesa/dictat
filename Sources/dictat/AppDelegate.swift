import AppKit
import Combine

/// Ties everything together: a menu-bar icon, a global hotkey, and the
/// record → transcribe → paste pipeline. Everything runs locally on-device.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private var hotkey: Hotkey?
    private var hotkeyCancellable: AnyCancellable?
    private var uiState: UIState = .loadingModel
    private var lastTranscript = ""

    private enum UIState {
        case loadingModel
        case ready
        case recording
        case transcribing
        case error(String)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        render(.loadingModel)

        // Ask for Accessibility up front (needed to paste at the cursor).
        TextInjector.ensureAccessibility(prompt: true)

        // Register the global hotkey and keep it in sync with the user's chosen shortcut.
        // sink() fires immediately with the current value, so this also does the initial bind.
        let hotkey = Hotkey()
        hotkey.onPress = { [weak self] in self?.toggle() }
        self.hotkey = hotkey
        hotkeyCancellable = HotkeyStore.shared.$shortcut.sink { [weak self] shortcut in
            hotkey.apply(shortcut)
            self?.refreshMenu()
        }

        // Load the local model (downloads once, then cached + offline).
        Task {
            await transcriber.loadIfNeeded()
            let state = await transcriber.state
            await MainActor.run {
                switch state {
                case .ready: self.render(.ready)
                case let .failed(message): self.render(.error(message))
                default: break
                }
            }
        }
    }

    // MARK: - Pipeline

    private func toggle() {
        if recorder.isRecording {
            stopAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task {
            guard await transcriber.state == .ready else { return }
            do {
                try recorder.start()
                render(.recording)
            } catch {
                render(.error(error.localizedDescription))
            }
        }
    }

    private func stopAndTranscribe() {
        let samples = recorder.stop()
        render(.transcribing)
        Task {
            do {
                let text = try await transcriber.transcribe(samples)
                await MainActor.run {
                    if !text.isEmpty {
                        self.lastTranscript = text
                        TextInjector.insert(text)   // clipboard + auto-paste at cursor
                    }
                    self.render(.ready)
                }
            } catch {
                await MainActor.run { self.render(.error(error.localizedDescription)) }
            }
        }
    }

    // MARK: - Menu bar

    /// Re-render the menu using the last known state (e.g. after the shortcut changes).
    private func refreshMenu() { render(uiState) }

    private func render(_ state: UIState) {
        uiState = state
        let button = statusItem.button
        let shortcut = HotkeyStore.shared.shortcut.display
        let menu = NSMenu()
        menu.autoenablesItems = false   // we manage enabled state ourselves

        // The mascot is the menu-bar icon; state is shown as a short word beside it.
        button?.image = Mascot.menuBar
        button?.imagePosition = .imageLeading

        switch state {
        case .loadingModel:
            button?.title = " loading…"
            menu.addItem(disabled("Downloading / loading model…"))
        case .ready:
            button?.title = ""
            menu.addItem(disabled("Ready — \(shortcut) to dictate"))
        case .recording:
            button?.title = " listening…"
            menu.addItem(disabled("Recording — \(shortcut) to stop"))
        case .transcribing:
            button?.title = " transcribing…"
            menu.addItem(disabled("Transcribing…"))
        case let .error(message):
            button?.title = " error"
            menu.addItem(disabled("Error: \(message)"))
        }

        // Pasting at the cursor needs Accessibility. Surface it clearly if it's missing,
        // since CGEvent paste fails silently without it (clipboard copy still works).
        if !AXIsProcessTrusted() {
            menu.addItem(.separator())
            let warn = NSMenuItem(
                title: "⚠️ Enable Accessibility to paste…",
                action: #selector(openAccessibilitySettings), keyEquivalent: ""
            )
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let toggleItem = NSMenuItem(
            title: recorder.isRecording ? "Stop Dictation" : "Start Dictation",
            action: #selector(menuToggle), keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        let copyPreviousItem = NSMenuItem(
            title: "Copy previous", action: #selector(copyPrevious), keyEquivalent: ""
        )
        copyPreviousItem.target = self
        copyPreviousItem.isEnabled = !lastTranscript.isEmpty
        menu.addItem(copyPreviousItem)

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit dictat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func menuToggle() { toggle() }

    @objc private func openSettings() { SettingsWindowController.shared.show() }

    @objc private func copyPrevious() {
        TextInjector.copyToClipboard(lastTranscript)
    }

    @objc private func openAccessibilitySettings() {
        // Re-trigger the system prompt, then open the Accessibility pane directly.
        TextInjector.ensureAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

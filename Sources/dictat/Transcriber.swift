import Foundation
import FluidAudio

/// Wraps FluidAudio's Parakeet engine. Loads the model once (downloading it from
/// Hugging Face on first run, ~600 MB, cached afterwards) and transcribes 16 kHz mono
/// Float samples on demand. Everything runs on-device.
actor Transcriber {
    enum State: Equatable {
        case idle          // not loaded yet
        case loading
        case ready
        case failed(String)
    }

    private var manager: UnifiedAsrManager?
    private(set) var state: State = .idle

    /// Download + load the Parakeet model. Safe to call repeatedly; only loads once.
    func loadIfNeeded() async {
        guard manager == nil else { return }
        state = .loading
        do {
            let manager = UnifiedAsrManager()
            try await manager.loadModels()   // downloads on first run, then offline
            // Privacy lock: once the model is on disk, forbid FluidAudio from ever
            // touching the network again. Dictation is now provably offline.
            DownloadUtils.enforceOffline = true
            self.manager = manager
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Transcribe mono 16 kHz audio. Returns trimmed text (may be empty).
    func transcribe(_ samples: [Float]) async throws -> String {
        guard let manager else {
            throw NSError(
                domain: "dictat",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Model not loaded yet."]
            )
        }
        let text = try await manager.transcribe(samples)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

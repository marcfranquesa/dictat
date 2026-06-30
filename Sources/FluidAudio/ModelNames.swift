import Foundation

/// HuggingFace repository for the vendored Parakeet Unified offline ASR models.
///
/// Trimmed from FluidAudio's full multi-model `Repo` enum down to the single
/// repository the Parakeet Unified offline batch path needs.
public enum Repo: String, CaseIterable, Sendable {
    case parakeetUnified = "FluidInference/parakeet-unified-en-0.6b-coreml"

    /// Repository slug (without owner).
    public var name: String {
        switch self {
        case .parakeetUnified:
            return "parakeet-unified-en-0.6b-coreml"
        }
    }

    /// Fully qualified HuggingFace repo path (owner/name).
    public var remotePath: String {
        "FluidInference/\(name)"
    }

    /// Optional remote subdirectory (none for the unified repo).
    public var subPath: String? {
        nil
    }

    /// Local folder name used for caching.
    public var folderName: String {
        name.replacingOccurrences(of: "-coreml", with: "")
    }
}

/// Centralized model names for the vendored Parakeet Unified offline ASR path.
public enum ModelNames {

    /// Parakeet Unified 0.6B (FastConformer-RNNT) CoreML bundle names.
    public enum ParakeetUnified {
        public static let preprocessorFile = "parakeet_unified_preprocessor.mlmodelc"
        /// Encoders ship in two precisions. int8 (per-channel linear symmetric
        /// weights) is the default: identical test-clean WER to fp16
        /// (1.83%/2.14% vs 1.82%/2.15%), same ANE latency, half the download.
        public static let streamingEncoderInt8File = "parakeet_unified_encoder_streaming_70_13_13_int8.mlmodelc"
        public static let streamingEncoderFp16File = "parakeet_unified_encoder_streaming_70_13_13.mlmodelc"
        public static let offlineEncoderInt8File = "parakeet_unified_encoder_int8.mlmodelc"
        public static let offlineEncoderFp16File = "parakeet_unified_encoder.mlmodelc"
        public static let decoderFile = "parakeet_unified_decoder.mlmodelc"
        public static let jointDecisionFile = "parakeet_unified_joint_decision_single_step.mlmodelc"
        public static let vocab = "vocab.json"
        public static let metadata = "metadata.json"

        public static func streamingEncoderFile(precision: UnifiedEncoderPrecision) -> String {
            precision == .int8 ? streamingEncoderInt8File : streamingEncoderFp16File
        }

        public static func offlineEncoderFile(precision: UnifiedEncoderPrecision) -> String {
            precision == .int8 ? offlineEncoderInt8File : offlineEncoderFp16File
        }

        public static func requiredModels(variant: String?) -> Set<String> {
            let isOffline = variant?.hasPrefix("offline") == true
            let isFp16 = variant?.hasSuffix("fp16") == true
            let precision: UnifiedEncoderPrecision = isFp16 ? .fp16 : .int8
            let encoder =
                isOffline
                ? offlineEncoderFile(precision: precision)
                : streamingEncoderFile(precision: precision)
            return [
                preprocessorFile,
                encoder,
                decoderFile,
                jointDecisionFile,
                vocab,
                metadata,
            ]
        }
    }

    static func getRequiredModelNames(for repo: Repo, variant: String?) -> Set<String> {
        switch repo {
        case .parakeetUnified:
            // Variants: nil/"fp16" (streaming), "offline"/"offline-fp16" (batch).
            return ModelNames.ParakeetUnified.requiredModels(variant: variant)
        }
    }
}

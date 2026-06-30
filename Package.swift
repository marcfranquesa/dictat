// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dictat",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        // Vendored, trimmed subset of FluidAudio (Apache-2.0, FluidInference).
        // Only the Parakeet Unified offline ASR path is kept. Module name is
        // intentionally "FluidAudio" so `import FluidAudio` in dictat's own
        // sources needs no change. See LICENSE-FluidAudio and README.md.
        .target(
            name: "FluidAudio",
            dependencies: [
                "MachTaskSelfWrapper",
            ],
            path: "Sources/FluidAudio"
        ),
        .target(
            name: "MachTaskSelfWrapper",
            path: "Sources/MachTaskSelfWrapper",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "dictat",
            dependencies: [
                "FluidAudio",
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)

// swift-tools-version:5.9
import PackageDescription

// MeanderKit is the pure, testable core (audio, transcription, cleanup, pipeline).
// The macOS app target lives in Sources/MeanderApp and is built by the Xcode
// project generated from project.yml (it depends on this package's MeanderKit).
let package = Package(
    name: "Meander",
    platforms: [.macOS(.v14)], // WhisperKit requires macOS 14+
    products: [
        .library(name: "MeanderKit", targets: ["MeanderKit"]),
        .library(name: "MeanderMLX", targets: ["MeanderMLX"]),
        .executable(name: "meander-eval", targets: ["MeanderEval"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.4"),
        // On-device LLM cleanup (MLX). Isolated in the MeanderMLX target so this
        // heavy dependency stays out of MeanderKit and the shipping app until the
        // eval proves a small local model is worth it.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.4")),
        // Needed directly for the `#huggingFaceTokenizerLoader()` macro expansion.
        // Pinned to WhisperKit's exact range (<1.2.0) so resolution stays put and
        // MLX's newer-transformers HF download path is deliberately avoided (we
        // load models from a local directory instead).
        .package(url: "https://github.com/huggingface/swift-transformers.git", .upToNextMinor(from: "1.1.6")),
    ],
    targets: [
        .target(
            name: "MeanderKit",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/MeanderKit"
        ),
        // On-device LLM cleanup via MLX. Kept as its own target so nothing in
        // MeanderKit or the app links MLX until we choose to ship it.
        .target(
            name: "MeanderMLX",
            dependencies: [
                "MeanderKit",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/MeanderMLX"
        ),
        // Cleanup-quality eval harness. Runs the enhancement-contract cases
        // through each cleanup provider and writes a human-readable report
        // (contract pass rate + latency per model). Run: `swift run meander-eval`.
        .executableTarget(
            name: "MeanderEval",
            dependencies: ["MeanderKit", "MeanderMLX"],
            path: "Sources/MeanderEval"
        ),
        .testTarget(
            name: "MeanderKitTests",
            dependencies: ["MeanderKit"],
            path: "Tests/MeanderKitTests"
        ),
    ]
)

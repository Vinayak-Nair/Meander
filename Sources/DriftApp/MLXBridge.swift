import Foundation
import DriftKit
import DriftMLX

/// Wires the MLX cleanup provider (which lives in the heavier DriftMLX target)
/// into DriftKit's `CleanupFactory` at launch, so the pipeline can use it without
/// DriftKit depending on MLX. Holds a single warm `MLXCleanup` so the model loads
/// once and stays resident.
enum MLXBridge {
    /// Registers the "mlx" provider if its model is present on disk. If the model
    /// hasn't been downloaded, "mlx" simply falls back to deterministic cleanup.
    static func register(modelsRoot: URL) {
        let dir = modelsRoot.appendingPathComponent("mlx/qwen2.5-0.5b-4bit", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path) else {
            return
        }
        let provider = MLXCleanup(
            id: "mlx",
            displayName: "On-device LLM (MLX)",
            modelDirectory: dir
        )
        CleanupFactory.externalBuilders["mlx"] = { _, _, _ in provider }
        // Warm the model in the background so the first dictation isn't cold.
        // Timed into the latency log so we can confirm the one-time GPU/graph
        // warm-up cost lands here at launch rather than on the first dictation.
        Task.detached(priority: .utility) {
            let start = DispatchTime.now()
            do {
                try await provider.prewarm()
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                LatencyLog.record(String(format: "mlx prewarm %.0fms (load + 1-token generation)", ms))
            } catch {
                LatencyLog.record("mlx prewarm FAILED: \(error)")
            }
        }
    }
}

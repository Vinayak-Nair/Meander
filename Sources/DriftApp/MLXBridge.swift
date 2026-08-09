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
    ///
    /// `settings` is captured for the dictionary rather than read from the
    /// factory's per-call argument: the provider is a single warm instance, so it
    /// has to read the vocabulary itself at cleanup time.
    static func register(modelsRoot: URL, settings: Settings) {
        let dir = modelsRoot.appendingPathComponent("mlx/qwen2.5-0.5b-4bit", isDirectory: true)
        seedBundledModelIfNeeded(at: dir)
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path) else {
            return
        }
        let provider = MLXCleanup(
            id: "mlx",
            displayName: "On-device LLM (MLX)",
            modelDirectory: dir,
            vocabularyProvider: { settings.vocabularyBook }
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

    /// Copies the model shipped inside the app bundle (see scripts/release.sh)
    /// into the models directory on first launch, so the loader — which reads a
    /// plain directory, not the HF hub — finds it. No-op once installed, and in
    /// dev builds, where scripts/fetch-eval-model.sh populates the directory.
    private static func seedBundledModelIfNeeded(at dir: URL) {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("config.json").path) { return }
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let bundled = resourceURL
            .appendingPathComponent("BundledModels/mlx/qwen2.5-0.5b-4bit", isDirectory: true)
        guard fm.fileExists(atPath: bundled.appendingPathComponent("config.json").path) else { return }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for item in try fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) {
                let dest = dir.appendingPathComponent(item.lastPathComponent)
                guard !fm.fileExists(atPath: dest.path) else { continue }
                try fm.copyItem(at: item, to: dest)
            }
        } catch {
            LatencyLog.record("mlx seed FAILED: \(error)")
        }
    }
}

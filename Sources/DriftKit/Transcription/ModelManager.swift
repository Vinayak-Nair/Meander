import CoreML
import Foundation
import FluidAudio
import WhisperKit

/// Manages speech model storage and loading: where models live, whether they're
/// present, downloading them (with progress) on first run, and producing a ready
/// `Transcriber`. This is what makes the user flow zero-friction: no manual
/// downloads, no Terminal.
public final class ModelManager {
    private let settings: Settings

    public init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Root directory for models. Honors a user-chosen path (e.g. external SSD),
    /// otherwise Application Support/Drift/models.
    public var modelsDirectory: URL {
        if let custom = settings.modelStoragePath, !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Drift/models", isDirectory: true)
    }

    /// Whether the given variant has been downloaded and its folder still exists.
    public func isDownloaded(_ variant: String) -> Bool {
        guard let path = settings.modelFolderPath(for: variant) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    public var isDefaultModelDownloaded: Bool {
        isSelectedModelDownloaded()
    }

    public func isSelectedModelDownloaded(variant requested: String? = nil) -> Bool {
        switch settings.transcriptionBackend {
        case .fluidAudioEnglish:
            return isFluidAudioEnglishDownloaded
        case .nemotronEnglish:
            return isNemotronEnglishDownloaded
        case .whisperKit:
            return isDownloaded(requested ?? settings.modelVariant)
        }
    }

    /// Ensures the variant is present (downloading with progress if needed), loads
    /// it, and returns a ready `Transcriber`.
    /// - Parameter onProgress: download progress in 0...1 (only called while downloading).
    public func loadTranscriber(
        variant requested: String? = nil,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> Transcriber {
        switch settings.transcriptionBackend {
        case .fluidAudioEnglish:
            return try await loadFluidAudioEnglishTranscriber(onProgress: onProgress)
        case .nemotronEnglish:
            return try await loadNemotronEnglishTranscriber(onProgress: onProgress)
        case .whisperKit:
            return try await loadWhisperKitTranscriber(variant: requested, onProgress: onProgress)
        }
    }

    private var fluidAudioModelsDirectory: URL {
        modelsDirectory.appendingPathComponent("FluidAudio", isDirectory: true)
    }

    private var fluidAudioEnglishModelDirectory: URL {
        fluidAudioModelsDirectory.appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)
    }

    private var isFluidAudioEnglishDownloaded: Bool {
        AsrModels.modelsExist(at: fluidAudioEnglishModelDirectory, version: .v3)
            || bundledFluidAudioModelsDirectory != nil
    }

    /// The default model shipped inside the app bundle, if present. Release builds
    /// bundle Parakeet v3 (see scripts/release.sh) so first-run English dictation
    /// needs no download. Returns nil for dev builds, which fall back to download.
    private var bundledFluidAudioModelsDirectory: URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let dir = resourceURL.appendingPathComponent("BundledModels/FluidAudio", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Copies the bundled model into the models directory on first use so the
    /// offline load path finds it. No-op if already installed or nothing is bundled.
    private func seedBundledFluidAudioEnglishModelIfNeeded() throws {
        let fm = FileManager.default
        if AsrModels.modelsExist(at: fluidAudioEnglishModelDirectory, version: .v3) { return }
        guard let bundled = bundledFluidAudioModelsDirectory else { return }
        try fm.createDirectory(at: fluidAudioModelsDirectory, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: bundled, includingPropertiesForKeys: nil) {
            let dest = fluidAudioModelsDirectory.appendingPathComponent(item.lastPathComponent)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            try fm.copyItem(at: item, to: dest)
        }
    }

    private func loadFluidAudioEnglishTranscriber(
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> Transcriber {
        try FileManager.default.createDirectory(
            at: fluidAudioModelsDirectory, withIntermediateDirectories: true
        )
        try seedBundledFluidAudioEnglishModelIfNeeded()
        let models = try await AsrModels.downloadAndLoad(
            to: fluidAudioEnglishModelDirectory,
            version: .v3,
            progressHandler: { progress in
                onProgress?(progress.fractionCompleted)
            }
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        return FluidAudioEnglishTranscriber(asrManager: manager)
    }

    // MARK: Nemotron streaming (English, prototype)

    /// Base directory the Nemotron streaming repo downloads into. The manager
    /// appends the repo's own folder structure under here.
    private var nemotronModelsBaseDir: URL {
        modelsDirectory.appendingPathComponent("FluidAudioStreaming", isDirectory: true)
    }

    /// Chunk size for the streaming engine. Smaller = more frequent live partial
    /// updates (snappier on-screen text) at some throughput/accuracy cost.
    private let nemotronChunkSize: NemotronChunkSize = .ms1120

    private var nemotronEnglishCacheDir: URL {
        nemotronModelsBaseDir.appendingPathComponent(
            nemotronChunkSize.repo.folderName, isDirectory: true
        )
    }

    private var isNemotronEnglishDownloaded: Bool {
        FileManager.default.fileExists(
            atPath: nemotronEnglishCacheDir.appendingPathComponent("metadata.json").path
        )
    }

    private func loadNemotronEnglishTranscriber(
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> Transcriber {
        try FileManager.default.createDirectory(
            at: nemotronModelsBaseDir, withIntermediateDirectories: true
        )
        let manager = StreamingNemotronAsrManager(requestedChunkSize: nemotronChunkSize)
        try await manager.loadModels(
            to: nemotronModelsBaseDir,
            configuration: nil,
            progressHandler: { progress in
                onProgress?(progress.fractionCompleted)
            }
        )
        return NemotronEnglishTranscriber(manager: manager)
    }

    private func loadWhisperKitTranscriber(
        variant requested: String? = nil,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> Transcriber {
        let variant = requested ?? settings.modelVariant
        try FileManager.default.createDirectory(
            at: modelsDirectory, withIntermediateDirectories: true
        )

        let folder: URL
        if let saved = settings.modelFolderPath(for: variant),
           FileManager.default.fileExists(atPath: saved) {
            folder = URL(fileURLWithPath: saved) // offline-friendly fast path
        } else {
            folder = try await WhisperKit.download(
                variant: variant,
                downloadBase: modelsDirectory,
                from: settings.modelRepo,
                progressCallback: { progress in
                    onProgress?(progress.fractionCompleted)
                }
            )
            settings.setModelFolderPath(folder.path, for: variant)
        }

        // Run the audio encoder on the GPU rather than the Neural Engine. WhisperKit
        // defaults the encoder to `.cpuAndNeuralEngine`, which triggers a one-time
        // on-device ANE compilation that, for the large Whisper encoders (e.g.
        // large-v3-turbo), can peg ANECompilerService for many minutes on first load
        // and makes the app look hung on "Preparing model…". `.cpuAndGPU` skips that
        // compile and loads in seconds, at a small inference-speed cost. The decoder
        // stays on the ANE (its compile is fast) for good runtime throughput.
        let computeOptions = ModelComputeOptions(audioEncoderCompute: .cpuAndGPU)
        let config = WhisperKitConfig(modelFolder: folder.path, computeOptions: computeOptions)
        let kit = try await WhisperKit(config)
        let settings = self.settings
        return WhisperKitTranscriber(
            whisperKit: kit,
            vocabularyProvider: { settings.customVocabulary }
        )
    }
}

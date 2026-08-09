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
    /// otherwise Application Support/Meander/models.
    public var modelsDirectory: URL {
        if let custom = settings.modelStoragePath, !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Meander/models", isDirectory: true)
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
        case .fluidAudioParakeet:
            return isFluidAudioDownloaded
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
        case .fluidAudioParakeet:
            return try await loadFluidAudioTranscriber(onProgress: onProgress)
        case .nemotronEnglish:
            return try await loadNemotronEnglishTranscriber(onProgress: onProgress)
        case .whisperKit:
            return try await loadWhisperKitTranscriber(variant: requested, onProgress: onProgress)
        }
    }

    /// The Parakeet build behind the FluidAudio backend. **Must stay `.v3`.**
    ///
    /// v3 is the multilingual model (25 European languages). It decides its own
    /// output language from the acoustics, and on short push-to-talk phrases it
    /// has too little context to decide well: "Same for Gamma" once came back as
    /// "Сеймфор Гамма".
    ///
    /// The fix is not a smaller model, it is the language hint that
    /// `FluidAudioTranscriber` passes on every call. FluidAudio's v3 decoder
    /// filters each token against the declared language's script, so a wrong-script
    /// token is replaced mid-decode by the best same-script candidate. That
    /// enforcement is **v3-only**: it needs the top-K outputs that the v3 joint
    /// model exposes, and `AsrManager` logs and ignores the hint on any other
    /// build. Downgrading to the English-only v2 would silently discard the
    /// guarantee along with the multilingual capability.
    public static let parakeetVersion: AsrModelVersion = .v3

    /// The repo holding the pinned version. FluidAudio keeps its own version to
    /// repo mapping internal, so Meander restates it: both constants must name the
    /// same build, and `EnglishBackendTests` pins the pair.
    public static let parakeetRepo: Repo = .parakeetV3

    /// Folder the model lives in, taken from the pinned repo so the directory and
    /// the loaded weights can never disagree.
    public static var parakeetFolderName: String {
        parakeetRepo.folderName
    }

    private var fluidAudioModelsDirectory: URL {
        modelsDirectory.appendingPathComponent("FluidAudio", isDirectory: true)
    }

    private var parakeetModelDirectory: URL {
        fluidAudioModelsDirectory.appendingPathComponent(
            Self.parakeetFolderName, isDirectory: true
        )
    }

    private var isFluidAudioDownloaded: Bool {
        AsrModels.modelsExist(at: parakeetModelDirectory, version: Self.parakeetVersion)
            || bundledFluidAudioModelsDirectory != nil
    }

    /// The pinned model shipped inside the app bundle, if present. Release
    /// builds bundle it (see scripts/release.sh) so first-run dictation
    /// needs no download. Returns nil for dev builds, which fall back to download.
    ///
    /// Resolves the pinned folder by name rather than accepting whatever the bundle
    /// happens to contain: a build carrying the wrong Parakeet version must read as
    /// "not bundled" and download the right one, never load weights that cannot
    /// honor the language hint.
    private var bundledFluidAudioModelsDirectory: URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let dir = resourceURL
            .appendingPathComponent("BundledModels/FluidAudio", isDirectory: true)
            .appendingPathComponent(Self.parakeetFolderName, isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Copies the bundled model into the models directory on first use so the
    /// offline load path finds it. No-op if already installed or nothing is bundled.
    private func seedBundledParakeetModelIfNeeded() throws {
        let fm = FileManager.default
        let version = Self.parakeetVersion
        if AsrModels.modelsExist(at: parakeetModelDirectory, version: version) { return }
        guard let bundled = bundledFluidAudioModelsDirectory else { return }
        try fm.createDirectory(at: fluidAudioModelsDirectory, withIntermediateDirectories: true)
        guard !fm.fileExists(atPath: parakeetModelDirectory.path) else { return }
        try fm.copyItem(at: bundled, to: parakeetModelDirectory)
    }

    private func loadFluidAudioTranscriber(
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> Transcriber {
        try FileManager.default.createDirectory(
            at: fluidAudioModelsDirectory, withIntermediateDirectories: true
        )
        try seedBundledParakeetModelIfNeeded()
        let models = try await AsrModels.downloadAndLoad(
            to: parakeetModelDirectory,
            version: Self.parakeetVersion,
            progressHandler: { progress in
                onProgress?(progress.fractionCompleted)
            }
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        let settings = self.settings
        return FluidAudioTranscriber(
            asrManager: manager,
            // Constructed unconditionally; it downloads its model only if and
            // when the user actually has dictionary terms.
            booster: ParakeetVocabularyBooster(modelDirectory: ctcModelDirectory),
            vocabularyProvider: { settings.vocabularyBook }
        )
    }

    /// Where the auxiliary CTC model for dictionary boosting lives. Kept beside
    /// the Parakeet weights under Meander's own models directory, so a user who
    /// points Meander at an external drive gets this there too rather than in
    /// FluidAudio's default cache.
    private var ctcModelDirectory: URL {
        fluidAudioModelsDirectory.appendingPathComponent(
            CtcModelVariant.ctc110m.repo.folderName, isDirectory: true
        )
    }

    /// Whether acoustic dictionary boosting is ready to use on the Parakeet
    /// backend. False either because the model isn't installed or because the
    /// active backend doesn't use it.
    public var isParakeetVocabularyBoostInstalled: Bool {
        settings.transcriptionBackend == .fluidAudioParakeet
            && ParakeetVocabularyBooster.isModelInstalled(at: ctcModelDirectory)
    }

    /// Installs the auxiliary CTC model that lets the dictionary be checked
    /// against the audio on the Parakeet backend.
    ///
    /// Only worth its download once the user actually has dictionary terms,
    /// which is why nothing calls this at first launch. No-op when the model is
    /// already present, when the dictionary is empty, or on other backends.
    @discardableResult
    public func installParakeetVocabularyBoostIfNeeded() async -> Bool {
        guard settings.transcriptionBackend == .fluidAudioParakeet else { return false }
        guard !settings.vocabularyBook.isEmpty else { return false }
        let booster = ParakeetVocabularyBooster(modelDirectory: ctcModelDirectory)
        guard await !booster.isModelInstalled else { return true }
        do {
            try await booster.prepare()
            LatencyLog.record("parakeet vocab boost model installed")
            return true
        } catch {
            // Dictation is unaffected; the dictionary just keeps working through
            // the text-level layers until this succeeds on a later attempt.
            LatencyLog.record("parakeet vocab boost model install failed: \(error)")
            return false
        }
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

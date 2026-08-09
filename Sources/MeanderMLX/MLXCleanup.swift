import Foundation
import MeanderKit
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

/// On-device LLM cleanup via MLX. Conforms to MeanderKit's `CleanupProvider`, so
/// it drops into the same pipeline slot as the deterministic cleaner and is
/// scored by the same eval.
///
/// The model is loaded from a local directory (see scripts/fetch-eval-model.sh)
/// rather than the HuggingFace hub, deliberately: the hub loader would pull a
/// newer swift-transformers that conflicts with WhisperKit's pin. The expensive
/// `ModelContainer` is loaded once and kept warm in `WarmMLXModel`; each cleanup
/// spins up a fresh, cheap `ChatSession` so no transcript history accumulates.
public final class MLXCleanup: CleanupProvider {
    public let id: String
    public let displayName: String
    public let requiresNetwork = false

    private let warm: WarmMLXModel
    /// Read at cleanup time (not captured once) so dictionary edits apply to the
    /// next dictation, matching `WhisperKitTranscriber`'s decode-time biasing.
    private let vocabularyProvider: @Sendable () -> VocabularyBook

    public init(
        id: String,
        displayName: String,
        modelDirectory: URL,
        vocabularyProvider: @escaping @Sendable () -> VocabularyBook = { .init() }
    ) {
        self.id = id
        self.displayName = displayName
        self.warm = WarmMLXModel(modelDirectory: modelDirectory)
        self.vocabularyProvider = vocabularyProvider
    }

    /// Loads the model ahead of first use so the first dictation is already warm.
    public func prewarm() async throws { try await warm.prewarm() }

    public func clean(_ text: String, language _: Language) async throws -> String {
        let instructions = EnhancementContract.systemPrompt(vocabulary: vocabularyProvider())
        let cleaned = try await warm.clean(text, instructions: instructions)
        return cleaned.isEmpty ? text : cleaned
    }
}

/// Owns the single, long-lived `ModelContainer`. Loading weights is the costly
/// step; keeping the container alive keeps them resident so cleanup is just
/// generation time.
actor WarmMLXModel {
    private let modelDirectory: URL
    private var container: ModelContainer?

    init(modelDirectory: URL) { self.modelDirectory = modelDirectory }

    private func loadedContainer() async throws -> ModelContainer {
        if let container { return container }
        let loaded = try await LLMModelFactory.shared.loadContainer(
            from: modelDirectory,
            using: #huggingFaceTokenizerLoader()
        )
        container = loaded
        return loaded
    }

    /// Loads the weights *and* runs one tiny throwaway generation.
    ///
    /// Loading alone isn't enough: the expensive one-time costs only fire when
    /// arithmetic actually executes on the GPU — Metal pipeline states get
    /// compiled per kernel, MLX traces and fuses its lazy graph, the buffer pool
    /// and KV cache allocate for the first time, the GPU ramps off its idle
    /// clock, and the mmap'd weight pages fault in. Running a real (1-token)
    /// generation here forces all of that at launch, in the background, so the
    /// user's first dictation lands in steady state instead of paying the cliff.
    func prewarm() async throws {
        let container = try await loadedContainer()
        let session = ChatSession(
            container,
            instructions: EnhancementContract.systemPrompt,
            generateParameters: Self.parameters(maxTokens: 1)
        )
        _ = try await session.respond(to: "hi")
    }

    /// Shared sampling config. Low temperature: cleanup should be near
    /// deterministic, not creative.
    private static func parameters(maxTokens: Int? = nil) -> GenerateParameters {
        GenerateParameters(maxTokens: maxTokens, temperature: 0.2)
    }

    /// `instructions` is the system prompt for this call: the enhancement
    /// contract, plus the user's dictionary clause when they have one. Passed in
    /// per call rather than stored so a dictionary edit takes effect immediately
    /// without reloading the container.
    func clean(_ text: String, instructions: String) async throws -> String {
        let container = try await loadedContainer()
        // Fresh session per call: warm model, but no accumulated history.
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: Self.parameters()
        )
        let response = try await session.respond(to: text)
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

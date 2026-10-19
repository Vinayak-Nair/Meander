# Architecture

## Targets and ownership

[Package.swift](../Package.swift) defines MeanderKit, MeanderMLX, MeanderEval, and MeanderKitTests. [project.yml](../project.yml) generates the macOS app target and links both libraries. MeanderKit has no UI target dependency, but uses macOS audio/model frameworks; “UI-independent” does not mean platform-independent.

MeanderMLX isolates heavy MLX dependencies from core logic. The app already links it despite older comments in Package.swift describing a future integration. [MLXBridge.swift](../Sources/MeanderApp/MLXBridge.swift) registers a warm provider through CleanupFactory and seeds bundled assets when available.

## Dictation flow

1. [MeanderApp.swift](../Sources/MeanderApp/MeanderApp.swift) creates the dashboard/menu-bar scenes and invokes `AppState.bootstrap()` on launch.
2. [AppState.swift](../Sources/MeanderApp/AppState.swift) coordinates permissions, model loading, hotkey lifecycle, overlay state, and the current destination. ModelManager supplies a transcriber to Pipeline.
3. [Pipeline.swift](../Sources/MeanderKit/Pipeline.swift) records audio, selects batch or streaming behavior through the transcriber interface, sanitizes output, and applies cleanup. Streaming callbacks cross audio/UI boundaries; AppState awaits streaming startup before finishing it.
4. Pipeline resolves a formatting profile, applies command mode, and bypasses vocabulary/cleanup for code destinations. Other destinations receive vocabulary correction and the selected cleanup provider; provider errors fall back to deterministic cleanup and then prepared text.
5. AppState records the transcript, calls [Paster.swift](../Sources/MeanderApp/Paster.swift), and starts [CorrectionWatcher.swift](../Sources/MeanderApp/CorrectionWatcher.swift). Paster synthesizes paste and restores prior clipboard representations only if its clipboard change is still current. CorrectionWatcher reads destination text through Accessibility and passes learned corrections back into vocabulary.

## Speech and vocabulary

Read [Transcriber.swift](../Sources/MeanderKit/Transcription/Transcriber.swift), [ModelManager.swift](../Sources/MeanderKit/Transcription/ModelManager.swift), and the selected backend implementation before changing model behavior. Backends include FluidAudio Parakeet, WhisperKit, and Nemotron implementations; do not infer their identical capabilities from the shared protocol.

[ParakeetVocabularyBooster.swift](../Sources/MeanderKit/Transcription/ParakeetVocabularyBooster.swift), [ConstrainedCTCScorer.swift](../Sources/MeanderKit/Transcription/ConstrainedCTCScorer.swift), and [SoundAlikeRescorer.swift](../Sources/MeanderKit/Transcription/SoundAlikeRescorer.swift) implement acoustic vocabulary assistance. Text correction and learned aliases also affect the cleanup input. Preserve the guards tested in [ParakeetVocabularyBoosterTests.swift](../Tests/MeanderKitTests/ParakeetVocabularyBoosterTests.swift), including declining without downloading when the auxiliary model is absent. AppState separately schedules auxiliary installation; distinguish installation from inference-time behavior.

## Cleanup and evaluation

[CleanupProvider.swift](../Sources/MeanderKit/Cleanup/CleanupProvider.swift) owns the protocol, registry, factory, and shared cloud/Ollama prompt construction. MLX registration comes from the app bridge; an unavailable external provider falls through to deterministic cleanup.

[EnhancementContract.swift](../Sources/MeanderKit/Cleanup/EnhancementContract.swift) defines the local LLM enhancement prompt. Do not assume every provider uses that exact prompt. [MeanderEval/main.swift](../Sources/MeanderEval/main.swift) evaluates raw/deterministic providers and adds MLX models when a config.json file exists in the corresponding local model directory, writing Markdown and HTML reports. XCTest prompt-integrity checks do not establish model quality.

## Privacy and operational boundaries

- Cloud cleanup is opt-in text processing; audio transcription stays on device. Model downloads are separate network operations.
- Clipboard data, destination field contents, saved transcript history, and learned vocabulary are sensitive. Inspect source, not real user data, unless explicitly authorized.
- [DictationCapture.swift](../Sources/MeanderKit/Audio/DictationCapture.swift) is a diagnostic path called from batch processing. It saves WAV audio only when its capture directory exists. Do not create that directory for routine testing.
- Pipeline latency logging and correction diagnostics have filesystem side effects. Do not treat local-first as meaning no local persistence.
- App entitlements, stable signing, microphone access, and Accessibility affect manual testing. See [workflows](workflows.md); avoid changing permissions or replacing the installed app during automated verification.

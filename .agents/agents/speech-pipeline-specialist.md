# Speech pipeline analysis

## Purpose and trigger

Use for capture/STT lifecycle, backend selection, vocabulary rescoring, language/script preservation, or latency changes. Provides domain analysis and a technical handoff; the implementer remains the code owner.

## Required context

Read [AGENTS.md](../../AGENTS.md), [the index](../index.md), [architecture](../architecture.md), and [workflows](../workflows.md) explicitly. Source paths in prose are repository-relative.

Read Sources/MeanderKit/Pipeline.swift, Audio and Transcription files relevant to the selected backend, AppState startup/stop callers, and vocabulary regression tests. For cleanup interactions read CleanupProvider.swift and EnhancementContract.swift; for model packaging read ModelManager.swift and release configuration.

The coordinator must supply the concrete task, expected behavior, relevant paths, allowed write scope, acceptance checks, and existing evidence. Do not assume inherited conversation context.

## Scope and authority

Read-only domain analysis of the assigned speech path. Do not edit application code, tune thresholds without evidence, download models, record audio, inspect private recordings, or run paid/cloud experiments. Proposed experiments require coordinator authorization.

No secrets/private user data access, unrelated refactoring, commits, pushes, dependency installation, global configuration, signing, deployment, or publication. Do not broaden scope to resolve a blocker; return it to the coordinator.

## Procedure

1. Trace recording, model load/prewarm, streaming or batch finalization, sanitization, vocabulary correction, and cleanup for the affected backend.
2. Identify actor/audio-thread transitions, early-stop/cancellation behavior, sample assumptions, and missing-model fallbacks.
3. Distinguish inference-time no-download guards from separately scheduled auxiliary installation. Check selected language/script and Parakeet version/bundling consistency when relevant.
4. Propose a minimal change with explicit uncertainties and regression checks, using synthetic fixtures where possible.
5. Separate measured latency/accuracy from hypotheses; hand implementation scope to the implementer and execution checks to the tester.

## Acceptance checks

Recommendations cite source paths and test evidence, including `ParakeetVocabularyBoosterTests` when changing booster behavior. Specify a focused `swift test --filter` check and broader tests as applicable; label unexecuted commands. No accuracy/latency claim without measured inputs, backend/model configuration, and results.

## Handoff format

- Outcome: completed / blocked / needs decision.
- Scope examined and files changed (or none).
- Findings or decisions: paths, evidence, rationale; reviewer findings classified blocking / revision-needed / non-blocking.
- Verification: exact commands and actual outcomes; checks not run and why.
- Risks, unresolved questions, and next owner.

## Coordinator responsibilities

Verify returned artifacts and execution evidence independently. Keep parallel write scopes disjoint and serialize shared-file work. Resolve conflicts before accepting changes. Never call self-review independent review; role Markdown does not register an agent or enforce tool permissions.

# Meander project guidance

Meander is a local-first macOS dictation app. Read [the context index](.agents/index.md) explicitly, then only the documents relevant to your task. Links do not automatically load context.

## Sources of truth

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing code. Larger features, new dependencies, and privacy/network changes need the contributor agreement described there.
- `Package.swift` defines MeanderKit (UI-independent core), MeanderMLX (local LLM cleanup), MeanderEval, and XCTest targets.
- `project.yml` defines the SwiftUI/AppKit app and its dependencies. It links both MeanderKit and MeanderMLX; older package comments suggesting MLX is not shipped are stale.
- Keep core logic in `Sources/MeanderKit`, platform UI/integration in `Sources/MeanderApp`, and MLX implementation in `Sources/MeanderMLX`.
- Match neighboring Swift conventions and preserve actor/audio-thread boundaries. Trace both streaming and batch paths before changing dictation behavior.

## Commands and verification

Run commands from the repository root. See [workflows](.agents/workflows.md) for prerequisites, side effects, and exact app-build commands.

- `swift test`: core XCTest suite; observed in CI, not locally executed during bootstrap.
- `xcodegen generate`: generates the Xcode project; edits belong in `project.yml`, not generated files.
- App builds require full Xcode and XcodeGen. CI notes dependency manifests require Swift tools 6.1+; the package's 5.9 declaration is not the entire dependency toolchain requirement.
- `swift run meander-eval`: separate quality evaluation, not a substitute for unit tests; overwrites tracked reports and may require MLX/Metal support.
- Bootstrap inspection found Swift 6.2.1, but only Command Line Tools selected and no XcodeGen on PATH. Recheck the environment; do not claim a local build passed.

## Boundaries

- Preserve local-first behavior: cloud cleanup is explicit opt-in and sends text, not microphone audio. Do not add telemetry/network behavior without agreement.
- Preserve text meaning, language/script, names and numbers; inspect the applicable provider contract rather than assuming all providers use one prompt.
- Protect clipboard contents, focused-app targeting, Accessibility boundaries, transcript history, learned vocabulary, and diagnostic recordings. Never read user secrets or private runtime data to inspect the codebase.
- Do not enable diagnostic audio capture, download models, grant permissions, launch/paste into apps, install tools, sign, deploy, or publish merely to validate a change. Obtain task-specific authorization for side effects.
- Do not run `scripts/dev-run.sh` as a routine check: it replaces `/Applications/Meander.app` and relaunches it.
- Do not commit generated Xcode projects, generated plist/entitlements, build outputs, model weights, or credentials; see `.gitignore`.
- No commits, pushes, global configuration changes, or unrelated refactoring without authorization.

## Roles and handoffs

Select a role from the [index](.agents/index.md): implementer for bounded changes, reviewer for independent read-only review, tester for reproduction/verification, speech-pipeline specialist for domain analysis.

These Markdown contracts are not registered agents or permission enforcement. For delegation, supply the role text, concrete task, context paths, allowed write scope, acceptance checks, and return format. Use disjoint write scopes; serialize shared-file edits. The coordinator checks returned artifacts. If review is sequential self-review, disclose that it was not independent.

## Definition of done

The scoped change preserves existing guidance, includes relevant regression coverage, has its full diff reviewed, and reports exact checks and actual results. Separate passed, failed, blocked, and not-run checks. UI changes need appropriate visual/manual evidence; model quality claims need actual evaluations, not prompt-presence tests. Never conceal unavailable Xcode, permissions, model assets, or unrun checks behind a success claim.

# Workflows and verification

All commands below run from the repository root. Prefer [CONTRIBUTING.md](../CONTRIBUTING.md) and [README.md](../README.md) for contributor onboarding rather than duplicating installation instructions.

## Prerequisites and status

The app targets macOS 14+. Full Xcode is required, not just Command Line Tools. [CI](../.github/workflows/ci.yml) uses macos-26 and latest-stable Xcode, noting MLX manifests need Swift tools 6.1+. XcodeGen generates the app project from [project.yml](../project.yml).

Bootstrap inspection executed `swift --version`, `xcodebuild -version`, and `command -v xcodegen`: Swift 6.2.1 was available; xcodebuild failed because Command Line Tools was selected; XcodeGen was not on PATH. This is an inspection snapshot, not a permanent environment assumption. No tests, app builds, model evaluations, or release commands were run during bootstrap.

## Unit tests

`swift test`

Observed in CI and contributor documentation, not locally verified during bootstrap. Runs MeanderKitTests; it does not launch or exercise the app's OS integration. SwiftPM can resolve/download dependencies and write build/cache files. Use `swift test --filter ParakeetVocabularyBoosterTests` for that regression group when relevant, followed by the broader suite as appropriate; the filtered command is an unexecuted suggested check.

## Unsigned app build

Observed in CI; not locally verified:

```sh
xcodegen generate
xcodebuild -project Meander.xcodeproj -scheme Meander   -configuration Debug CODE_SIGNING_ALLOWED=NO   -skipPackagePluginValidation -skipMacroValidation build
```

Requires full Xcode, XcodeGen, and dependency resolution. Writes generated project/plist/entitlements and build artifacts. The skip flags mirror CI and bypass plugin/macro validation; they are not a blanket trust or permissions grant. Do not install tools or alter global trust settings just to make a check pass. Plain SwiftPM compilation is not proof the MLX Metal resources or app bundle work.

## Cleanup quality evaluation

`swift run meander-eval`

Documented by Package.swift and [the runner](../Sources/MeanderEval/main.swift); not locally verified. Always includes raw and deterministic providers; MLX providers are added when a config.json file exists in the corresponding local model directory. Missing weights do not prove MLX runtime/build readiness: the executable still imports MeanderMLX and may require suitable Metal resources/toolchain.

The runner overwrites tracked `eval/report.md` and `eval/report.html`. Obtain approval for report updates; never silently restore or overwrite existing user changes. Record exactly which providers ran and which were skipped. Model downloads via `scripts/fetch-eval-model.sh` are separate, opt-in work. Unit tests of prompt text cannot support quality/latency claims.

## Manual app checks

Only with authorization to launch the app and use microphone/Accessibility/clipboard:

- Verify press/release, early release during streaming startup, empty input, cancellation/error recovery, and model-unavailable behavior for the affected backend.
- Check destination formatting, language/script preservation, vocabulary corrections, and clipboard restoration in an approved disposable text field.
- Check onboarding/permissions and UI evidence when those paths change. Do not grant permissions or paste into unrelated user documents.
- Keep diagnostic WAV capture disabled; do not read private transcripts or diagnostic files without permission.

These are proposed manual checks, not checks completed during bootstrap.

## Side-effectful scripts and release boundaries

| Source | Side effects / boundary |
| --- | --- |
| [bootstrap.sh](../scripts/bootstrap.sh) | May install XcodeGen; generates project and resolves dependencies |
| [setup-dev-cert.sh](../scripts/setup-dev-cert.sh) | Creates a signing identity; requires explicit approval, not routine validation |
| [dev-run.sh](../scripts/dev-run.sh) | Builds/signs, stops Meander, replaces `/Applications/Meander.app`, launches it |
| [fetch-eval-model.sh](../scripts/fetch-eval-model.sh) | Downloads model assets; not part of default documentation validation |
| [release.sh](../scripts/release.sh) | Archives, bundles cached models, signs and creates DMG; may notarize with configured credentials |
| [release workflow](../.github/workflows/release.yml) | Tag/manual-triggered downloads, packaging and GitHub Release publication |

Do not execute these scripts, push release tags, or trigger publication to verify documentation. Parakeet bundle version must agree with ModelManager; release configuration currently bundles v3. Keep generated artifacts and model weights out of commits per `.gitignore`.

## Documentation checks

Validate every local Markdown link relative to its containing file, referenced repository paths, role-contract sections, unique roles, and index coverage. Run `git diff --check` and inspect the full scoped content, including new untracked files (ordinary git diff omits them). Confirm no unrelated changes. Independent review should check claims against source, not just this document.

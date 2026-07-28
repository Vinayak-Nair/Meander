# Drift

**Local-first voice dictation for macOS. A free, open-source alternative to Wispr Flow.**

Hold a key, speak, and Drift types cleaned-up text into whatever app you're using. English transcription runs entirely on your Mac with [FluidAudio](https://github.com/FluidInference/FluidAudio); [WhisperKit](https://github.com/argmaxinc/WhisperKit) adds fully on-device dictation in Indian and international languages.

- 🎙️ **Push-to-talk anywhere**, system-wide
- 🔒 **Private by default**: on-device transcription and on-device cleanup, no account, no API key
- 🇬🇧 **English-first right now**, using FluidAudio's local Parakeet model for fast dictation
- 🌐 **Multilingual optional**, via WhisperKit for Indian and international languages, all on-device
- 🧹 **Smart cleanup**: removes filler words and fixes punctuation instantly on-device; optional cloud or local LLM cleanup for higher quality
- 🪶 **Native and lightweight**: a Swift menu-bar app, no Electron
- 🆓 **MIT licensed**

## Install (for users)

1. Download `Drift.dmg` from the [Releases](https://github.com/Vinayak-Nair/Drift/releases/latest) page.
2. Open it and drag **Drift** to your Applications folder.
3. Open Drift. A small waveform icon appears in your menu bar.
4. Follow the one-time setup: grant **Microphone** and **Accessibility**, and let the speech model download.
5. Click into any text field, **hold Right Option (⌥)**, speak, and release.

No Homebrew, no Terminal, no separate downloads. Everything is handled inside the app.

> Accessibility is required so Drift can detect the push-to-talk key and type into other apps. You can review this anytime in the menu under **Setup & Permissions**.

## Using Drift

- **Dictate:** hold Right Option (⌥), speak, release. The text is inserted at your cursor.
- **Change language:** menu bar ▸ Language, or Settings.
- **Pick a cleanup style:** Settings ▸ Cleanup.
- Sounds confirm start, success, and empty results.

## Languages

Drift currently defaults to **FluidAudio English** using Parakeet TDT v3.

In Settings you can switch the dictation model to **WhisperKit Multilingual**, which runs fully on-device (no Python, no account, no gated downloads). It covers:

- **Indian languages:** Hindi, Bengali, Tamil, Telugu, Kannada, Malayalam, Marathi, Gujarati, Punjabi, Urdu, Nepali, Sanskrit, Sindhi, and Assamese.
- **International languages:** Spanish, French, German, Italian, Portuguese, Dutch, Polish, Turkish, Chinese, Japanese, Korean, Arabic, Russian, and many more.
- **Auto-detect**, which lets Whisper identify the spoken language on its own.

Indian-language and low-resource accuracy is best with the Large model; smaller Whisper variants trade accuracy for speed. The model downloads once, then runs locally with no network.

## Cleanup options

| Provider | Where it runs | Setup | Best for |
|----------|---------------|-------|----------|
| **On-device** (default) | Your Mac | None | Instant, private formatting |
| **Cloud (OpenAI-compatible)** | A hosted API | Base URL + key | Highest quality; works with OpenAI, Groq, **Sarvam**, LM Studio |
| **Local LLM (Ollama)** | Your Mac | Run Ollama | Private LLM cleanup, advanced |
| **Raw** | n/a | None | Insert the transcription verbatim |

The cleanup layer is model-agnostic, so adding an Indian-language model such as Sarvam is just a base URL and model name in Settings.

## Privacy

By default, audio is transcribed on-device and cleaned on-device. Nothing is uploaded. If you opt into a cloud cleanup provider, only the transcribed text (not your audio) is sent to the endpoint you configure.

---

## Building from source (for contributors)

### Requirements

- macOS 14+
- **Full Xcode 16+** (Command Line Tools alone are not enough: WhisperKit and the app build need Xcode). If your internal disk is low, Xcode and its build data can live on an external APFS SSD.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the bootstrap script installs it via Homebrew)

### Steps

```bash
git clone <repo-url> Drift && cd Drift
./scripts/bootstrap.sh     # installs XcodeGen, generates the project, resolves deps
open Drift.xcodeproj       # then press Run (Cmd+R)
```

Run the core unit tests with:

```bash
swift test
```

### Push-to-talk permission across rebuilds

The global push-to-talk hotkey needs macOS **Accessibility** permission, which is
tied to the app's code signature. Default ad-hoc signing changes the signature on
every rebuild, so the grant is invalidated each time and the hotkey "stops
working." To make it stick, sign local builds with a stable self-signed identity:

```bash
./scripts/setup-dev-cert.sh   # one-time: creates a "Drift Dev" code-signing cert
./scripts/dev-run.sh          # build + sign + relaunch (use this instead of Cmd+R)
```

Grant Accessibility to Drift once after the first signed build; it then persists
across all future `dev-run.sh` rebuilds (the signature, hence the permission, no
longer changes). No Apple Developer account required.

### Project layout

`DriftKit` is a pure, testable Swift package (no UI). The macOS app in `Sources/DriftApp` is generated into an Xcode project by XcodeGen from `project.yml`.

| Area | Path | Responsibility |
|------|------|----------------|
| Core | `Sources/DriftKit/Pipeline.swift` | record ▸ transcribe ▸ clean orchestration |
| STT | `Sources/DriftKit/Transcription/` | `Transcriber` protocol, FluidAudio + WhisperKit impls, model download |
| Cleanup | `Sources/DriftKit/Cleanup/` | `CleanupProvider` protocol + deterministic / OpenAI-compatible / Ollama |
| Audio | `Sources/DriftKit/Audio/Recorder.swift` | mic capture to 16 kHz samples |
| App | `Sources/DriftApp/` | menu bar, onboarding, settings, hotkey, paste |

### Releasing

```bash
DEV_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="drift-notary" \
./scripts/release.sh
```

Produces a signed, notarized `build/Drift.dmg`. Notarization needs a paid Apple Developer account; without one the script still builds an ad-hoc-signed DMG for local use.

The release bundles two models inside the app so first run works with no download: the default English speech model (Parakeet v3, ~470 MB) and the on-device cleanup model (Qwen2.5 0.5B 4-bit, ~276 MB). Parakeet is copied from your local model cache (`~/Library/Application Support/Drift/models/FluidAudio/parakeet-tdt-0.6b-v3`), so run the app once to populate it or set `MODEL_CACHE` to a directory containing that folder. The cleanup model comes from `eval/models/qwen2.5-0.5b-4bit` (run `scripts/fetch-eval-model.sh`) or `MLX_MODEL_CACHE`. Either model missing means the DMG ships without it: dictation falls back to downloading on first run, and the on-device LLM cleanup option falls back to the deterministic rules. Neither model is committed to git. Multilingual Whisper models download on demand.

### Automated releases (CI)

Pushing a tag that starts with `v` builds and publishes a GitHub Release automatically — no local build needed (see [`.github/workflows/release.yml`](.github/workflows/release.yml)):

```bash
git tag v0.2.0
git push origin v0.2.0
```

On a macOS GitHub runner the workflow archives the app, downloads and bundles the Parakeet v3 model, builds an ad-hoc-signed `Drift.dmg`, and attaches it to a `v0.2.0` release marked **latest** — so the landing page's download link always resolves to the newest build. It sets the app's version from the tag and needs no Apple Developer account. To ship a notarized build instead, add `DEV_ID` / notary credentials as repository secrets and wire them into the build step (the script already honors `DEV_ID` and `NOTARY_PROFILE`). You can also trigger it manually from **Actions ▸ Release ▸ Run workflow**.

## Roadmap

- [ ] App icon and a polished menu-bar status UI
- [ ] Move the API key to the Keychain
- [ ] Live partial-transcription overlay
- [x] Custom vocabulary and per-app formatting profiles
- [ ] Sarvam and other Indian-language cleanup presets
- [ ] Configurable push-to-talk key in Settings

## Credits

Built on [FluidAudio](https://github.com/FluidInference/FluidAudio) by FluidInference and [WhisperKit](https://github.com/argmaxinc/WhisperKit) by Argmax. Inspired by Wispr Flow.

## License

MIT, see [LICENSE](LICENSE).

# Contributing to Meander

Thanks for helping out. Meander is a small project, so the process is light: fork, branch, open a pull request.

## Before you start

- **Small fixes** (typos, obvious bugs, small cleanups): just open a pull request.
- **Anything bigger** (new features, new dependencies, changes to the transcription or cleanup pipeline, UI redesigns): open an issue first and describe what you want to do. A quick agreement up front saves you from writing code that won't be merged.
- Looking for something to work on? Check issues labeled [`good first issue`](https://github.com/Vinayak-Nair/Meander/labels/good%20first%20issue) or [`help wanted`](https://github.com/Vinayak-Nair/Meander/labels/help%20wanted). Comment on the issue so others know you've picked it up.

## Setting up

You need macOS 14+, **full Xcode 16+** (Command Line Tools alone won't build the app), and Homebrew.

```bash
git clone https://github.com/<your-username>/Meander.git && cd Meander
./scripts/bootstrap.sh        # installs XcodeGen, generates the project, resolves deps
./scripts/setup-dev-cert.sh   # one-time: stable local signing identity
./scripts/dev-run.sh          # build, sign, and relaunch the app
```

Use `dev-run.sh` instead of Cmd+R in Xcode. Push-to-talk needs Accessibility permission, which macOS ties to the app's signature. With the stable dev certificate you grant it once and it survives rebuilds; with plain Xcode builds it breaks after every rebuild.

`Meander.xcodeproj` is generated from `project.yml` and is not committed. If you add files or change build settings, edit `project.yml` and run `xcodegen generate`.

## Where things live

| Area | Path |
|------|------|
| Core pipeline (record, transcribe, clean) | `Sources/MeanderKit/Pipeline.swift` |
| Speech-to-text backends | `Sources/MeanderKit/Transcription/` |
| Text cleanup providers | `Sources/MeanderKit/Cleanup/` |
| Audio capture | `Sources/MeanderKit/Audio/` |
| macOS app (menu bar, settings, hotkey, paste) | `Sources/MeanderApp/` |
| Unit tests | `Tests/MeanderKitTests/` |

`MeanderKit` is a plain Swift package with no UI, so most logic can be tested without launching the app. Prefer putting new logic there and keeping `MeanderApp` thin.

## Tests

```bash
swift test
```

New logic in `MeanderKit` should come with tests. Bug fixes should include a test that fails without the fix when that's practical.

CI runs `swift test` and a full app build on every pull request. Both must pass before merging. If you're a first-time contributor, a maintainer has to approve the CI run before it starts; that's a GitHub default, not a sign anything is wrong.

## Pull requests

- Branch from the latest `main` and keep each pull request focused on one change.
- Match the style of the surrounding code: naming, comment density, file layout.
- Describe what changed and why. For UI changes, include a screenshot or short recording.
- Don't commit generated files, build output, or model weights (see `.gitignore`).
- Don't add new dependencies without discussing it in an issue first.

## Privacy

Meander is private by default: audio never leaves the Mac unless the user explicitly opts into a cloud provider, and even then only text is sent. Changes that add network calls, telemetry, or send user data anywhere need to be discussed in an issue first and must be opt-in.

## Reporting bugs

Use the bug report template when opening an issue. Your macOS version, Mac model (Apple silicon or Intel), the dictation model, and the cleanup provider you were using make bugs much easier to track down.

## Security issues

Please don't open a public issue for security problems. Use GitHub's [private vulnerability reporting](https://github.com/Vinayak-Nair/Meander/security/advisories/new) instead.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).

import AppKit
import MeanderKit

/// Inline autocomplete: after a typing pause in an allowed app, asks the on-device
/// model for a short continuation and shows it as ghost text at the caret. Tab
/// accepts it all, Option+Right takes one word. Everything is local: the typed
/// context is read through Accessibility, handed to the on-device model, and
/// dropped. Nothing is logged or stored.
@MainActor
final class AutocompleteController {
    static let shared = AutocompleteController()

    private let tap = SuggestionKeyTap()
    private let overlay = SuggestionOverlay()
    private var debounceTask: Task<Void, Never>?
    private var running = false
    private var suggestion: String?

    private let debounce: UInt64 = 350_000_000
    private let minimumPrefix = 8

    private init() {
        tap.onTyping = { [weak self] in Task { @MainActor in self?.typed() } }
        tap.onDismiss = { [weak self] in Task { @MainActor in self?.dismiss() } }
        tap.onAcceptAll = { [weak self] in Task { @MainActor in self?.accept(wordOnly: false) } }
        tap.onAcceptWord = { [weak self] in Task { @MainActor in self?.accept(wordOnly: true) } }
    }

    /// Starts or stops according to the current setting. Safe to call repeatedly.
    func apply() {
        let enabled = Settings.shared.autocompleteEnabled
        if enabled, !running {
            running = true
            tap.start()
        } else if !enabled, running {
            running = false
            tap.stop()
            dismiss()
        }
    }

    private func typed() {
        dismiss()
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounce ?? 0)
            guard !Task.isCancelled else { return }
            await self?.suggest()
        }
    }

    private func dismiss() {
        suggestion = nil
        tap.suggestionVisible = false
        overlay.hide()
    }

    private func provider() -> CompletionProvider? {
        guard let build = CleanupFactory.externalBuilders["mlx"] else { return nil }
        return build(Settings.shared, .standard, nil) as? CompletionProvider
    }

    private func suggest() async {
        guard running, case .idle = AppState.shared.status,
              let provider = provider(),
              let context = FocusedTextReader.read(),
              Settings.shared.autocompleteApps.contains(context.bundleID),
              context.beforeCaret.count >= minimumPrefix,
              context.caretRect != nil
        else { return }

        let completion: String
        do { completion = try await provider.complete(prefix: context.beforeCaret) }
        catch { return }
        guard !Task.isCancelled, !completion.isEmpty else { return }

        // The user may have kept typing or switched fields while the model ran.
        guard let now = FocusedTextReader.read(),
              now.bundleID == context.bundleID,
              now.beforeCaret == context.beforeCaret,
              let rect = now.caretRect
        else { return }

        show(completion, at: rect)
    }

    private func show(_ text: String, at rect: CGRect) {
        suggestion = text
        overlay.show(text, after: rect)
        tap.suggestionVisible = true
    }

    private func accept(wordOnly: Bool) {
        guard let text = suggestion, !text.isEmpty else { return }
        var insert = text
        var remainder = ""
        if wordOnly, let match = text.range(of: #"^\s*\S+"#, options: .regularExpression) {
            insert = String(text[match])
            remainder = String(text[match.upperBound...])
        }
        dismiss()
        Paster.paste(insert)

        // After taking one word, offer the rest again once the paste has landed.
        guard !remainder.isEmpty else { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self,
                  let now = FocusedTextReader.read(), let rect = now.caretRect else { return }
            self.show(remainder, at: rect)
        }
    }
}

import AppKit
import ApplicationServices
import MeanderKit
import os

/// Wispr Flow-style dictionary learning. After a dictation is pasted, this
/// snapshots the destination text field (via Accessibility) and re-reads it a
/// few times over the next ~70 seconds. When the user fixes a misheard word in
/// place, the diff is handed to `DictionaryLearner` and the correction becomes
/// a vocabulary entry.
///
/// Fails quietly everywhere: secure fields, apps with poor AX support, or a
/// field that no longer contains the pasted text simply learn nothing. Each
/// step appends a line (lengths only, no content) to /tmp/meander-correction.log
/// for debugging.
@MainActor
final class CorrectionWatcher {
    private static let log = Logger(subsystem: "Meander", category: "CorrectionWatcher")

    /// Seconds after paste at which the baseline snapshot is attempted. Multiple
    /// tries because some apps commit a synthesized Cmd+V slowly, and Chromium
    /// builds its accessibility tree lazily after we request it.
    private static let snapshotTimes: [Double] = [0.8, 2.5, 5]
    /// How often the field is re-read, and for how long. Reading one AX string
    /// value is sub-millisecond, so a tight cadence is cheap and makes the
    /// learned-word toast appear a beat after the user finishes a correction.
    private static let pollInterval = 1.0
    private static let watchWindow = 75.0
    /// Consecutive unchanged reads required before an edit is treated as
    /// finished. See the read loop for why one is not enough.
    private static let stableTicksBeforeLearning = 2

    private var task: Task<Void, Never>?

    /// Starts watching for corrections to `pasted`. Cancels any prior watch:
    /// only the latest dictation is tracked.
    func watch(
        pasted: String,
        vocabulary: @escaping () -> [String],
        onLearn: @escaping ([DictionaryLearner.LearnedTerm]) -> Void
    ) {
        cancel()
        task = Task {
            let target = NSWorkspace.shared.frontmostApplication
            Self.trace("watch started: pasted \(pasted.count) chars into \(target?.bundleIdentifier ?? "unknown app")")

            // Electron and Chromium only build their accessibility trees once an
            // assistive client announces itself. Electron listens for
            // AXManualAccessibility, Chromium browsers for AXEnhancedUserInterface
            // (VoiceOver's flag). Return codes are unreliable — Chrome answers
            // "not implemented" yet still enables — so both are set blind.
            // Native apps ignore them.
            if let target {
                let appElement = AXUIElementCreateApplication(target.processIdentifier)
                AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }

            var elapsed = 0.0
            var element: AXUIElement?
            var baseline: String?
            for time in Self.snapshotTimes {
                try? await Task.sleep(for: .seconds(time - elapsed))
                elapsed = time
                guard !Task.isCancelled else { return }
                let roots = Self.snapshotRoots(target: target)
                guard !roots.isEmpty else {
                    Self.trace("snapshot \(time)s: no focused element or window to search")
                    continue
                }
                for root in roots {
                    if let (found, value) = Self.resolveTextElement(from: root, containing: pasted) {
                        element = found
                        baseline = value
                        break
                    }
                }
                if element != nil { break }
                Self.trace("snapshot \(time)s: paste not found under \(roots.count) root(s)")
            }
            guard let element, let baseline else {
                Self.trace("giving up: destination field unreadable or paste not found")
                return
            }
            Self.trace("watching field (\(baseline.count) chars)")

            // Web editors report their placeholder as the value once the field
            // empties (e.g. "Ask anything" after sending a chat message); noting
            // it now lets the polls recognize a cleared field instead of
            // "learning" the placeholder as a correction.
            let placeholder = Self.stringValue(of: element, attribute: kAXPlaceholderValueAttribute)
            let pastedTokens = Set(pasted.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })

            // Tight polling with a stability debounce: an edit is processed one
            // tick after the field stops changing, so the toast shows ~2s after
            // the user finishes typing a fix. Every diff runs against the
            // ORIGINAL baseline, not the previous tick, so a half-finished edit
            // can't eat the correction. Re-learning is prevented both by
            // `processed` and because `vocabulary()` re-reads settings.
            var previous = baseline
            var processed = baseline
            var stableTicks = 0
            while elapsed < Self.watchWindow {
                try? await Task.sleep(for: .seconds(Self.pollInterval))
                elapsed += Self.pollInterval
                guard !Task.isCancelled else { return }
                guard let current = Self.stringValue(of: element) else {
                    Self.trace("poll \(Int(elapsed))s: field no longer readable, stopping")
                    return
                }
                if Self.looksCleared(current: current, baseline: baseline, placeholder: placeholder, pastedTokens: pastedTokens) {
                    Self.trace("poll \(Int(elapsed))s: field cleared or replaced (message sent?), stopping")
                    return
                }
                stableTicks = current == previous ? stableTicks + 1 : 0
                defer { previous = current }
                guard current != processed else { continue } // nothing new
                // A single quiet tick is not enough: people pause mid-sentence, so
                // one second of stillness catches them part-way through typing and
                // hands the learner a half-written phrase ("fil o" on the way to
                // "file or"). Waiting for a second quiet tick costs a beat on the
                // toast and keeps typing-in-progress out of the dictionary.
                guard stableTicks >= Self.stableTicksBeforeLearning else { continue }

                let terms = DictionaryLearner.newTerms(
                    pasted: pasted, before: baseline, after: current,
                    vocabulary: vocabulary()
                )
                Self.trace("poll \(Int(elapsed))s: field changed (\(baseline.count) -> \(current.count) chars), learned \(terms.count) term(s)")
                if !terms.isEmpty { onLearn(terms) }
                processed = current
            }
            Self.trace("watch window ended")
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    // MARK: Accessibility

    /// Places to look for the pasted text, most specific first: the system-wide
    /// focused element, the target app's own focused element, then its focused
    /// window. Chrome often reports no focused element at all while its web
    /// content is still reachable by walking the window.
    private static func snapshotRoots(target: NSRunningApplication?) -> [AXUIElement] {
        var roots: [AXUIElement] = []
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let focused {
            roots.append(focused as! AXUIElement)
        }
        if let target {
            let appElement = AXUIElementCreateApplication(target.processIdentifier)
            var appFocused: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &appFocused) == .success,
               let appFocused {
                roots.append(appFocused as! AXUIElement)
            }
            var window: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
               let window {
                roots.append(window as! AXUIElement)
            }
        }
        return roots
    }

    /// The element under `root` whose text contains the pasted transcript.
    /// Containment is whitespace-insensitive because web editors normalize
    /// spacing. Breadth-first and bounded; the limits fit real web trees
    /// (Chrome exposes composer fields ~25 levels deep, under a thousand nodes).
    private static func resolveTextElement(
        from root: AXUIElement, containing pasted: String
    ) -> (AXUIElement, String)? {
        let needle = normalizeWhitespace(pasted)
        guard !needle.isEmpty else { return nil }
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count {
            let (element, depth) = queue[index]
            index += 1
            if let value = stringValue(of: element), normalizeWhitespace(value).contains(needle) {
                return (element, value)
            }
            if depth < 30, queue.count < 4000 {
                for child in children(of: element) { queue.append((child, depth + 1)) }
            }
        }
        return nil
    }

    private static func stringValue(of element: AXUIElement, attribute: String = kAXValueAttribute) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element, attribute as CFString, &value
        )
        guard result == .success else { return nil }
        return value as? String
    }

    /// Whether the field no longer holds the dictation at all: emptied, showing
    /// its placeholder, or wholesale-replaced (message sent, draft discarded).
    /// Diffing those states against the baseline would "learn" garbage like the
    /// placeholder text, so the watch ends instead.
    private static func looksCleared(
        current: String, baseline: String, placeholder: String?, pastedTokens: Set<String>
    ) -> Bool {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if let placeholder, !placeholder.isEmpty,
           normalizeWhitespace(trimmed) == normalizeWhitespace(placeholder) {
            return true
        }
        // Wholesale replacement: most dictated words gone and the field shrank
        // by half or more. A real correction keeps the surrounding words.
        guard !pastedTokens.isEmpty else { return false }
        let currentTokens = Set(current.split(whereSeparator: \.isWhitespace).map { $0.lowercased() })
        let overlap = Double(pastedTokens.intersection(currentTokens).count) / Double(pastedTokens.count)
        return overlap < 0.5 && current.count < baseline.count / 2
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func normalizeWhitespace(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Tracing

    private static let traceURL = URL(fileURLWithPath: "/tmp/meander-correction.log")
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Appends a diagnostic line (no transcript content, lengths only) to
    /// /tmp/meander-correction.log and mirrors it to the unified log.
    private static func trace(_ message: String) {
        log.notice("\(message, privacy: .public)")
        let line = "[\(timeFormatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: traceURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: traceURL)
        }
    }
}

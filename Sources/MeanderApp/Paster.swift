import AppKit

/// Inserts text into the currently focused app by putting it on the pasteboard
/// and synthesizing Cmd+V, then restoring the previous clipboard.
enum Paster {
    /// How long to wait after Cmd+V before putting the old clipboard back.
    ///
    /// Posting the key event does not paste anything: the target app reads the
    /// pasteboard whenever it gets around to handling the event. Restoring too
    /// early makes it paste the *previous* clipboard instead of the dictated
    /// text. Electron and browser-based apps regularly take well over half a
    /// second, so leave a wide margin.
    private static let restoreDelay: TimeInterval = 1.5

    static func paste(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        let previous = snapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendCmdV()
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                restore(previous, to: pasteboard, ifStillAt: ourChangeCount)
            }
        }
    }

    /// Returns the text currently selected in the frontmost app by briefly sending
    /// Cmd+C, then puts the previous clipboard back. Empty when nothing is selected.
    @MainActor
    static func copySelection() async -> String {
        let pasteboard = NSPasteboard.general
        let previous = snapshot(pasteboard)
        pasteboard.clearContents()
        let cleared = pasteboard.changeCount
        sendKey(8) // 'c'
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 30_000_000)
            if pasteboard.changeCount != cleared { break }
        }
        let selection = pasteboard.string(forType: .string) ?? ""
        let after = pasteboard.changeCount
        restore(previous, to: pasteboard, ifStillAt: after)
        return selection
    }

    /// Every representation of every item, so images and rich text survive a
    /// dictation instead of being flattened to plain text or dropped.
    private static func snapshot(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type] = data
                }
            }
            return representations
        }
        .filter { !$0.isEmpty }
    }

    private static func restore(
        _ items: [[NSPasteboard.PasteboardType: Data]],
        to pasteboard: NSPasteboard,
        ifStillAt changeCount: Int
    ) {
        // Something else claimed the clipboard while we were pasting: the user
        // copied, or a second dictation landed. Whatever is there now wins.
        guard pasteboard.changeCount == changeCount else { return }
        guard !items.isEmpty else { return }

        pasteboard.clearContents()
        pasteboard.writeObjects(items.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        })
    }

    private static func sendCmdV() { sendKey(9) } // 'v'

    private static func sendKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

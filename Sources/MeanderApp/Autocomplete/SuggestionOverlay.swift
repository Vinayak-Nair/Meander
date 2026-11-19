import AppKit

/// A click-through, non-activating panel that draws the suggestion as gray ghost
/// text right after the caret. It never takes focus from the app being typed in.
@MainActor
final class SuggestionOverlay {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        label.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        panel.contentView = label
    }

    /// Shows `text` starting at the right edge of `caretRect` (the previous
    /// character's rect, so the ghost text lines up with what was typed).
    func show(_ text: String, after caretRect: CGRect) {
        label.font = NSFont.systemFont(ofSize: max(11, caretRect.height * 0.78))
        label.stringValue = text
        label.sizeToFit()
        let size = NSSize(width: min(label.frame.width + 2, 520), height: caretRect.height)
        let origin = NSPoint(x: caretRect.maxX, y: caretRect.minY)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        label.frame = NSRect(x: 0, y: (size.height - label.frame.height) / 2, width: size.width, height: label.frame.height)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

import AppKit
import ApplicationServices

/// What the focused text field looks like right now, read through Accessibility.
struct FocusedTextContext {
    let bundleID: String
    /// Text before the caret, at most `maxContext` characters.
    let beforeCaret: String
    /// Rect of the character before the caret in AppKit screen coordinates, when
    /// the app reports one. Used to place the ghost text.
    let caretRect: CGRect?
}

enum FocusedTextReader {
    private static let maxContext = 600
    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]

    /// nil when there is no usable text field: secure fields, a selection, a caret
    /// in the middle of existing text, or an app that exposes no text.
    static func read() -> FocusedTextContext? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement

        guard let role = string(element, kAXRoleAttribute), textRoles.contains(role) else { return nil }
        if string(element, kAXSubroleAttribute) == "AXSecureTextField" { return nil }

        guard let value = string(element, kAXValueAttribute) else { return nil }
        guard let range = selectedRange(element), range.length == 0 else { return nil }

        let text = value as NSString
        let caret = min(max(range.location, 0), text.length)

        // Only suggest at the end of a line: text after the caret means the user is
        // editing in the middle, where a continuation would be wrong.
        let after = text.substring(from: caret)
        let restOfLine = after.prefix(while: { $0 != "\n" })
        if !restOfLine.trimmingCharacters(in: .whitespaces).isEmpty { return nil }

        let start = max(0, caret - maxContext)
        let before = text.substring(with: NSRange(location: start, length: caret - start))

        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return nil }

        return FocusedTextContext(
            bundleID: bundleID,
            beforeCaret: before,
            caretRect: caretRect(element, caret: caret)
        )
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(ref as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func caretRect(_ element: AXUIElement, caret: Int) -> CGRect? {
        guard caret > 0 else { return nil }
        var range = CFRange(location: caret - 1, length: 1)
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var ref: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &ref
        ) == .success, let ref, CFGetTypeID(ref) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(ref as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }
        // Accessibility uses a top-left origin on the primary display; AppKit is bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

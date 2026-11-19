import AppKit

/// Session-wide key and mouse tap for autocomplete. It is an *active* tap so it
/// can swallow Tab and Option+Right, but only while a suggestion is on screen;
/// every other event passes through untouched. It runs on its own thread so a busy
/// main thread can never starve the system's key delivery.
final class SuggestionKeyTap {
    var onTyping: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onAcceptAll: () -> Void = {}
    var onAcceptWord: () -> Void = {}

    private let lock = NSLock()
    private var _visible = false
    /// Set by the controller whenever a suggestion appears or disappears.
    var suggestionVisible: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _visible }
        set { lock.lock(); _visible = newValue; lock.unlock() }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?
    private var runLoop: CFRunLoop?

    func start() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let this = Unmanaged<SuggestionKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = this.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return this.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }

        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: me
        ) else {
            NSLog("Meander: could not create autocomplete event tap (needs Accessibility permission)")
            return
        }
        self.tap = tap

        let thread = Thread { [weak self] in
            guard let self, let tap = self.tap else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.source = source
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.meander.autocomplete-tap"
        self.thread = thread
        thread.start()
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop {
            if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
            CFRunLoopStop(runLoop)
        }
        source = nil; tap = nil; runLoop = nil; thread = nil
        suggestionVisible = false
    }

    /// Returns true when the event was consumed.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .leftMouseDown || type == .rightMouseDown {
            DispatchQueue.main.async { [onDismiss] in onDismiss() }
            return false
        }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let visible = suggestionVisible

        if visible {
            let modifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            if keyCode == 48, modifiers.isEmpty { // Tab
                DispatchQueue.main.async { [onAcceptAll] in onAcceptAll() }
                return true
            }
            if keyCode == 124, modifiers == .maskAlternate { // Option+Right
                DispatchQueue.main.async { [onAcceptWord] in onAcceptWord() }
                return true
            }
            if keyCode == 53 { // Escape
                DispatchQueue.main.async { [onDismiss] in onDismiss() }
                return false
            }
        }

        // Ordinary typing (or editing) restarts the suggestion timer. Shortcuts
        // (Command/Control) are not typing and just clear the suggestion.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            DispatchQueue.main.async { [onDismiss] in onDismiss() }
        } else {
            DispatchQueue.main.async { [onTyping] in onTyping() }
        }
        return false
    }
}

import AppKit
import MeanderKit

/// Listens system-wide for the push-to-talk key and reports press/release.
/// Defaults to a modifier key (Right Option) but also supports normal keys.
/// Requires Accessibility permission for the event tap.
final class Hotkey {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    /// Quill key (second push-to-talk key), active only when enabled in Settings.
    var onQuillPress: () -> Void = {}
    var onQuillRelease: () -> Void = {}
    private var isQuillHeld = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var isHeld = false
    /// Toggle mode: whether a toggle-started recording is currently running.
    private var toggledOn = false

    /// Modifier keycodes mapped to their CGEventFlags bit.
    private static let modifierFlags: [Int: CGEventFlags] = [
        61: .maskAlternate, 58: .maskAlternate, // right/left option
        54: .maskCommand, 55: .maskCommand,     // right/left command
        60: .maskShift, 56: .maskShift,         // right/left shift
        62: .maskControl, 59: .maskControl,     // right/left control
    ]

    func start() {
        guard eventTap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let hotkey = Unmanaged<Hotkey>.fromOpaque(refcon).takeUnretainedValue()
            // macOS disables a tap if its run loop is starved past a timeout (or on
            // certain user input). Re-enable it so the hotkey keeps working instead
            // of dying after the first stall.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = hotkey.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            hotkey.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: selfPtr
        ) else {
            NSLog("Meander: could not create event tap (needs Accessibility permission)")
            return
        }
        eventTap = tap

        // Run the tap on a dedicated thread with its own run loop. If it shared the
        // main run loop, heavy main-thread work (model warm-up, transcription) would
        // starve the tap and macOS would disable it — the "works once, then dead"
        // symptom. A private thread keeps key delivery responsive regardless.
        let thread = Thread { [weak self] in
            guard let self, let tap = self.eventTap else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "com.meander.hotkey"
        tapThread = thread
        thread.start()
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let tapRunLoop {
            if let runLoopSource {
                CFRunLoopRemoveSource(tapRunLoop, runLoopSource, .commonModes)
            }
            CFRunLoopStop(tapRunLoop)
        }
        runLoopSource = nil
        eventTap = nil
        tapRunLoop = nil
        tapThread = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let ptt = Settings.shared.pttKeyCode
        if let held = Self.heldState(type: type, keyCode: keyCode, flags: event.flags, key: ptt) {
            setHeld(held)
        }
        let quill = Settings.shared.quillKeyCode
        if Settings.shared.quillEnabled, quill != ptt,
           let held = Self.heldState(type: type, keyCode: keyCode, flags: event.flags, key: quill) {
            setQuillHeld(held)
        }
    }

    /// nil when the event is not about `key`; otherwise whether it is now held.
    private static func heldState(type: CGEventType, keyCode: Int, flags: CGEventFlags, key: Int) -> Bool? {
        if let flag = modifierFlags[key] {
            guard type == .flagsChanged, keyCode == key else { return nil }
            return flags.contains(flag)
        }
        guard keyCode == key else { return nil }
        if type == .keyDown { return true }
        if type == .keyUp { return false }
        return nil
    }

    private func setQuillHeld(_ held: Bool) {
        guard held != isQuillHeld else { return }
        isQuillHeld = held
        DispatchQueue.main.async { [weak self] in
            if held { self?.onQuillPress() } else { self?.onQuillRelease() }
        }
    }

    private func setHeld(_ held: Bool) {
        guard held != isHeld else { return } // dedupe auto-repeat / flag noise
        isHeld = held
        if Settings.shared.pressToToggle {
            // Press once to start, press again to stop; releases are ignored.
            guard held else { return }
            toggledOn.toggle()
            let starting = toggledOn
            DispatchQueue.main.async { [weak self] in
                if starting { self?.onPress() } else { self?.onRelease() }
            }
            return
        }
        toggledOn = false
        DispatchQueue.main.async { [weak self] in
            if held { self?.onPress() } else { self?.onRelease() }
        }
    }
}

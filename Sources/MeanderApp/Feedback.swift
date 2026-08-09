import AppKit

/// Audible cues so the user knows what's happening without looking at the menu bar.
enum Feedback {
    static func start()   { NSSound(named: "Tink")?.play() }
    static func success() { NSSound(named: "Pop")?.play() }
    static func empty()   { NSSound(named: "Funk")?.play() }
}

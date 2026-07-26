import Foundation

/// What Drift knows about where dictated text is headed, captured the moment a
/// dictation starts. `windowTitle` is only read for browsers and terminals,
/// where the bundle id alone can't tell a Gmail tab from a Claude tab, or a
/// shell from a `claude` session.
public struct DictationTarget: Equatable, Sendable {
    public let bundleID: String?
    public let appName: String?
    public let windowTitle: String?

    public init(bundleID: String?, appName: String? = nil, windowTitle: String? = nil) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
    }
}

/// A destination recognized beyond the frontmost app's bundle id: a web app in
/// a browser tab (Gmail, Claude, ChatGPT) or an AI CLI running in a terminal
/// (claude, codex). It carries a pseudo bundle id ("web.gmail", "cli.codex") so
/// it can have its own built-in rule and per-app override, exactly like a real
/// app.
public struct Destination: Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Resolves the true destination of a dictation from the frontmost app and its
/// focused window title.
public enum DestinationDetector {
    /// Browsers: the focused tab's title decides who you're really talking to.
    public static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser", // Arc
        "company.thebrowser.dia",     // Dia
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
    ]

    /// Terminals: the window title usually names the running program, which is
    /// how an AI coding agent is told apart from a plain shell.
    public static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
    ]

    private struct Rule {
        let keyword: String
        let destination: Destination
    }

    /// Web apps recognized in a browser tab title (substring match on the
    /// lowercased title, first hit wins).
    private static let webRules: [Rule] = [
        .init(keyword: "gmail",      destination: .init(id: "web.gmail",      name: "Gmail")),
        .init(keyword: "claude",     destination: .init(id: "web.claude",     name: "Claude")),
        .init(keyword: "chatgpt",    destination: .init(id: "web.chatgpt",    name: "ChatGPT")),
        .init(keyword: "gemini",     destination: .init(id: "web.gemini",     name: "Gemini")),
        .init(keyword: "perplexity", destination: .init(id: "web.perplexity", name: "Perplexity")),
        .init(keyword: "copilot",    destination: .init(id: "web.copilot",    name: "Copilot")),
        .init(keyword: "outlook",    destination: .init(id: "web.outlook",    name: "Outlook")),
    ]

    /// AI CLIs recognized in a terminal window title. Whole-word match, so
    /// "claude" in "~/Drift (claude)" hits but "claudette.txt" doesn't.
    private static let cliRules: [Rule] = [
        .init(keyword: "claude", destination: .init(id: "cli.claude", name: "Claude Code")),
        .init(keyword: "codex",  destination: .init(id: "cli.codex",  name: "Codex")),
        .init(keyword: "gemini", destination: .init(id: "cli.gemini", name: "Gemini CLI")),
        .init(keyword: "aider",  destination: .init(id: "cli.aider",  name: "Aider")),
    ]

    /// Whether the app's focused window title is worth reading at all.
    public static func wantsWindowTitle(bundleID: String) -> Bool {
        browserBundleIDs.contains(bundleID) || terminalBundleIDs.contains(bundleID)
    }

    public static func detect(bundleID: String?, windowTitle: String?) -> Destination? {
        guard let bundleID, let title = windowTitle?.lowercased(), !title.isEmpty else { return nil }
        if browserBundleIDs.contains(bundleID) {
            return webRules.first { title.contains($0.keyword) }?.destination
        }
        if terminalBundleIDs.contains(bundleID) {
            let words = Set(title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            return cliRules.first { words.contains($0.keyword) }?.destination
        }
        return nil
    }

    /// The name handed to the LLM cleanup prompt so it knows who the user is
    /// talking to: the detected destination if any, else the plain app name.
    public static func displayName(for target: DictationTarget?) -> String? {
        guard let target else { return nil }
        return detect(bundleID: target.bundleID, windowTitle: target.windowTitle)?.name ?? target.appName
    }
}

import XCTest
@testable import MeanderKit

final class DestinationDetectorTests: XCTestCase {
    private func makeSettings() -> Settings {
        let suite = "meander-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Settings(defaults: defaults)
    }

    // MARK: Detection

    func testDetectsGmailTabInChrome() {
        let dest = DestinationDetector.detect(
            bundleID: "com.google.Chrome",
            windowTitle: "Inbox (12) - archana@gmail.com - Gmail"
        )
        XCTAssertEqual(dest?.id, "web.gmail")
        XCTAssertEqual(dest?.name, "Gmail")
    }

    func testDetectsClaudeTabInSafari() {
        let dest = DestinationDetector.detect(bundleID: "com.apple.Safari", windowTitle: "Claude")
        XCTAssertEqual(dest?.id, "web.claude")
    }

    func testDetectsChatGPTTab() {
        let dest = DestinationDetector.detect(bundleID: "com.google.Chrome", windowTitle: "ChatGPT - New chat")
        XCTAssertEqual(dest?.id, "web.chatgpt")
    }

    func testUnknownBrowserTabIsNotADestination() {
        XCTAssertNil(DestinationDetector.detect(bundleID: "com.google.Chrome", windowTitle: "Hacker News"))
    }

    func testDetectsClaudeSessionInTerminal() {
        let dest = DestinationDetector.detect(bundleID: "com.apple.Terminal", windowTitle: "claude — 80×24")
        XCTAssertEqual(dest?.id, "cli.claude")
        XCTAssertEqual(dest?.name, "Claude Code")
    }

    func testDetectsCodexSessionInITerm() {
        let dest = DestinationDetector.detect(bundleID: "com.googlecode.iterm2", windowTitle: "~/Meander (codex)")
        XCTAssertEqual(dest?.id, "cli.codex")
    }

    func testTerminalMatchRequiresWholeWord() {
        // "claudette" must not read as a claude session.
        XCTAssertNil(DestinationDetector.detect(bundleID: "com.apple.Terminal", windowTitle: "vim claudette"))
    }

    func testPlainShellIsNotADestination() {
        XCTAssertNil(DestinationDetector.detect(bundleID: "com.apple.Terminal", windowTitle: "zsh — 80×24"))
    }

    func testNonBrowserTitleIsIgnored() {
        // A Slack channel named "claude" shouldn't flip the profile.
        XCTAssertNil(DestinationDetector.detect(bundleID: "com.tinyspeck.slackmacgap", windowTitle: "claude"))
    }

    func testNilInputs() {
        XCTAssertNil(DestinationDetector.detect(bundleID: nil, windowTitle: "Gmail"))
        XCTAssertNil(DestinationDetector.detect(bundleID: "com.google.Chrome", windowTitle: nil))
    }

    func testWantsWindowTitleOnlyForBrowsersAndTerminals() {
        XCTAssertTrue(DestinationDetector.wantsWindowTitle(bundleID: "com.google.Chrome"))
        XCTAssertTrue(DestinationDetector.wantsWindowTitle(bundleID: "com.apple.Terminal"))
        XCTAssertFalse(DestinationDetector.wantsWindowTitle(bundleID: "com.tinyspeck.slackmacgap"))
    }

    // MARK: Profile resolution from a target

    func testGmailTabResolvesFormal() {
        let target = DictationTarget(
            bundleID: "com.google.Chrome", appName: "Chrome",
            windowTitle: "Inbox - Gmail"
        )
        XCTAssertEqual(FormattingProfiles.resolve(target: target, settings: makeSettings()).id, "formal")
    }

    func testClaudeTabResolvesPrompt() {
        let target = DictationTarget(bundleID: "com.apple.Safari", appName: "Safari", windowTitle: "Claude")
        XCTAssertEqual(FormattingProfiles.resolve(target: target, settings: makeSettings()).id, "prompt")
    }

    func testClaudeInTerminalBeatsCodeRule() {
        let target = DictationTarget(
            bundleID: "com.apple.Terminal", appName: "Terminal",
            windowTitle: "claude — 80×24"
        )
        XCTAssertEqual(FormattingProfiles.resolve(target: target, settings: makeSettings()).id, "prompt")
    }

    func testPlainTerminalStaysCode() {
        let target = DictationTarget(
            bundleID: "com.apple.Terminal", appName: "Terminal",
            windowTitle: "zsh — 80×24"
        )
        XCTAssertEqual(FormattingProfiles.resolve(target: target, settings: makeSettings()).id, "code")
    }

    func testOverrideOnDestinationWins() {
        let s = makeSettings()
        s.setProfileOverride("casual", forBundleID: "web.gmail")
        let target = DictationTarget(bundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "Inbox - Gmail")
        XCTAssertEqual(FormattingProfiles.resolve(target: target, settings: s).id, "casual")
    }

    func testMasterToggleOffUsesDefault() {
        let s = makeSettings()
        s.perAppProfilesEnabled = false
        let target = DictationTarget(bundleID: "com.apple.Safari", appName: "Safari", windowTitle: "Claude")
        XCTAssertEqual(FormattingProfiles.resolve(target: target, settings: s).id, "standard")
    }

    func testClaudeDesktopAppResolvesPrompt() {
        let target = DictationTarget(bundleID: "com.anthropic.claudefordesktop", appName: "Claude")
        XCTAssertEqual(FormattingProfiles.resolve(target: target, settings: makeSettings()).id, "prompt")
    }

    func testNilTargetUsesDefault() {
        XCTAssertEqual(FormattingProfiles.resolve(target: nil, settings: makeSettings()).id, "standard")
    }

    // MARK: Destination name for the LLM prompt

    func testDisplayNamePrefersDetectedDestination() {
        let target = DictationTarget(bundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "Inbox - Gmail")
        XCTAssertEqual(DestinationDetector.displayName(for: target), "Gmail")
    }

    func testDisplayNameFallsBackToAppName() {
        let target = DictationTarget(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack")
        XCTAssertEqual(DestinationDetector.displayName(for: target), "Slack")
    }

    func testDestinationIsInjectedIntoCleanupPrompt() {
        let prompt = CleanupPrompt.system(for: .english, destination: "Gmail")
        XCTAssertTrue(prompt.contains("pasted into Gmail"))
        XCTAssertFalse(CleanupPrompt.system(for: .english).contains("pasted into"))
    }

    func testPromptProfileExists() {
        XCTAssertEqual(FormattingProfile.with(id: "prompt").style, .prompt)
        XCTAssertNotNil(FormattingProfile.prompt.tone)
    }
}

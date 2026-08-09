import XCTest
@testable import MeanderKit

final class FormattingProfilesTests: XCTestCase {
    private func makeSettings() -> Settings {
        let suite = "meander-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return Settings(defaults: defaults)
    }

    func testEnabledByDefault() {
        XCTAssertTrue(makeSettings().perAppProfilesEnabled)
    }

    func testResolvesBuiltInRule() {
        let s = makeSettings()
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: "com.tinyspeck.slackmacgap", settings: s).style, .casual)
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: "com.apple.mail", settings: s).style, .formal)
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: "com.apple.dt.Xcode", settings: s).style, .code)
    }

    func testUnknownAppUsesDefault() {
        let s = makeSettings()
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: "com.example.unknown", settings: s).id, "standard")
    }

    func testDefaultProfileIsStandardByDefault() {
        XCTAssertEqual(makeSettings().defaultProfileID, "standard")
    }

    func testUserDefaultAppliesToUnknownApps() {
        let s = makeSettings()
        s.defaultProfileID = "casual"
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: "com.example.unknown", settings: s).id, "casual")
        // Built-in rules still win over the default.
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: "com.apple.dt.Xcode", settings: s).id, "code")
    }

    func testDisabledUsesUserDefault() {
        let s = makeSettings()
        s.defaultProfileID = "casual"
        s.perAppProfilesEnabled = false
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: "com.apple.dt.Xcode", settings: s).id, "casual")
    }

    func testOverrideBeatsBuiltIn() {
        let s = makeSettings()
        s.setProfileOverride("formal", forBundleID: "com.tinyspeck.slackmacgap")
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: "com.tinyspeck.slackmacgap", settings: s).id, "formal")
    }

    func testDisabledFallsBackToStandard() {
        let s = makeSettings()
        s.perAppProfilesEnabled = false
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: "com.apple.dt.Xcode", settings: s).id, "standard")
    }

    func testNilBundleIsStandard() {
        XCTAssertEqual(FormattingProfiles.resolve(bundleID: nil, settings: makeSettings()).id, "standard")
    }

    func testEffectiveProfileIDIgnoresMasterToggle() {
        let s = makeSettings()
        s.perAppProfilesEnabled = false
        XCTAssertEqual(FormattingProfiles.effectiveProfileID(bundleID: "com.apple.dt.Xcode", settings: s), "code")
    }

    func testCasualTrimDropsTrailingPeriodOnly() {
        XCTAssertEqual(FormattingProfiles.applyCasualTrim("sounds good."), "sounds good")
        XCTAssertEqual(FormattingProfiles.applyCasualTrim("really?"), "really?")
        XCTAssertEqual(FormattingProfiles.applyCasualTrim("wow!"), "wow!")
        XCTAssertEqual(FormattingProfiles.applyCasualTrim("hmm..."), "hmm...")
    }

    func testProfileLookupFallsBackToStandard() {
        XCTAssertEqual(FormattingProfile.with(id: "nonexistent").id, "standard")
        XCTAssertEqual(FormattingProfile.with(id: "code").style, .code)
    }

    func testToneIsInjectedIntoPrompt() {
        let prompt = CleanupPrompt.system(for: .english, tone: "Be brief.")
        XCTAssertTrue(prompt.contains("Be brief."))
        let plain = CleanupPrompt.system(for: .english)
        XCTAssertFalse(plain.contains("Be brief."))
    }
}

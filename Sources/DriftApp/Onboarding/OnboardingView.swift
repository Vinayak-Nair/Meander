import SwiftUI
import DriftKit

/// First-run setup: microphone, accessibility, and the model download. Designed so
/// the user never needs the Terminal or any separate install.
///
/// Wears the app's light `GF` design language (white canvas, GoFundMe-green
/// accent, rounded headings, soft cards) so onboarding and the dashboard read as
/// one product.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// Onboarding pages, in order: permission setup, cleanup-engine setup, then a
    /// one-time "quick wins" step. After this the same options live only in the
    /// dashboard's Settings.
    private enum Page { case setup, engines, quickWins }
    @State private var page: Page = .setup

    private var downloadFraction: Double? {
        if case .downloadingModel(let p) = state.status { return p }
        return nil
    }

    private var modelDownloaded: Bool { state.isSelectedModelDownloaded() }

    var body: some View {
        ZStack {
            switch page {
            case .setup:
                setupContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .opacity))
            case .engines:
                engineContent
                    .transition(.opacity)
            case .quickWins:
                quickWinsContent
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity))
            }
        }
        .frame(width: 520, height: 640)
        .background(OnboardingCanvas().ignoresSafeArea())
        .tint(GF.accent)
        .preferredColorScheme(.light)
        .animation(.snappy(duration: 0.3), value: page)
        .onReceive(permissionTimer) { _ in
            state.refreshPermissions()
        }
    }

    // MARK: Page header — shared layout

    /// A consistent page header: a green brand orb, a progress hint, a title and a
    /// lede — matching the dashboard's rounded, green-accented hierarchy.
    private func header(glyph: String, step: Int, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                BrandOrb(glyph: glyph)
                Spacer()
                StepDots(current: step)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(GF.ink)
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(GF.inkSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Page 1 — permission setup

    private var setupContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(glyph: "waveform", step: 0,
                   title: "Welcome to Drift",
                   subtitle: "Hold a key, speak, and your words appear as text in any app. Transcription runs entirely on your Mac.")

            VStack(spacing: 10) {
                StepRow(number: 1, title: "Microphone access", detail: "So Drift can hear you.",
                        done: state.micGranted, actionTitle: "Grant",
                        action: { Task { await state.requestMicrophone() } })
                StepRow(number: 2, title: "Accessibility access", detail: "Lets Drift type the transcribed text into other apps.",
                        done: state.accessibilityGranted, actionTitle: "Open Settings",
                        action: { state.requestAccessibility() })
                StepRow(number: 3, title: "Input Monitoring access", detail: "Lets the push-to-talk key work while other apps are focused.",
                        done: state.inputMonitoringGranted, actionTitle: "Open Settings",
                        action: { state.requestInputMonitoring() })
                modelStep
            }

            Spacer(minLength: 0)

            HStack {
                Button("Re-check") { state.refreshPermissions() }
                    .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(GF.inkSecondary)
                Spacer()
                PrimaryButton(title: "Continue") {
                    withAnimation(.snappy(duration: 0.3)) { page = .engines }
                }
                .disabled(!state.allPermissionsAndModelReady)
                .opacity(state.allPermissionsAndModelReady ? 1 : 0.45)
            }
        }
        .padding(32)
    }

    // MARK: Page 3 — quick wins (first-run only)

    private var quickWinsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(glyph: "checkmark", step: 2,
                   title: "You\u{2019}re all set",
                   subtitle: "A few quick wins to dictate faster. Turn these on now, or find them later in Settings.")

            VStack(spacing: 10) {
                TipRow(icon: "command", title: "Speak punctuation and edits, hands-free",
                       subtitle: "Say \u{201C}new line\u{201D}, \u{201C}period\u{201D}, or \u{201C}scratch that\u{201D}.",
                       toggle: $state.commandModeEnabled)
                TipRow(icon: "wand.and.stars", title: "Match your writing to each app",
                       subtitle: "Drift adapts its style to the app you dictate into.",
                       toggle: $state.perAppProfilesEnabled)
                ModelPickerRow()
            }

            Spacer(minLength: 0)

            HStack {
                Button("Back") { withAnimation(.snappy(duration: 0.3)) { page = .engines } }
                    .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(GF.inkSecondary)
                Spacer()
                PrimaryButton(title: "Start dictating") {
                    state.finishOnboarding()
                }
            }
        }
        .padding(32)
    }

    // MARK: Page 2 — cleanup engine

    /// Buzz-style engine setup: shows what this Mac can do for cleanup, with live
    /// status and a one-tap action. Fully skippable — the on-device rules engine
    /// is always ready, so no choice here can leave the user stuck.
    private var engineContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            header(glyph: "sparkles", step: 1,
                   title: "Polish what you say",
                   subtitle: "Drift tidies up as you talk: clearing filler, fixing punctuation and capitalization, and correcting names you\u{2019}ve taught it. Say \u{201C}log into you be\u{201D} and it writes \u{201C}log into Yubi\u{201D}.")

            onDeviceEngineCard

            Text("Want an LLM to rephrase too? Cloud APIs, Ollama, and LM Studio live in Settings.")
                .font(.caption).foregroundStyle(GF.inkTertiary)

            Spacer(minLength: 0)

            HStack {
                Button("Back") { withAnimation(.snappy(duration: 0.3)) { page = .setup } }
                    .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(GF.inkSecondary)
                Spacer()
                // "Skip" and "Continue" do the same thing — advance — because the
                // engine is applied the moment it's chosen above. Skip is offered
                // so a user who wants no AI feels explicitly permitted to move on.
                Button("Skip") { withAnimation(.snappy(duration: 0.3)) { page = .quickWins } }
                    .buttonStyle(.plain).font(.callout.weight(.medium)).foregroundStyle(GF.inkSecondary)
                PrimaryButton(title: "Continue") {
                    withAnimation(.snappy(duration: 0.3)) { page = .quickWins }
                }
            }
        }
        .padding(32)
    }

    /// The built-in cleanup engine: instant, on-device, always on.
    private var onDeviceEngineCard: some View {
        EngineCard(
            icon: "cpu",
            title: "On-device rules",
            subtitle: "Instant and fully private, no AI. Cleans up filler, punctuation, and taught names right on your Mac.",
            status: .ready("Active"),
            action: nil
        )
    }

    private var modelStep: some View {
        StepCard(done: modelDownloaded) {
            StepBadge(number: 4, done: modelDownloaded)
            VStack(alignment: .leading, spacing: 6) {
                Text(state.modelSetupTitle).font(.system(size: 15, weight: .semibold)).foregroundStyle(GF.ink)
                Text(state.modelSetupDetail)
                    .font(.callout).foregroundStyle(GF.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let frac = downloadFraction {
                    ProgressView(value: frac) {
                        Text("Downloading… \(Int(frac * 100))%").font(.caption).foregroundStyle(GF.inkSecondary)
                    }
                    .frame(maxWidth: 320).tint(GF.accent)
                }
                if case .error(let msg) = state.status {
                    Text(msg).font(.caption).foregroundStyle(GF.danger)
                }
            }
            Spacer()
            if modelDownloaded {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(GF.accent).font(.title2)
            } else if downloadFraction == nil {
                SecondaryButton(title: "Download", systemImage: "arrow.down.circle") { Task { await state.loadModel() } }
            }
        }
    }
}

// MARK: - Palette extension (onboarding-only semantic)

private extension GF {
    /// Warm-red used for inline error copy, matching the dashboard's error accent.
    static let danger = Color(red: 0.9, green: 0.3, blue: 0.36)
    /// Amber used for "needs a step" engine status, matching the dashboard.
    static let warning = Color(red: 0.95, green: 0.6, blue: 0.2)
    /// A hair off pure white so the first-run canvas doesn't read as flat #fff;
    /// cards stay pure white and lift off it.
    static let paper = Color(red: 0.980, green: 0.986, blue: 0.982)
}

// MARK: - Canvas

/// A white canvas with a whisper of green warmth up top — the dashboard's flat
/// white, with a soft brand glow so the first-run window feels alive.
private struct OnboardingCanvas: View {
    var body: some View {
        ZStack {
            GF.paper
            RadialGradient(colors: [GF.accent.opacity(0.06), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 520)
        }
    }
}

// MARK: - Brand orb

/// The app's brand orb: a green-gradient circle with a top highlight and a glyph,
/// matching the dashboard's `HeroAvatar`.
private struct BrandOrb: View {
    let glyph: String
    var body: some View {
        ZStack {
            Circle()
                .fill(GF.accentGradient)
                .overlay(
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
                )
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
            Image(systemName: glyph)
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Three-step progress dots in brand green.
private struct StepDots: View {
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == current ? AnyShapeStyle(GF.accent) : AnyShapeStyle(GF.accent.opacity(0.20)))
                    .frame(width: i == current ? 20 : 7, height: 7)
                    .animation(.snappy(duration: 0.3), value: current)
            }
        }
    }
}

// MARK: - Buttons

/// The prominent green CTA, mirroring the app's gradient brand fill.
private struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(Capsule().fill(GF.accentGradient.opacity(hovering ? 1 : 0.94)))
            .shadow(color: .black.opacity(hovering ? 0.16 : 0.10), radius: 10, y: 4)
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// A bordered white chip button for inline secondary actions.
private struct SecondaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(GF.ink)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? GF.gridEmpty : GF.sectionBG))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(hovering ? GF.accent.opacity(0.4) : GF.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Shared row chrome

/// A soft white card matching the dashboard's `LightCard`, with a green accent
/// when the step is complete.
private struct StepCard<Content: View>: View {
    let done: Bool
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(done ? GF.accentSoft : GF.cardBG)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(done ? GF.accent.opacity(0.35) : GF.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

/// The numbered / checked badge on a step row — a green circle when done, a soft
/// green ring with the step number while pending.
private struct StepBadge: View {
    let number: Int
    let done: Bool
    var body: some View {
        ZStack {
            Circle()
                .fill(done ? AnyShapeStyle(GF.accentGradient) : AnyShapeStyle(GF.accentSoft))
                .frame(width: 28, height: 28)
            if done {
                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
            } else {
                Text("\(number)").font(.caption.bold()).foregroundStyle(GF.accent)
            }
        }
    }
}

/// A soft circular icon tile — the app's `GF.accentSoft` circle with a green
/// glyph, as used across the dashboard.
private struct IconTile: View {
    let icon: String
    var body: some View {
        ZStack {
            Circle().fill(GF.accentSoft).frame(width: 44, height: 44)
            Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(GF.accent)
        }
    }
}

// MARK: - Cards & rows

/// A selectable cleanup-engine card: icon, name, one-line pitch, a live status
/// pill, and an optional action button.
private struct EngineCard: View {
    enum Status {
        case ready(String)      // green — selected / always-on
        case neutral(String)    // available, not yet chosen
        case attention(String)  // needs a step from the user
        case working(String)    // downloading / warming up
        case unavailable(String)

        var text: String {
            switch self {
            case .ready(let t), .neutral(let t), .attention(let t), .working(let t), .unavailable(let t): return t
            }
        }
        var tint: Color {
            switch self {
            case .ready: return GF.accent
            case .neutral: return GF.inkTertiary // available, not the active engine
            case .attention: return GF.warning
            case .working: return GF.accent
            case .unavailable: return GF.inkTertiary
            }
        }
    }

    struct Action {
        let title: String
        var icon: String = "arrow.right"
        let perform: () -> Void
    }

    let icon: String
    let title: String
    let subtitle: String
    let status: Status
    let action: Action?

    var body: some View {
        HStack(spacing: 14) {
            IconTile(icon: icon)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(GF.ink)
                    statusPill
                }
                Text(subtitle).font(.caption).foregroundStyle(GF.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action {
                SecondaryButton(title: action.title, systemImage: action.icon, action: action.perform)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isReady ? GF.accentSoft : GF.cardBG)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isReady ? GF.accent.opacity(0.35) : GF.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            if case .working = status {
                ProgressView().controlSize(.mini).tint(status.tint)
            } else {
                Circle().fill(status.tint).frame(width: 6, height: 6)
            }
            Text(status.text).font(.system(size: 10, weight: .semibold)).foregroundStyle(status.tint)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(status.tint.opacity(0.14)))
    }
}

/// A recommended-setup row on the final onboarding page: an icon, a short pitch,
/// and an optional inline toggle. Rows without a toggle just point to Settings.
private struct TipRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var toggle: Binding<Bool>? = nil

    var body: some View {
        HStack(spacing: 14) {
            IconTile(icon: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(GF.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.caption).foregroundStyle(GF.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let toggle {
                Toggle("", isOn: toggle).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GF.cardBG))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GF.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

/// A card that lets the user pick their speech model right in onboarding. Uses
/// the single bundled model+engine list so the choice stays one decision; a
/// heavier model simply downloads on first use.
private struct ModelPickerRow: View {
    @EnvironmentObject var state: AppState

    private var currentName: String {
        state.dictationModelOptions.first { $0.id == state.selectedDictationModelID }?.displayName ?? "Choose a model"
    }

    var body: some View {
        HStack(spacing: 14) {
            IconTile(icon: "cpu")
            VStack(alignment: .leading, spacing: 6) {
                Text("Pick your speech model").font(.subheadline.weight(.semibold)).foregroundStyle(GF.ink)
                Text("Runs on your Mac. Bigger is more accurate, smaller is faster; new models download on first use.")
                    .font(.caption).foregroundStyle(GF.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                modelMenu
            }
            Spacer(minLength: 8)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(GF.cardBG))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GF.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }

    private var modelMenu: some View {
        Menu {
            ForEach(state.dictationModelOptions) { option in
                Button {
                    state.selectDictationModel(option.id)
                } label: {
                    if option.id == state.selectedDictationModelID {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentName).font(.caption.weight(.medium)).foregroundStyle(GF.ink).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(GF.inkSecondary)
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GF.sectionBG))
        }
        .menuStyle(.borderlessButton)
        .padding(.top, 2)
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let detail: String
    let done: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        StepCard(done: done) {
            StepBadge(number: number, done: done)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(GF.ink)
                Text(detail).font(.callout).foregroundStyle(GF.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(GF.accent).font(.title2)
            } else {
                SecondaryButton(title: actionTitle, systemImage: "arrow.right", action: action)
            }
        }
    }
}

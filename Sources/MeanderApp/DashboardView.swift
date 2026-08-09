import SwiftUI
import MeanderKit

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @State private var appeared = false
    @State private var query = ""
    @State private var newTerm = ""

    enum Section: String, CaseIterable, Identifiable {
        case home = "Home", history = "History", apps = "Apps", dictionary = "Dictionary", settings = "Settings"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .history: return "clock.arrow.circlepath"
            case .apps: return "square.grid.2x2.fill"
            case .dictionary: return "character.book.closed.fill"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(GF.hairline).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                sidebar
                ScrollView {
                    mainContent
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.top, 28)
                        .padding(.bottom, 40)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .frame(minWidth: 940, minHeight: 720)
        .background(GF.pageBG.ignoresSafeArea())
        .tint(GF.accent)
        .preferredColorScheme(.light)
        .onAppear { withAnimation(.easeOut(duration: 0.3)) { appeared = true } }
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            HStack(spacing: 9) {
                Image("BrandMark")
                    .resizable().scaledToFit().frame(height: 22)
                Text("meander")
                    .font(.system(size: 21, weight: .medium, design: .rounded)).tracking(-0.3)
                    .foregroundStyle(GF.ink)
            }
            HStack {
                Spacer()
                StatusChip(text: state.statusBadgeText, color: state.statusBadgeColor, pulsing: state.isRecordingStatus)
            }
            .padding(.trailing, 24)
        }
        .frame(height: 60)
        .padding(.leading, 90) // clear the floating window controls
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Section.allCases) { s in
                SideItem(title: s.rawValue, icon: s.icon, active: state.dashboardSection == s) {
                    withAnimation(.snappy(duration: 0.25)) { state.dashboardSection = s }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .frame(width: 232)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Main content

    @ViewBuilder private var mainContent: some View {
        switch state.dashboardSection {
        case .home: homeView
        case .history: historyView
        case .apps: appsView
        case .dictionary: dictionaryView
        case .settings: settingsView
        }
    }

    private var homeView: some View {
        let stats = DashboardStats(state.transcriptHistory)
        return VStack(spacing: 24) {
            HeroCard(stats: stats, lifetimeWords: state.lifetimeWords, lifetimeDictations: state.lifetimeDictations, keyName: state.keyName(state.settings.pttKeyCode))
            activityCard(stats)
            recentSection
        }
    }

    /// The latest dictations, surfaced on Home so the most recent transcripts are a
    /// click away to copy or reuse. "See all" opens the full History tab.
    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent dictations")
                    .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(GF.ink)
                Spacer()
                if state.transcriptHistory.count > 3 {
                    Button { withAnimation(.snappy(duration: 0.25)) { state.dashboardSection = .history } } label: {
                        HStack(spacing: 3) { Text("See all"); Image(systemName: "arrow.right") }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(GF.accent)
                    }.buttonStyle(.plain)
                }
            }
            if state.transcriptHistory.isEmpty {
                LightCard {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(GF.accentSoft).frame(width: 44, height: 44)
                            Image(systemName: "waveform").font(.system(size: 17, weight: .medium)).foregroundStyle(GF.accent)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No dictations yet").font(.callout.weight(.semibold)).foregroundStyle(GF.ink)
                            Text("Hold \(state.keyName(state.settings.pttKeyCode)) and speak to get started.")
                                .font(.caption).foregroundStyle(GF.inkSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                ForEach(state.transcriptHistory.prefix(3)) { entry in
                    LightTranscriptRow(entry: entry) { state.copyTranscript(entry) }
                }
            }
        }
    }

    /// A GitHub-style heatmap of dictation activity: the home page's centerpiece.
    private func activityCard(_ stats: DashboardStats) -> some View {
        LightCard {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Activity").font(.callout.weight(.semibold)).foregroundStyle(GF.ink)
                    Text("\(stats.total) total · \(stats.week) this week")
                        .font(.caption).foregroundStyle(GF.inkSecondary)
                }
                Spacer()
                if stats.streak > 0 { StreakChip(days: stats.streak) }
            }
            ContributionGraph(entries: state.transcriptHistory)
            HStack { Spacer(); ActivityLegend() }
        }
    }

    // MARK: History

    private var filtered: [TranscriptEntry] {
        guard !query.isEmpty else { return state.transcriptHistory }
        let q = query.lowercased()
        return state.transcriptHistory.filter { $0.text.lowercased().contains(q) || $0.microphoneName.lowercased().contains(q) }
    }

    private var historyView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transcript History").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(GF.ink)
                    Text(historySubtitle).font(.caption).foregroundStyle(GF.inkSecondary)
                }
                Spacer()
                if !state.transcriptHistory.isEmpty {
                    Button(role: .destructive) { withAnimation(.smooth) { state.clearTranscriptHistory() } } label: {
                        Label("Clear", systemImage: "trash")
                    }
                }
            }
            if !state.transcriptHistory.isEmpty {
                LightSearchField(text: $query)
            }

            if state.transcriptHistory.isEmpty {
                hint(symbol: "waveform", title: "No transcripts yet", message: "Hold your push-to-talk key and speak — finished dictations land here.")
            } else if filtered.isEmpty {
                hint(symbol: "text.magnifyingglass", title: "No matches", message: "Nothing matches “\(query)”.")
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(DashboardStats.group(filtered).enumerated()), id: \.element.title) { index, group in
                        Text(group.title.uppercased())
                            .font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(GF.inkTertiary)
                            .padding(.top, index == 0 ? 0 : 8)
                        ForEach(group.entries) { entry in
                            LightTranscriptRow(entry: entry, highlight: query) { state.copyTranscript(entry) }
                        }
                    }
                }
            }
        }
    }

    private var historySubtitle: String {
        if !query.isEmpty { let n = filtered.count; return n == 1 ? "1 match" : "\(n) matches" }
        let c = state.transcriptHistory.count
        return c == 0 ? "Nothing captured yet" : (c == 1 ? "1 dictation" : "\(c) dictations")
    }

    // MARK: Apps

    private var appsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Per-app Formatting").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(GF.ink)

            LightCard {
                HStack {
                    Text("Match style to the app").font(.callout.weight(.semibold)).foregroundStyle(GF.ink)
                    Spacer()
                    Toggle("", isOn: $state.perAppProfilesEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if state.perAppProfilesEnabled {
                    Text("Meander matches its style to where you dictate, including web apps like Gmail and AI tools like Claude or Codex.")
                        .font(.caption).foregroundStyle(GF.inkSecondary)
                    LightProfileRow(name: "Default", systemIcon: "asterisk.circle.fill", selection: $state.defaultProfileID)
                    ForEach(state.recentTargetApps.prefix(8)) { app in
                        LightAppRow(app: app)
                    }
                    Button { state.addApp() } label: { Label("Add app…", systemImage: "plus") }
                        .buttonStyle(.bordered).controlSize(.regular)
                } else {
                    Text("Turn on to auto-switch style per app.").font(.caption).foregroundStyle(GF.inkSecondary)
                }
            }

            LightCard {
                HStack {
                    Text("Command mode").font(.callout.weight(.semibold)).foregroundStyle(GF.ink)
                    Spacer()
                    Toggle("", isOn: $state.commandModeEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                Text(state.commandModeEnabled ? "Speak formatting instead of typing it." : "Turn on to speak punctuation and edits.")
                    .font(.caption).foregroundStyle(GF.inkSecondary)
                if state.commandModeEnabled {
                    ForEach(CommandProcessor.reference, id: \.spoken) { cmd in
                        HStack {
                            Text("“\(cmd.spoken)”").font(.caption2.weight(.medium)).foregroundStyle(GF.ink)
                            Spacer()
                            Text(cmd.effect).font(.caption2).foregroundStyle(GF.inkSecondary)
                        }
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: state.perAppProfilesEnabled)
        .animation(.smooth(duration: 0.25), value: state.commandModeEnabled)
    }

    // MARK: Dictionary

    private var dictionaryView: some View {
        let terms = Vocabulary.parse(state.customVocabularyRaw)
        return VStack(alignment: .leading, spacing: 18) {
            Text("Dictionary").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(GF.ink)

            LightCard {
                HStack {
                    Text("Names & terms").font(.callout.weight(.semibold)).foregroundStyle(GF.ink)
                    Spacer()
                    if !terms.isEmpty {
                        Text("\(terms.count) \(terms.count == 1 ? "term" : "terms")")
                            .font(.caption.weight(.semibold)).foregroundStyle(GF.accent)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(GF.accentSoft))
                    }
                }
                Text("Words Meander keeps mishearing: people, places, brands.")
                    .font(.caption).foregroundStyle(GF.inkSecondary)

                HStack(spacing: 8) {
                    TextField("Add a name or term", text: $newTerm)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GF.sectionBG))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(GF.cardBorder, lineWidth: 1))
                        .onSubmit(addTerm)
                    Button(action: addTerm) {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !terms.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(terms, id: \.self) { term in
                            TermChip(term: term) { removeTerm(term) }
                        }
                    }
                    .padding(.top, 4)
                }
            }

            LightCard {
                Text("How it works").font(.callout.weight(.semibold)).foregroundStyle(GF.ink)
                dictionaryPoint(icon: "waveform", text: "Whisper is nudged toward these spellings while it listens.")
                dictionaryPoint(icon: "ear", text: "Close mishears are fixed on your Mac: \u{201C}current johar\u{201D} becomes \u{201C}Karan Johar\u{201D}.")
                dictionaryPoint(icon: "wand.and.stars", text: "AI cleanup providers can restore even badly garbled terms.")
                dictionaryPoint(icon: "sparkles", text: "Fix a word right after dictating and Meander learns it automatically.")
            }
        }
    }

    /// Appends the typed term to the stored vocabulary (newline-separated raw
    /// string shared with MeanderKit). Case-insensitive duplicates are ignored.
    private func addTerm() {
        let term = newTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        newTerm = ""
        let existing = Vocabulary.parse(state.customVocabularyRaw)
        guard !existing.contains(where: { $0.lowercased() == term.lowercased() }) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            state.customVocabularyRaw = (existing + [term]).joined(separator: "\n")
        }
    }

    private func removeTerm(_ term: String) {
        let remaining = Vocabulary.parse(state.customVocabularyRaw).filter { $0 != term }
        withAnimation(.snappy(duration: 0.2)) {
            state.customVocabularyRaw = remaining.joined(separator: "\n")
        }
    }

    private func dictionaryPoint(icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(GF.accent)
                .frame(width: 18)
            Text(text).font(.caption).foregroundStyle(GF.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Settings

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(GF.ink)

            LightCard {
                Text("Input").font(.callout.weight(.semibold)).foregroundStyle(GF.ink)
                Picker("Microphone", selection: Binding(get: { state.selectedMicrophoneID }, set: { state.selectMicrophone($0) })) {
                    ForEach(state.availableMicrophones) { d in Text(d.name).tag(d.id) }
                }.labelsHidden()
                LightDetail(title: "Active input", value: state.selectedMicrophoneName)
                HStack {
                    Button { state.refreshSelectedMicrophone() } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
                    Button { state.openSoundSettings() } label: { Label("Sound", systemImage: "speaker.wave.2") }.buttonStyle(.bordered)
                }
            }

            LightCard {
                Text("Model").font(.callout.weight(.semibold)).foregroundStyle(GF.ink)
                Picker("Model", selection: Binding(get: { state.selectedDictationModelID }, set: { state.selectDictationModel($0) })) {
                    ForEach(state.dictationModelOptions) { o in Text(o.displayName).tag(o.id) }
                }.labelsHidden()
                if state.supportsLanguageSelection {
                    Picker("Language", selection: $state.languageCode) {
                        ForEach(state.availableLanguages) { l in Text(l.displayName).tag(l.code) }
                    }.labelsHidden()
                } else {
                    LightDetail(title: "Language", value: state.languageDisplayName)
                }
                LightDetail(title: "Push-to-talk", value: state.keyName(state.settings.pttKeyCode))
            }

            LightCard {
                Text("Cleanup").font(.callout.weight(.semibold)).foregroundStyle(GF.ink)
                Picker("Provider", selection: $state.cleanupProviderID) {
                    ForEach(CleanupRegistry.all) { info in Text(info.displayName).tag(info.id) }
                }.labelsHidden()

                switch state.cleanupProviderID {
                case "openai":
                    lightField("Base URL", text: $state.openAIBaseURL)
                    lightField("Model", text: $state.openAIModel)
                    lightSecureField("API Key", text: $state.openAIKey)
                    lightNote("Works with any OpenAI-compatible API: OpenAI, Groq, Sarvam, LM Studio.")
                case "ollama":
                    lightField("Base URL", text: $state.ollamaBaseURL)
                    lightField("Model", text: $state.ollamaModel)
                    lightNote("Requires Ollama running locally with the model pulled.")
                case "none":
                    lightNote("Text is inserted exactly as transcribed.")
                default:
                    lightNote("Fast, private formatting on your Mac. No setup, no network.")
                }
            }
        }
    }

    private func lightNote(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(GF.inkSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private func lightField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text).textFieldStyle(.roundedBorder)
    }

    private func lightSecureField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text).textFieldStyle(.roundedBorder)
    }

    private func hint(symbol: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(GF.accentSoft).frame(width: 72, height: 72)
                Image(systemName: symbol).font(.system(size: 26, weight: .medium)).foregroundStyle(GF.accent)
            }
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(GF.ink)
            Text(message).font(.callout).foregroundStyle(GF.inkSecondary).multilineTextAlignment(.center).frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }
}

// MARK: - Palette

/// The app's light design system — a white canvas with a GoFundMe-green brand
/// accent. Internal (not private) so the onboarding flow wears the exact same
/// language as the dashboard.
enum GF {
    static let pageBG = Color.white
    static let sectionBG = Color(red: 0.953, green: 0.961, blue: 0.969)
    static let cardBG = Color.white
    static let hairline = Color.black.opacity(0.06)
    static let cardBorder = Color.black.opacity(0.06)
    static let gridEmpty = Color(red: 0.90, green: 0.92, blue: 0.94)

    static let ink = Color(red: 0.105, green: 0.12, blue: 0.15)
    static let inkSecondary = Color(red: 0.42, green: 0.46, blue: 0.51)
    static let inkTertiary = Color(red: 0.60, green: 0.64, blue: 0.69)

    // GoFundMe green
    static let accent = Color(red: 0.05, green: 0.72, blue: 0.42)
    static let accentDeep = Color(red: 0.09, green: 0.36, blue: 0.22)
    static let accentSoft = Color(red: 0.05, green: 0.72, blue: 0.42).opacity(0.14)
    static let accentGradient = LinearGradient(
        colors: [Color(red: 0.46, green: 0.85, blue: 0.50), Color(red: 0.07, green: 0.74, blue: 0.42), Color(red: 0.02, green: 0.59, blue: 0.37)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let heroGradient = LinearGradient(
        colors: [Color(red: 0.80, green: 0.93, blue: 0.66), Color(red: 0.87, green: 0.95, blue: 0.75)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let pastelBlue = Color(red: 0.85, green: 0.93, blue: 0.99)
    static let pastelGreen = Color(red: 0.86, green: 0.95, blue: 0.89)
    static let pastelTeal = Color(red: 0.82, green: 0.94, blue: 0.93)
}

// MARK: - Sidebar item

private struct SideItem: View {
    let title: String
    let icon: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(active ? AnyShapeStyle(GF.accentGradient) : AnyShapeStyle(Color.black.opacity(hovering ? 0.06 : 0.04)))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(active ? .white : GF.inkSecondary)
                }
                Text(title)
                    .font(.system(size: 16, weight: active ? .bold : .medium))
                    .foregroundStyle(active ? GF.ink : GF.inkSecondary)
                Spacer()
            }
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

// MARK: - Hero card

private struct HeroCard: View {
    let stats: DashboardStats
    let lifetimeWords: Int
    let lifetimeDictations: Int
    let keyName: String

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 16) {
                Color.clear.frame(height: 36)

                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Text("\(lifetimeWords.formatted()) words")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(GF.accentDeep)
                        Image(systemName: "chevron.right").font(.system(size: 18, weight: .bold)).foregroundStyle(GF.accentDeep.opacity(0.6))
                    }
                    HStack(spacing: 6) {
                        Text("Hold").foregroundStyle(GF.accentDeep.opacity(0.7))
                        LightKeycap(keyName)
                        Text("to talk").foregroundStyle(GF.accentDeep.opacity(0.7))
                    }
                    .font(.system(size: 14, weight: .semibold))
                }

                HStack(spacing: 9) {
                    HeroPill(value: lifetimeDictations.formatted(), label: "Dictations")
                    HeroPill(value: stats.week.formatted(), label: "This week")
                    HeroPill(value: "\(stats.streak)", label: stats.streak == 1 ? "Day streak" : "Day streak")
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(GF.heroGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(RadialGradient(colors: [.white.opacity(0.5), .clear], center: .topLeading, startRadius: 0, endRadius: 320))
                    )
            )
            .padding(.top, 40)

            HeroAvatar()
        }
    }
}

private struct HeroAvatar: View {
    @State private var breathe = false
    var body: some View {
        ZStack {
            // Sprout spike
            Capsule().fill(GF.accentGradient).frame(width: 5, height: 16).offset(y: -42)
            // Progress ring
            Circle().trim(from: 0, to: 0.82)
                .stroke(GF.accentGradient, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 84, height: 84)
            // White ring
            Circle().fill(.white).frame(width: 78, height: 78)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
            // Orb
            ZStack {
                Circle().fill(GF.accentGradient)
                    .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .top, endPoint: .center)))
                    .frame(width: 64, height: 64)
                Image(systemName: "waveform").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
            }
            .scaleEffect(breathe ? 1.03 : 0.99)
        }
        .frame(width: 84, height: 84)
        .onAppear { withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true } }
    }
}

private struct HeroPill: View {
    let value: String
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(GF.ink)
            Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(GF.inkSecondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Capsule().fill(.white))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }
}

// MARK: - Contribution graph

/// A GitHub-style activity heatmap: one cell per day, brightening with the number
/// of dictations that day. Cells are a fixed size; the number of week-columns is
/// derived from the available width so the grid always fills the card.
private struct ContributionGraph: View {
    let entries: [TranscriptEntry]

    private let cell: CGFloat = 13
    private let gap: CGFloat = 3
    private let weekdayLabelWidth: CGFloat = 28
    private let monthRowHeight: CGFloat = 15

    private var gridHeight: CGFloat { cell * 7 + gap * 6 }
    private var totalHeight: CGFloat { monthRowHeight + 6 + gridHeight }

    private struct DayCell: Identifiable { let id = UUID(); let date: Date; let count: Int; let isFuture: Bool }
    private struct Column: Identifiable { let id: Int; let days: [DayCell] }
    private struct MonthMark: Identifiable { let id = UUID(); let col: Int; let text: String }

    var body: some View {
        GeometryReader { geo in
            let weeks = weekCount(for: geo.size.width)
            let cal = Calendar.current
            let columns = buildColumns(weeks: weeks, cal: cal, counts: dailyCounts(cal: cal))
            VStack(alignment: .leading, spacing: 6) {
                monthHeader(columns)
                HStack(spacing: gap) {
                    weekdayColumn
                    HStack(spacing: gap) {
                        ForEach(columns) { col in
                            VStack(spacing: gap) {
                                ForEach(col.days) { cellView($0) }
                            }
                        }
                    }
                }
            }
        }
        .frame(height: totalHeight)
    }

    private func cellView(_ day: DayCell) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(day.isFuture ? Color.clear : activityColor(activityLevel(day.count)))
            .frame(width: cell, height: cell)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.black.opacity(day.isFuture ? 0 : 0.04), lineWidth: 1)
            )
            .help(day.isFuture ? "" : "\(day.count) \(day.count == 1 ? "dictation" : "dictations") · \(day.date.formatted(date: .abbreviated, time: .omitted))")
    }

    private var weekdayColumn: some View {
        VStack(spacing: gap) {
            ForEach(0..<7, id: \.self) { row in
                Text(weekdayLabel(row))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(GF.inkTertiary)
                    .frame(height: cell)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(width: weekdayLabelWidth)
    }

    private func monthHeader(_ columns: [Column]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(monthMarks(columns)) { mark in
                Text(mark.text)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(GF.inkTertiary)
                    .offset(x: CGFloat(mark.col) * (cell + gap))
            }
        }
        .frame(maxWidth: .infinity, minHeight: monthRowHeight, maxHeight: monthRowHeight, alignment: .topLeading)
        .padding(.leading, weekdayLabelWidth + gap)
    }

    // MARK: Data

    private func weekCount(for width: CGFloat) -> Int {
        let usable = width - weekdayLabelWidth - gap
        let n = Int(((usable + gap) / (cell + gap)).rounded(.down))
        return max(6, min(53, n))
    }

    private func dailyCounts(cal: Calendar) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for entry in entries {
            counts[cal.startOfDay(for: entry.createdAt), default: 0] += 1
        }
        return counts
    }

    private func buildColumns(weeks: Int, cal: Calendar, counts: [Date: Int]) -> [Column] {
        let today = cal.startOfDay(for: Date())
        let weekdayIndex = cal.component(.weekday, from: today) - 1 // 0 = Sunday
        let startOfThisWeek = cal.date(byAdding: .day, value: -weekdayIndex, to: today)!
        let firstColumnStart = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: startOfThisWeek)!

        return (0..<weeks).map { c in
            let days = (0..<7).map { r -> DayCell in
                let date = cal.date(byAdding: .day, value: c * 7 + r, to: firstColumnStart)!
                return DayCell(date: date, count: counts[date] ?? 0, isFuture: date > today)
            }
            return Column(id: c, days: days)
        }
    }

    /// One label per month, above the first column of that month, skipping any
    /// that would crowd the previous label.
    private func monthMarks(_ columns: [Column]) -> [MonthMark] {
        let cal = Calendar.current
        var marks: [MonthMark] = []
        var lastMonth = -1
        var lastCol = -10
        for (i, col) in columns.enumerated() {
            let m = cal.component(.month, from: col.days[0].date)
            guard m != lastMonth else { continue }
            lastMonth = m
            if i == 0 || i - lastCol >= 2 {
                marks.append(MonthMark(col: i, text: col.days[0].date.formatted(.dateTime.month(.abbreviated))))
                lastCol = i
            }
        }
        return marks
    }

    private func weekdayLabel(_ row: Int) -> String {
        switch row {
        case 1: return "Mon"
        case 3: return "Wed"
        case 5: return "Fri"
        default: return ""
        }
    }
}

/// The "Less → More" key beneath the contribution graph.
private struct ActivityLegend: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("Less").font(.system(size: 10)).foregroundStyle(GF.inkTertiary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(activityColor(level))
                    .frame(width: 11, height: 11)
                    .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).strokeBorder(Color.black.opacity(0.04), lineWidth: 1))
            }
            Text("More").font(.system(size: 10)).foregroundStyle(GF.inkTertiary)
        }
    }
}

/// A small "N day streak" chip shown beside the activity header.
private struct StreakChip: View {
    let days: Int
    private let amber = Color(red: 0.95, green: 0.6, blue: 0.2)
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill").font(.system(size: 11, weight: .bold))
            Text("\(days) day streak").font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(amber.opacity(0.14)))
        .foregroundStyle(amber)
    }
}

/// Buckets a day's dictation count into one of five intensity levels.
private func activityLevel(_ count: Int) -> Int {
    switch count {
    case 0: return 0
    case 1: return 1
    case 2...3: return 2
    case 4...6: return 3
    default: return 4
    }
}

/// The green ramp for the heatmap: a faint slot when idle, deepening to full brand
/// green at the top of the scale.
private func activityColor(_ level: Int) -> Color {
    switch level {
    case 0: return GF.gridEmpty
    case 1: return GF.accent.opacity(0.3)
    case 2: return GF.accent.opacity(0.55)
    case 3: return GF.accent.opacity(0.8)
    default: return GF.accent
    }
}

// MARK: - Light shared rows

private struct LightCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(GF.cardBG))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(GF.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

/// A dictionary term rendered as a removable pill.
private struct TermChip: View {
    let term: String
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Text(term).font(.system(size: 13, weight: .medium)).foregroundStyle(GF.ink)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(hovering ? GF.ink : GF.inkTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(hovering ? GF.gridEmpty : GF.sectionBG))
        .overlay(Capsule().strokeBorder(GF.cardBorder, lineWidth: 1))
        .onHover { hovering = $0 }
    }
}

/// Left-aligned wrapping layout for the term chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? max(x - spacing, 0) : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct LightDetail: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(GF.inkSecondary)
            Spacer()
            Text(value).font(.callout.weight(.medium)).foregroundStyle(GF.ink).lineLimit(1)
        }
    }
}

private struct LightProfileRow: View {
    let name: String
    let systemIcon: String
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemIcon).font(.system(size: 14)).foregroundStyle(GF.accent).frame(width: 20)
            Text(name).font(.callout).foregroundStyle(GF.ink)
            Spacer()
            Picker("", selection: $selection) {
                ForEach(FormattingProfile.all) { p in Text(p.name).tag(p.id) }
            }.labelsHidden().pickerStyle(.menu).fixedSize()
        }
    }
}

private struct LightAppRow: View {
    @EnvironmentObject var state: AppState
    let app: TargetApp
    @State private var hovering = false
    var body: some View {
        HStack(spacing: 10) {
            if let icon = state.appIcon(forBundleID: app.bundleID) {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: state.appSymbol(forBundleID: app.bundleID))
                    .foregroundStyle(GF.inkTertiary).frame(width: 20)
            }
            Text(app.name).font(.callout).foregroundStyle(GF.ink).lineLimit(1)
            Spacer()
            Picker("", selection: Binding(
                get: { state.profileID(forBundleID: app.bundleID) },
                set: { state.setProfile($0, forBundleID: app.bundleID) }
            )) {
                ForEach(FormattingProfile.all) { p in Text(p.name).tag(p.id) }
            }.labelsHidden().pickerStyle(.menu).fixedSize()
            Button { state.removeApp(app) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(GF.inkTertiary)
            }.buttonStyle(.plain).opacity(hovering ? 1 : 0)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct LightTranscriptRow: View {
    let entry: TranscriptEntry
    var highlight: String = ""
    let copy: () -> Void
    @State private var hovering = false
    @State private var justCopied = false

    private var wordCount: Int { entry.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.createdAt.formatted(.relative(presentation: .named)))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(GF.ink)
                Spacer(minLength: 8)
                Text("\(wordCount) words").font(.caption2.weight(.medium)).foregroundStyle(GF.inkSecondary)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.black.opacity(0.05)))
                Button {
                    copy(); justCopied = true
                    Task { try? await Task.sleep(for: .seconds(1.4)); justCopied = false }
                } label: {
                    Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(justCopied ? Color.green : GF.inkSecondary)
                        .contentTransition(.symbolEffect(.replace))
                }.buttonStyle(.plain).opacity(justCopied || hovering ? 1 : 0.4)
            }
            highlightedText.font(.body).foregroundStyle(GF.ink.opacity(0.85)).lineSpacing(2)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.system(size: 9)).foregroundStyle(GF.inkTertiary)
                Text(entry.microphoneName).lineLimit(1)
                Text("·").foregroundStyle(GF.inkTertiary)
                Text(Language.from(code: entry.languageCode).displayName)
            }
            .font(.caption2).foregroundStyle(GF.inkSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(GF.cardBG))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(hovering ? GF.accent.opacity(0.4) : GF.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(hovering ? 0.07 : 0.03), radius: hovering ? 10 : 5, y: 2)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
        .animation(.snappy(duration: 0.25), value: justCopied)
    }

    private var highlightedText: Text {
        guard !highlight.isEmpty, let range = entry.text.range(of: highlight, options: .caseInsensitive) else { return Text(entry.text) }
        return Text(String(entry.text[..<range.lowerBound]))
            + Text(String(entry.text[range])).foregroundColor(GF.accent).bold()
            + Text(String(entry.text[range.upperBound...]))
    }
}

private struct LightSearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(GF.inkTertiary)
            TextField("Search transcripts", text: $text).textFieldStyle(.plain).font(.callout).focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(GF.inkTertiary) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(GF.sectionBG))
        .overlay(Capsule().strokeBorder(focused ? GF.accent.opacity(0.5) : GF.cardBorder, lineWidth: 1))
        .frame(maxWidth: 280)
    }
}

private struct LightKeycap: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(GF.accentDeep.opacity(0.15), lineWidth: 1))
            .foregroundStyle(GF.accentDeep)
    }
}

private struct StatusChip: View {
    let text: String
    let color: Color
    let pulsing: Bool
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color.opacity(0.9))
    }
}

// MARK: - Derived stats

private struct DashboardStats {
    var total = 0
    var words = 0
    var today = 0
    var week = 0
    var avg = 0
    var streak = 0
    var daily = Array(repeating: 0, count: 7)

    init(_ entries: [TranscriptEntry]) {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        total = entries.count
        var activeDays = Set<Date>()
        for e in entries {
            let w = e.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            words += w
            if cal.isDateInToday(e.createdAt) { today += 1 }
            let dayStart = cal.startOfDay(for: e.createdAt)
            activeDays.insert(dayStart)
            let diff = cal.dateComponents([.day], from: dayStart, to: todayStart).day ?? 99
            if diff >= 0, diff < 7 { daily[6 - diff] += 1; week += 1 }
        }
        avg = total == 0 ? 0 : Int((Double(words) / Double(total)).rounded())
        var probe = activeDays.contains(todayStart) ? todayStart : cal.date(byAdding: .day, value: -1, to: todayStart)!
        while activeDays.contains(probe) { streak += 1; probe = cal.date(byAdding: .day, value: -1, to: probe)! }
    }

    struct Section { let title: String; let entries: [TranscriptEntry] }

    static func group(_ entries: [TranscriptEntry]) -> [Section] {
        let cal = Calendar.current
        var today: [TranscriptEntry] = [], yesterday: [TranscriptEntry] = [], earlier: [TranscriptEntry] = []
        for e in entries {
            if cal.isDateInToday(e.createdAt) { today.append(e) }
            else if cal.isDateInYesterday(e.createdAt) { yesterday.append(e) }
            else { earlier.append(e) }
        }
        var out: [Section] = []
        if !today.isEmpty { out.append(Section(title: "Today", entries: today)) }
        if !yesterday.isEmpty { out.append(Section(title: "Yesterday", entries: yesterday)) }
        if !earlier.isEmpty { out.append(Section(title: "Earlier", entries: earlier)) }
        return out
    }
}

// MARK: - Status helpers

private extension AppState {
    var isDownloading: Bool { if case .downloadingModel = status { return true }; return false }
    var isRecordingStatus: Bool { if case .recording = status { return true }; return false }
    var statusBadgeText: String {
        switch status {
        case .needsSetup: return "Setup"
        case .loadingModel, .downloadingModel: return "Loading"
        case .idle: return "Ready"
        case .recording: return "Recording"
        case .transcribing: return "Processing"
        case .error: return "Error"
        }
    }
    var statusBadgeColor: Color {
        switch status {
        case .idle: return Color(red: 0.13, green: 0.7, blue: 0.42)
        case .recording: return Color(red: 0.9, green: 0.3, blue: 0.36)
        case .transcribing, .loadingModel, .downloadingModel: return Color(red: 0.95, green: 0.6, blue: 0.2)
        case .needsSetup: return Color(red: 0.95, green: 0.6, blue: 0.2)
        case .error: return Color(red: 0.9, green: 0.3, blue: 0.36)
        }
    }
}

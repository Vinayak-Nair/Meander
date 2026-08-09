import AppKit
import AVFoundation
import ApplicationServices
import IOKit.hid
import SwiftUI
import UniformTypeIdentifiers
import MeanderKit

/// Central app orchestrator: owns the model, pipeline, and hotkey; tracks status
/// and permissions; drives the dictation flow; and manages the onboarding and
/// settings windows. `@MainActor` so UI state is always touched on the main thread.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Status: Equatable {
        case needsSetup
        case loadingModel
        case downloadingModel(Double)
        case idle
        case recording
        case transcribing
        case error(String)
    }

    @Published private(set) var status: Status = .needsSetup
    /// True once a model load has been running long enough to warrant reassuring
    /// the user (first-run CoreML compile). Drives the "Preparing model…" copy.
    @Published private(set) var modelLoadIsSlow = false
    @Published private(set) var micGranted = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var lastText = ""
    /// Live partial transcript shown in the overlay while streaming (Nemotron).
    @Published private(set) var livePartialText = ""
    /// Live mic loudness (0...1) driving the overlay waveform. Smoothed with a
    /// fast attack / slow release so the wave jumps to life on speech and eases
    /// back to a flat line in silence.
    @Published private(set) var audioLevel: Double = 0
    /// Live frequency spectrum (relative band magnitudes, 0...1) shaping the
    /// waveform so it reflects the actual content of your voice, not just volume.
    @Published private(set) var audioSpectrum: [Double] = Array(repeating: 0, count: 24)
    @Published private(set) var transcriptHistory: [TranscriptEntry]
    /// Lifetime tallies that survive the 100-entry trim on `transcriptHistory`,
    /// so the dashboard hero reflects true cumulative usage instead of only the
    /// most recent window of transcripts.
    @Published private(set) var lifetimeDictations: Int
    @Published private(set) var lifetimeWords: Int
    @Published private(set) var recentTargetApps: [TargetApp]
    @Published private(set) var availableMicrophones: [AudioInputDevice]
    @Published private(set) var selectedMicrophoneID: String
    @Published private(set) var selectedMicrophoneName: String

    // Editable settings mirrors (observable for SwiftUI). didSet writes through.
    @Published var languageCode: String { didSet { settings.languageCode = languageCode } }
    @Published var cleanupProviderID: String { didSet { settings.cleanupProviderID = cleanupProviderID } }
    @Published var commandModeEnabled: Bool { didSet { settings.commandModeEnabled = commandModeEnabled } }
    @Published var perAppProfilesEnabled: Bool { didSet { settings.perAppProfilesEnabled = perAppProfilesEnabled } }
    @Published var defaultProfileID: String { didSet { settings.defaultProfileID = defaultProfileID } }
    @Published var openAIBaseURL: String { didSet { settings.openAIBaseURL = openAIBaseURL } }
    @Published var openAIModel: String { didSet { settings.openAIModel = openAIModel } }
    @Published var openAIKey: String { didSet { settings.openAIKey = openAIKey } }
    @Published var ollamaBaseURL: String { didSet { settings.ollamaBaseURL = ollamaBaseURL } }
    @Published var ollamaModel: String { didSet { settings.ollamaModel = ollamaModel } }
    @Published var customVocabularyRaw: String { didSet { settings.customVocabularyRaw = customVocabularyRaw } }
    @Published private(set) var transcriptionBackendID: String
    @Published private(set) var modelVariant: String

    let settings = Settings.shared
    private let modelManager = ModelManager()
    private var pipeline: Pipeline?
    private let hotkey = Hotkey()
    private var onboardingWindow: NSWindow?
    private var overlayWindow: NSPanel?
    /// The selected sidebar tab in the main window. Lives here (not as local
    /// view state) so the menu bar can navigate straight to a section.
    @Published var dashboardSection: DashboardView.Section = .home
    /// Terms shown in the "Added to dictionary" toast (empty = no toast).
    @Published private(set) var learnedToastTerms: [String] = []
    private var learnedToastWindow: NSPanel?
    private var learnedToastDismissTask: Task<Void, Never>?
    private var streamingStartTask: Task<Void, Never>?
    private var streamingStartFailed = false
    /// Fires while a model is loading; flips `modelLoadIsSlow` so the status copy
    /// reassures the user instead of looking frozen during a slow first-run load.
    private var longLoadWatchdog: Task<Void, Never>?
    private let transcriptHistoryKey = "transcriptHistory"
    private let transcriptHistoryLimit = 100
    private let lifetimeDictationsKey = "lifetimeDictations"
    private let lifetimeWordsKey = "lifetimeWords"
    private let recentAppsKey = "recentTargetApps"
    private let recentAppsLimit = 12
    /// The app frontmost when the current dictation started (bundle id, name,
    /// and focused window title); drives the per-app formatting profile and the
    /// destination hint handed to LLM cleanup.
    private var currentTarget: DictationTarget?
    /// Learns dictionary terms from corrections the user makes after pasting.
    private let correctionWatcher = CorrectionWatcher()

    private init() {
        let s = Settings.shared
        languageCode = s.languageCode
        cleanupProviderID = s.cleanupProviderID
        commandModeEnabled = s.commandModeEnabled
        perAppProfilesEnabled = s.perAppProfilesEnabled
        defaultProfileID = s.defaultProfileID
        openAIBaseURL = s.openAIBaseURL
        openAIModel = s.openAIModel
        openAIKey = s.openAIKey
        ollamaBaseURL = s.ollamaBaseURL
        ollamaModel = s.ollamaModel
        customVocabularyRaw = s.customVocabularyRaw
        transcriptionBackendID = s.transcriptionBackendID
        modelVariant = s.modelVariant
        let loadedHistory = Self.loadTranscriptHistory()
        transcriptHistory = loadedHistory
        (lifetimeDictations, lifetimeWords) = Self.loadLifetimeTotals(seedFrom: loadedHistory)
        recentTargetApps = Self.loadRecentTargetApps()

        let devices = AudioInputDevices.available()
        var microphoneID = s.inputDeviceID
        if !devices.contains(where: { $0.id == microphoneID }) {
            microphoneID = AudioInputDevice.systemDefaultID
            s.inputDeviceID = microphoneID
        }
        availableMicrophones = devices
        selectedMicrophoneID = microphoneID
        selectedMicrophoneName = AudioInputDevices.displayName(
            for: microphoneID,
            in: devices
        )
    }

    // MARK: Lifecycle

    func bootstrap() async {
        refreshPermissions()
        refreshSelectedMicrophone()
        // Register the MLX on-device LLM cleanup provider (no-op if its model
        // isn't downloaded) and warm it so the first dictation isn't cold.
        MLXBridge.register(modelsRoot: modelManager.modelsDirectory, settings: settings)
        // Repairs dictionaries poisoned by the old auto-learning rules before any
        // dictation can be run through them. Terms learned back then include
        // ordinary words like "taking" and "present", and the corrector matches on
        // sound, so leaving them in place would keep rewriting correct transcripts.
        let pruned = settings.pruneJunkFromVocabularyOnce()
        if !pruned.isEmpty {
            customVocabularyRaw = settings.customVocabularyRaw
            LatencyLog.record("pruned \(pruned.count) common word(s) from dictionary: \(pruned.joined(separator: ", "))")
        }
        // Covers dictionaries that already existed (including terms typed by hand
        // in Settings, which don't go through `learnVocabulary`).
        installVocabularyBoostIfNeeded()
        let ready = settings.hasCompletedOnboarding && micGranted
            && accessibilityGranted && inputMonitoringGranted && modelManager.isDefaultModelDownloaded
        if !inputMonitoringGranted {
            // Required for the global push-to-talk key to be observed while Meander
            // is in the background (Accessibility alone only works foreground).
            requestInputMonitoring()
        }
        if ready {
            await loadModelAndStart()
        } else {
            status = .needsSetup
            showOnboardingWindow()
        }
    }

    private func loadModelAndStart() async {
        await loadModel()
        if case .idle = status { startHotkey() }
    }

    func loadModel(variant: String? = nil) async {
        let target = variant ?? settings.modelVariant
        let downloaded = modelManager.isSelectedModelDownloaded(variant: target)
        status = downloaded ? .loadingModel : .downloadingModel(0)
        startLoadWatchdog(active: downloaded)
        defer { stopLoadWatchdog() }
        do {
            let transcriber = try await modelManager.loadTranscriber(variant: target) { [weak self] frac in
                Task { @MainActor in self?.status = .downloadingModel(frac) }
            }
            let newPipeline = Pipeline(transcriber: transcriber, settings: settings)
            newPipeline.onAudioLevel = { [weak self] level in
                Task { @MainActor in self?.applyAudioLevel(Double(level)) }
            }
            newPipeline.onAudioSpectrum = { [weak self] bands in
                Task { @MainActor in self?.applySpectrum(bands.map(Double.init)) }
            }
            pipeline = newPipeline
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Starts a timer that, after a grace period, marks an in-progress load as slow
    /// so the menu shows reassuring copy instead of a frozen "Preparing model…".
    /// Only armed when the model is already downloaded (i.e. the wait is a load, not
    /// a download that already shows its own progress percentage).
    private func startLoadWatchdog(active: Bool) {
        longLoadWatchdog?.cancel()
        modelLoadIsSlow = false
        guard active else { return }
        longLoadWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.modelLoadIsSlow = true
        }
    }

    private func stopLoadWatchdog() {
        longLoadWatchdog?.cancel()
        longLoadWatchdog = nil
        modelLoadIsSlow = false
    }

    private func startHotkey() {
        hotkey.onPress = { Task { @MainActor in AppState.shared.startDictation() } }
        hotkey.onRelease = { Task { @MainActor in await AppState.shared.stopDictation() } }
        hotkey.start()
    }

    // MARK: Dictation

    func toggleDictation() {
        if case .recording = status { Task { await stopDictation() } }
        else { startDictation() }
    }

    func startDictation() {
        guard case .idle = status, let pipeline else { return }
        captureTargetApp()
        refreshSelectedMicrophone()

        if pipeline.supportsStreaming {
            startStreamingDictation(pipeline)
            return
        }

        do {
            livePartialText = ""
            showLiveOverlay()
            try pipeline.startRecording()
            status = .recording
            Feedback.start()
        } catch {
            hideLiveOverlay()
            status = .error("Microphone unavailable")
        }
    }

    private func startStreamingDictation(_ pipeline: Pipeline) {
        // Set .recording synchronously so a key release that arrives before the
        // async setup finishes still pairs with this press (stopDictation awaits
        // the start task below). Otherwise the release is dropped and the app
        // gets stuck in .recording, making the hotkey appear dead.
        livePartialText = ""
        showLiveOverlay()
        status = .recording
        Feedback.start()
        streamingStartTask = Task {
            do {
                try await pipeline.startStreaming { [weak self] partial in
                    Task { @MainActor in self?.livePartialText = partial }
                }
            } catch {
                self.streamingStartFailed = true
            }
        }
    }

    func stopDictation() async {
        guard case .recording = status, let pipeline else { return }
        let streaming = pipeline.supportsStreaming
        status = .transcribing
        if streaming {
            await streamingStartTask?.value // ensure start finished before finishing
            streamingStartTask = nil
        }
        do {
            if streaming && streamingStartFailed {
                streamingStartFailed = false
                hideLiveOverlay()
                status = .idle
                Feedback.empty()
                return
            }
            let text = streaming
                ? try await pipeline.stopStreamingAndProcess(target: currentTarget)
                : try await pipeline.stopAndProcess(target: currentTarget)
            hideLiveOverlay()
            status = .idle
            if text.isEmpty {
                Feedback.empty()
            } else {
                lastText = text
                recordTranscript(text)
                Paster.paste(text)
                Feedback.success()
                correctionWatcher.watch(
                    pasted: text,
                    vocabulary: { [settings] in settings.customVocabulary },
                    onLearn: { [weak self] terms in self?.learnVocabulary(terms) }
                )
            }
        } catch {
            hideLiveOverlay()
            status = .idle
            Feedback.empty()
        }
    }

    // MARK: Dictionary learning

    /// Adds terms learned from user corrections to the dictionary and surfaces
    /// them in a floating toast (with Remove to undo). A term that already
    /// exists with different casing is updated in place ("vinayak" becomes
    /// "Vinayak") rather than duplicated.
    ///
    /// Each correction also records what the transcript actually said and which
    /// engine produced it. The engine tag is recorded against the term, not used
    /// to scope it: the mishearing describes how the term sounds, so it is worth
    /// applying whichever backend is active later.
    func learnVocabulary(_ terms: [DictionaryLearner.LearnedTerm]) {
        var book = settings.vocabularyBook
        let before = book.entries
        let source = settings.transcriptionBackend.rawValue
        for learned in terms {
            book.note(term: learned.term, misheardAs: learned.misheardAs, source: source)
        }
        guard book.entries != before else { return }
        settings.vocabularyBook = book
        // Keep the published copy in step: the settings editor binds to the raw
        // text, and `settings` was written behind its back.
        customVocabularyRaw = settings.customVocabularyRaw
        showLearnedToast(terms.map(\.term))
        installVocabularyBoostIfNeeded()
    }

    /// Fetches the auxiliary model that lets Parakeet check the dictionary
    /// against the audio, in the background, the first time the user has terms
    /// worth checking. Failure is silent: the dictionary still works through the
    /// text-level layers, and the next attempt retries.
    func installVocabularyBoostIfNeeded() {
        let manager = modelManager
        Task.detached(priority: .utility) {
            await manager.installParakeetVocabularyBoostIfNeeded()
        }
    }

    /// Removes a dictionary entry (case-insensitive). Used by the toast's Remove.
    func removeVocabularyTerm(_ term: String) {
        var book = settings.vocabularyBook
        book.remove(term: term)
        settings.vocabularyBook = book
        customVocabularyRaw = settings.customVocabularyRaw
    }

    // MARK: Learned-term toast

    /// Shows a small floating card (top-right) confirming what auto-learning
    /// just added, so a wrong guess is one click to undo. Auto-fades after a
    /// few seconds; x dismisses immediately.
    private func showLearnedToast(_ terms: [String]) {
        learnedToastTerms = terms
        learnedToastDismissTask?.cancel()

        if learnedToastWindow == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false // the SwiftUI card draws its own shadow
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: LearnedToastView().environmentObject(self))
            learnedToastWindow = panel
        }
        guard let panel = learnedToastWindow else { return }
        layoutLearnedToast()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        learnedToastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.dismissLearnedToast()
        }
    }

    func dismissLearnedToast() {
        learnedToastDismissTask?.cancel()
        learnedToastDismissTask = nil
        guard let panel = learnedToastWindow, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    /// Undoes one learned term from the toast; the toast shrinks or disappears.
    func removeLearnedTerm(_ term: String) {
        removeVocabularyTerm(term)
        learnedToastTerms.removeAll { $0 == term }
        if learnedToastTerms.isEmpty {
            dismissLearnedToast()
        } else {
            // Re-fit the panel after SwiftUI drops the removed row.
            DispatchQueue.main.async { self.layoutLearnedToast() }
        }
    }

    /// Sizes the panel to the card and pins it to the bottom-center of the
    /// screen (same neighborhood as the live dictation overlay).
    private func layoutLearnedToast() {
        guard let panel = learnedToastWindow, let content = panel.contentView,
              let screen = NSScreen.main else { return }
        let size = content.fittingSize
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 48
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: Model selection

    // MARK: Model selection

    func selectTranscriptionBackend(_ id: String) {
        guard id != settings.transcriptionBackendID else { return }
        settings.transcriptionBackendID = id
        transcriptionBackendID = settings.transcriptionBackendID
        normalizeLanguageForSelectedBackend()
        hotkey.stop()
        Task {
            await loadModel()
            if case .idle = status { startHotkey() }
        }
    }

    func selectModel(_ variant: String) {
        guard variant != settings.modelVariant else { return }
        settings.modelVariant = variant
        modelVariant = variant
        hotkey.stop()
        Task {
            await loadModel(variant: variant)
            if case .idle = status { startHotkey() }
        }
    }

    /// A selectable dictation model that bundles its engine. The dashboard exposes
    /// only this single list so the user picks a model; the engine is derived and
    /// switched automatically (engine choice lives in Settings).
    struct DictationModelOption: Identifiable, Hashable {
        let id: String
        let displayName: String
        let backendID: String
        let variant: String?
    }

    var dictationModelOptions: [DictationModelOption] {
        var options: [DictationModelOption] = [
            DictationModelOption(
                id: TranscriptionBackend.fluidAudioParakeet.id,
                displayName: "Parakeet v3, English (fastest)",
                backendID: TranscriptionBackend.fluidAudioParakeet.id,
                variant: nil
            ),
            DictationModelOption(
                id: TranscriptionBackend.nemotronEnglish.id,
                displayName: "Nemotron 0.6B, English (streaming, beta)",
                backendID: TranscriptionBackend.nemotronEnglish.id,
                variant: nil
            )
        ]
        for option in ModelCatalog.options {
            options.append(DictationModelOption(
                id: "whisperKit:\(option.id)",
                displayName: "Whisper \(option.displayName), multilingual",
                backendID: TranscriptionBackend.whisperKit.id,
                variant: option.id
            ))
        }
        return options
    }

    var selectedDictationModelID: String {
        switch transcriptionBackend {
        case .fluidAudioParakeet: return TranscriptionBackend.fluidAudioParakeet.id
        case .nemotronEnglish: return TranscriptionBackend.nemotronEnglish.id
        case .whisperKit: return "whisperKit:\(modelVariant)"
        }
    }

    /// Selects a model and switches the engine to match in one reload.
    func selectDictationModel(_ id: String) {
        guard let option = dictationModelOptions.first(where: { $0.id == id }) else { return }

        let backendChanged = option.backendID != settings.transcriptionBackendID
        let variantChanged = option.variant != nil && option.variant != settings.modelVariant
        guard backendChanged || variantChanged else { return }

        settings.transcriptionBackendID = option.backendID
        transcriptionBackendID = option.backendID
        if let variant = option.variant {
            settings.modelVariant = variant
            modelVariant = variant
        }
        normalizeLanguageForSelectedBackend()

        hotkey.stop()
        Task {
            await loadModel()
            if case .idle = status { startHotkey() }
        }
    }

    // MARK: Permissions

    func refreshPermissions() {
        micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Prompts for Input Monitoring (required to observe the push-to-talk key
    /// while Meander is in the background) and opens the right System Settings pane.
    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestMicrophone() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refreshPermissions()
        refreshSelectedMicrophone()
    }

    /// Prompts for Accessibility and opens the right System Settings pane.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func finishOnboarding() {
        settings.hasCompletedOnboarding = true
        onboardingWindow?.close()
        if pipeline != nil, case .idle = status {
            startHotkey() // model already loaded during onboarding
        } else {
            Task { await loadModelAndStart() }
        }
    }

    // MARK: Windows

    func showOnboardingWindow() {
        if let onboardingWindow {
            NSApp.activate(ignoringOtherApps: true)
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: OnboardingView().environmentObject(self))
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to Meander"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        // Seamless light chrome: let the warm paper background flow up into the
        // title bar, and force a light (Aqua) appearance so the traffic lights and
        // titlebar read correctly on the cream backdrop regardless of system theme.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(NSSize(width: 520, height: 640))
        window.isReleasedWhenClosed = false
        window.center()
        onboardingWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Live transcription overlay

    /// Shows a floating, click-through panel near the bottom of the screen that
    /// displays the live partial transcript while streaming.
    func showLiveOverlay() {
        if overlayWindow == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: LiveOverlayView().environmentObject(self))
            overlayWindow = panel
        }
        positionOverlay()
        overlayWindow?.orderFrontRegardless()
    }

    func hideLiveOverlay() {
        overlayWindow?.orderOut(nil)
        livePartialText = ""
        audioLevel = 0
        audioSpectrum = Array(repeating: 0, count: audioSpectrum.count)
    }

    /// Publishes the latest mic readings as raw targets. The smoothing that makes
    /// the waveform buttery happens per-frame in the view (`WaveMotion`) at display
    /// rate, so we deliberately don't pre-smooth here — that would only add lag and
    /// blunt the amplitude's jump on a loud syllable.
    private func applyAudioLevel(_ target: Double) {
        audioLevel = min(1, max(0, target))
    }

    private func applySpectrum(_ bands: [Double]) {
        guard !bands.isEmpty else { return }
        audioSpectrum = bands
    }

    private func positionOverlay() {
        guard let overlayWindow, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = overlayWindow.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 120
        )
        overlayWindow.setFrameOrigin(origin)
    }

    // MARK: Derived UI state

    var menuBarSymbol: String {
        switch status {
        case .recording: return "waveform.circle.fill"
        case .transcribing, .loadingModel, .downloadingModel: return "ellipsis.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .needsSetup: return "waveform.badge.exclamationmark"
        case .idle: return "waveform"
        }
    }

    var statusText: String {
        switch status {
        case .needsSetup: return "Setup required"
        case .loadingModel:
            return modelLoadIsSlow ? "Preparing model… first run can take a minute" : "Preparing model…"
        case .downloadingModel(let p): return "Downloading model… \(Int(p * 100))%"
        case .idle: return "Ready. Hold \(keyName(settings.pttKeyCode)) to talk"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .error(let m): return "Error: \(m)"
        }
    }

    var isReady: Bool { if case .idle = status { return true } else { return false } }

    var languageDisplayName: String {
        settings.effectiveLanguage.displayName
    }

    var cleanupProviderDisplayName: String {
        CleanupRegistry.all.first { $0.id == cleanupProviderID }?.displayName ?? cleanupProviderID
    }

    var transcriptionBackend: TranscriptionBackend {
        TranscriptionBackend.from(id: transcriptionBackendID)
    }

    var transcriptionBackendDisplayName: String {
        transcriptionBackend.displayName
    }

    var supportsLanguageSelection: Bool {
        transcriptionBackend.supportsLanguageSelection
    }

    var availableLanguages: [Language] {
        switch transcriptionBackend {
        case .fluidAudioParakeet, .nemotronEnglish:
            return [.english]
        case .whisperKit:
            return Language.whisperKitLanguages
        }
    }

    var modelDisplayName: String {
        if let backendModel = transcriptionBackend.modelDisplayName {
            return backendModel
        }
        return ModelCatalog.options.first { $0.id == modelVariant }?.displayName ?? modelVariant
    }

    var modelSetupTitle: String {
        switch transcriptionBackend {
        case .fluidAudioParakeet, .nemotronEnglish:
            return "Download the English speech model"
        case .whisperKit:
            return "Download the speech model"
        }
    }

    var modelSetupDetail: String {
        switch transcriptionBackend {
        case .fluidAudioParakeet:
            return "A one-time FluidAudio Parakeet v3 download for fast, local dictation."
        case .nemotronEnglish:
            return "A one-time Nemotron 0.6B streaming model download (English). Prototype for evaluating streaming latency."
        case .whisperKit:
            return "A one-time download of the multilingual Whisper model. Fully on-device. Supports English, Indian languages (Hindi, Tamil, Malayalam, Kannada, Telugu, and more), plus major world languages."
        }
    }

    var allPermissionsAndModelReady: Bool {
        micGranted && accessibilityGranted && inputMonitoringGranted && modelManager.isSelectedModelDownloaded()
    }

    func isModelDownloaded(_ variant: String) -> Bool { modelManager.isDownloaded(variant) }
    func isSelectedModelDownloaded() -> Bool { modelManager.isSelectedModelDownloaded() }

    private func normalizeLanguageForSelectedBackend() {
        let current = Language.from(code: languageCode)
        let fallback: Language
        switch transcriptionBackend {
        case .fluidAudioParakeet, .nemotronEnglish:
            fallback = .english
        case .whisperKit:
            fallback = .auto
        }
        guard !availableLanguages.contains(current) else { return }
        languageCode = fallback.code
    }

    func keyName(_ code: Int) -> String {
        switch code {
        case 61: return "Right Option (⌥)"
        case 58: return "Left Option (⌥)"
        case 54: return "Right Command (⌘)"
        case 55: return "Left Command (⌘)"
        case 60: return "Right Shift (⇧)"
        case 62: return "Right Control (⌃)"
        default: return "key \(code)"
        }
    }

    // MARK: Dashboard

    func refreshSelectedMicrophone() {
        availableMicrophones = AudioInputDevices.available()
        if selectedMicrophoneID != AudioInputDevice.systemDefaultID,
           !availableMicrophones.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = AudioInputDevice.systemDefaultID
            settings.inputDeviceID = selectedMicrophoneID
        }
        selectedMicrophoneName = AudioInputDevices.displayName(
            for: selectedMicrophoneID,
            in: availableMicrophones
        )
    }

    func selectMicrophone(_ id: String) {
        selectedMicrophoneID = id
        settings.inputDeviceID = id
        refreshSelectedMicrophone()
    }

    func clearTranscriptHistory() {
        transcriptHistory.removeAll()
        persistTranscriptHistory()
        lifetimeDictations = 0
        lifetimeWords = 0
        persistLifetimeTotals()
    }

    func copyTranscript(_ entry: TranscriptEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    func openSoundSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Per-app formatting

    /// Remembers which app is frontmost as a dictation begins — that's the app the
    /// text will paste into, so it drives the formatting profile. For browsers and
    /// terminals the focused window title is captured too, so Meander can tell a
    /// Gmail tab from a Claude tab, or a `claude`/`codex` session from a shell.
    private func captureTargetApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else {
            currentTarget = nil
            return
        }
        let name = app.localizedName ?? bundleID
        let title = DestinationDetector.wantsWindowTitle(bundleID: bundleID)
            ? focusedWindowTitle(of: app) : nil
        currentTarget = DictationTarget(bundleID: bundleID, appName: name, windowTitle: title)
        recordTargetApp(bundleID: bundleID, name: name)
        // Surface the detected destination (Gmail, Claude Code…) in the dashboard
        // list too, so its profile can be tuned like any real app's.
        if let destination = DestinationDetector.detect(bundleID: bundleID, windowTitle: title) {
            recordTargetApp(bundleID: destination.id, name: destination.name)
        }
    }

    /// Reads the app's focused window title via Accessibility (a permission
    /// Meander already requires for pasting). Only called for browsers and
    /// terminals, where the title reveals the actual destination.
    private func focusedWindowTitle(of app: NSRunningApplication) -> String? {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var titleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleRef) == .success else {
            return nil
        }
        return titleRef as? String
    }

    private func recordTargetApp(bundleID: String, name: String) {
        var apps = recentTargetApps.filter { $0.bundleID != bundleID }
        apps.insert(TargetApp(bundleID: bundleID, name: name), at: 0)
        if apps.count > recentAppsLimit { apps.removeLast(apps.count - recentAppsLimit) }
        recentTargetApps = apps
        persistRecentApps()
    }

    private func persistRecentApps() {
        if let data = try? JSONEncoder().encode(recentTargetApps) {
            UserDefaults.standard.set(data, forKey: recentAppsKey)
        }
    }

    /// Lets the user pick any installed app to give it a formatting profile,
    /// without waiting to dictate into it first.
    func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app for a formatting profile"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        recordTargetApp(bundleID: bundleID, name: name)
    }

    /// Removes an app from the list and clears any per-app override, reverting it
    /// to the default profile.
    func removeApp(_ app: TargetApp) {
        recentTargetApps.removeAll { $0.bundleID == app.bundleID }
        settings.setProfileOverride(nil, forBundleID: app.bundleID)
        persistRecentApps()
    }

    /// The profile id currently in effect for an app (override → built-in → standard).
    func profileID(forBundleID id: String) -> String {
        FormattingProfiles.effectiveProfileID(bundleID: id, settings: settings)
    }

    func setProfile(_ profileID: String, forBundleID id: String) {
        settings.setProfileOverride(profileID, forBundleID: id)
        objectWillChange.send() // overrides aren't @Published; nudge the UI
    }

    /// The destination app's icon, if it can be located on disk.
    func appIcon(forBundleID id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// SF Symbol fallback for entries without an app icon: detected web and CLI
    /// destinations get a hint of what they are.
    func appSymbol(forBundleID id: String) -> String {
        if id.hasPrefix("web.") { return "globe" }
        if id.hasPrefix("cli.") { return "terminal" }
        return "app.dashed"
    }

    private static func loadRecentTargetApps() -> [TargetApp] {
        guard let data = UserDefaults.standard.data(forKey: "recentTargetApps"),
              let decoded = try? JSONDecoder().decode([TargetApp].self, from: data) else {
            return []
        }
        return decoded
    }

    private func recordTranscript(_ text: String) {
        let entry = TranscriptEntry(
            createdAt: Date(),
            text: text,
            languageCode: settings.effectiveLanguage.code,
            microphoneName: selectedMicrophoneName
        )
        transcriptHistory.insert(entry, at: 0)
        if transcriptHistory.count > transcriptHistoryLimit {
            transcriptHistory.removeLast(transcriptHistory.count - transcriptHistoryLimit)
        }
        persistTranscriptHistory()

        lifetimeDictations += 1
        lifetimeWords += Self.wordCount(text)
        persistLifetimeTotals()
    }

    /// Counts words the same way the dashboard does, so the hero total and any
    /// per-entry counts stay consistent.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private static func loadTranscriptHistory() -> [TranscriptEntry] {
        guard let data = UserDefaults.standard.data(forKey: "transcriptHistory"),
              let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persistTranscriptHistory() {
        guard let data = try? JSONEncoder().encode(transcriptHistory) else { return }
        UserDefaults.standard.set(data, forKey: transcriptHistoryKey)
    }

    /// Loads the persisted lifetime tallies. On first run after this feature
    /// shipped there is no stored value, so we seed from whatever history the
    /// user already has rather than starting them at zero.
    private static func loadLifetimeTotals(seedFrom history: [TranscriptEntry]) -> (dictations: Int, words: Int) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "lifetimeDictations") == nil {
            let seededDictations = history.count
            let seededWords = history.reduce(0) { $0 + wordCount($1.text) }
            defaults.set(seededDictations, forKey: "lifetimeDictations")
            defaults.set(seededWords, forKey: "lifetimeWords")
            return (seededDictations, seededWords)
        }
        return (defaults.integer(forKey: "lifetimeDictations"),
                defaults.integer(forKey: "lifetimeWords"))
    }

    private func persistLifetimeTotals() {
        UserDefaults.standard.set(lifetimeDictations, forKey: lifetimeDictationsKey)
        UserDefaults.standard.set(lifetimeWords, forKey: lifetimeWordsKey)
    }
}

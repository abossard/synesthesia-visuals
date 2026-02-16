// SwiftVJApp - SwiftUI macOS Application
// Phase 7: Unidirectional Data Flow Architecture

import SwiftUI
import SwiftVJCore
import Metal
import AppKit
import Combine
import OSCKit
import OscRestBridge

// Serial queue to process high-rate playback OSC off the main actor
private let playbackOSCQueue = DispatchQueue(label: "vj.playback.osc.queue", qos: .userInitiated)

private func makeLaunchpadOscSender(
    oscHub: OSCHub,
    onError: @escaping @Sendable (String) -> Void
) -> (OscCommand) -> Void {
    { command in
        // OSCHub is started from the main actor; route sends through main to keep queue ownership consistent.
        DispatchQueue.main.async {
            let values: [any OSCValue] = command.args.map { arg -> any OSCValue in
                switch arg {
                case .int(let v): return Int32(v)
                case .float(let v): return Float32(v)
                case .string(let v): return v
                case .bool(let v): return v ? Int32(1) : Int32(0)
                }
            }
            do {
                try oscHub.sendToSynesthesia(command.address, values: values)
            } catch {
                onError("OSC send to Synesthesia failed (\(command.address)): \(error)")
            }
        }
    }
}

private func makeLaunchpadDispatchSink(
    sendOnMain: @escaping @MainActor (AppAction) -> Void
) -> (AppAction) -> Void {
    { action in
        Task { @MainActor in
            sendOnMain(action)
        }
    }
}

private actor LaunchpadGateway: LaunchpadEffectHandling {
    private let module: LaunchpadModule

    init(module: LaunchpadModule) {
        self.module = module
    }

    func start() async {
        _ = module.start()
    }

    func stop() async {
        module.stop()
    }

    func buttonPressed(x: Int, y: Int) async {
        module.handleVirtualPadPress(ButtonId(x: x, y: y))
    }

    func buttonReleased(x: Int, y: Int) async {
        module.handleVirtualPadRelease(ButtonId(x: x, y: y))
    }

    func enterLearnMode() async {
        module.startLearnMode()
    }

    func exitLearnMode() async {
        module.stopLearnMode()
    }

    func forceProgrammerMode() async {
        module.forceProgrammerMode()
    }

    func flashAll() async {
        let allPads = allPadIds()
        module.setLeds(allPads.map { ($0, LP.red) })
        try? await Task.sleep(for: .milliseconds(500))
        module.setLeds(allPads.map { ($0, LP.off) })
    }

    func rainbowPattern() async {
        let colors = [LP.red, LP.orange, LP.yellow, LP.green, LP.cyan, LP.blue, LP.purple, LP.pink]
        var updates: [(ButtonId, Int)] = []
        for y in 0..<8 {
            for x in 0..<8 {
                updates.append((ButtonId(x: x, y: y), colors[(x + y) % colors.count]))
            }
        }
        module.setLeds(updates)
    }

    func clearAll() async {
        let allPads = allPadIds()
        module.setLeds(allPads.map { ($0, LP.off) })
    }

    func receiveOscEvent(_ event: OscEvent) async {
        module.receiveOscEvent(event)
    }

    private func allPadIds() -> [ButtonId] {
        (0...8).flatMap { x in
            (0...8).map { y in ButtonId(x: x, y: y) }
        }
    }
}

@main
struct SwiftVJApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }

            // Karaoke menu
            CommandMenu("Karaoke") {
                Button("Show Lyrics Panel") {
                    openWindow(id: "karaoke-lyrics")
                }
                .keyboardShortcut("L", modifiers: [.command, .shift])

                Divider()

                Button("Load Test Lyrics") {
                    Task { @MainActor in
                        appState.renderEngine?.karaokeEngine.loadTestLyrics()
                    }
                }

                Button("Next Line") {
                    Task { @MainActor in
                        appState.renderEngine?.karaokeEngine.nextLine()
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Button("Previous Line") {
                    Task { @MainActor in
                        appState.renderEngine?.karaokeEngine.previousLine()
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
            }
        }

        // Karaoke Lyrics Panel Window
        Window("Karaoke Lyrics", id: "karaoke-lyrics") {
            KaraokeLyricsPanelWindow()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                window.makeKeyAndOrderFront(nil)
                window.center()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - AppState (Store-Based)

/// Application state using unidirectional data flow.
/// Actions → Reducer → State → Views
@MainActor
public final class AppState: ObservableObject {

    // MARK: - Store

    private let store: Store<SwiftVJCore.AppState, AppAction>
    private var cancellables = Set<AnyCancellable>()
    private let isTestMode: Bool

    // MARK: - Modules

    public let oscHub = OSCHub()
    public let settings = Settings()
    public var playbackModule: PlaybackModule?
    public var lyricsModule: LyricsModule?
    public var aiModule: AIModule?
    public var shadersModule: ShadersModule?
    public var imagesModule: ImagesModule?
    public var pipelineModule: PipelineModule?
    private var launchpadModule: LaunchpadModule?
    private var launchpadGateway: LaunchpadGateway?
    private var launcherGateway: AppLauncherGateway?
    public var songsModule: SongsModule?
    public let synesthesiaAudio = SynesthesiaAudioProcessor()
    private let ledfxFeature: LedFXFeature

    // MARK: - Cache Adapters (for clearing)
    
    private var lyricsFetcher: LyricsFetcher?
    private var llmClient: LLMClient?

    // MARK: - Render Engine

    @Published var renderEngine: RenderEngine?

    // MARK: - State (derived from Store)

    @Published public private(set) var isRunning = false
    @Published public private(set) var currentTrack: Track?
    @Published public private(set) var playbackPosition: Double = 0
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var playbackSource: String = "vdj"
    @Published public private(set) var launchpadStatus: LaunchpadStatus?
    @Published public private(set) var launchpadState: ControllerState?
    @Published public private(set) var launchpadConfig: LaunchpadYAMLConfig?
    @Published public private(set) var pipelineSteps: [PipelineStep] = []
    @Published public private(set) var pipelineResult: PipelineResult?
    @Published public private(set) var pipelineExpandedSteps: Set<String> = []
    @Published public private(set) var imageIndex: Int = 0
    @Published public private(set) var imageCount: Int = 0
    @Published public private(set) var shaderCount: Int = 0
    @Published public private(set) var selectedShader: String?
    @Published public private(set) var selectedMaskShader: String?
    @Published public private(set) var renderEnabled: Bool = true
    @Published public private(set) var renderOutputs: RenderOutputsState = RenderOutputsState()
    @Published public private(set) var currentPhase: Phase?
    @Published public private(set) var detectedSongPhase: Phase?
    @Published public private(set) var songsState: SongsSubState = SongsSubState()

    // MARK: - UI State (private(set) enforces unidirectional flow)
    
    @Published public private(set) var logEntries: [LogEntry] = []
    @Published public private(set) var oscMessages: [String: OSCLogEntry] = [:]
    @Published public private(set) var oscMessageCount: Int = 0
    @Published public private(set) var oscFilter: String = ""
    @Published public private(set) var oscDebugEnabled: Bool = false {
        didSet { _oscDebugEnabledUnsafe = oscDebugEnabled }
    }
    nonisolated(unsafe) private var _oscDebugEnabledUnsafe: Bool = false

    // MARK: - LedFX UI State

    @Published public private(set) var ledfxBaseURL: String = "http://127.0.0.1:8888"
    @Published public private(set) var ledfxVirtualIdsString: String = ""
    @Published public private(set) var ledfxIsRefreshing: Bool = false
    @Published public private(set) var ledfxIsApplying: Bool = false
    @Published public private(set) var ledfxIsGeneratingConfig: Bool = false
    @Published public private(set) var ledfxServerInfo: LedFXInfo?
    @Published public private(set) var ledfxScenes: [String: LedFXScene] = [:]
    @Published public private(set) var ledfxVirtuals: [String: LedFXVirtual] = [:]
    @Published public private(set) var ledfxPlaylists: [String: LedFXPlaylist] = [:]
    @Published public private(set) var ledfxActivePlaylistId: String?
    @Published public private(set) var ledfxSceneFilter: String = ""
    @Published public private(set) var ledfxPlaylistFilter: String = ""
    @Published public private(set) var ledfxErrorMessage: String?
    @Published public private(set) var ledfxGeneratedConfig: BridgeConfig?
    @Published public private(set) var ledfxGeneratedYaml: String?
    @Published public private(set) var ledfxPlaylistCount: Int = 0
    @Published public private(set) var ledfxEffectsCount: Int = 0
    @Published public private(set) var ledfxIsRunning: Bool = false
    @Published public private(set) var ledfxHealthSummary: String = "Unknown"
    @Published public private(set) var ledfxLastHealthCheck: Date?

    // MARK: - Launcher UI State

    @Published public private(set) var launcherTargets: [LaunchTarget] = []
    @Published public private(set) var launcherRunningTargetIDs: Set<String> = []
    @Published public private(set) var launcherIsLaunchingAll: Bool = false
    @Published public private(set) var launcherLastError: String?
    @Published public private(set) var launcherLastLaunchSummary: String?

    public var oscRestBridge: OscRestBridgeService? {
        ledfxFeature.bridgeService
    }

    public var effectivePhase: Phase? { currentPhase ?? detectedSongPhase }
    
    // Shader Analysis State (public read, private write - controlled via analysis methods)
    @Published public private(set) var isAnalyzingShaders: Bool = false
    @Published public private(set) var analysisProgress: Double = 0
    @Published public private(set) var analysisCurrent: Int = 0
    @Published public private(set) var analysisTotal: Int = 0
    @Published public private(set) var currentAnalysisShader: String? = nil
    @Published public private(set) var analysisSuccessCount: Int = 0
    @Published public private(set) var analysisBlackCount: Int = 0
    @Published public private(set) var analysisErrorCount: Int = 0
    @Published public private(set) var analysisCancelled: Bool = false

    private var vdjQueryTask: Task<Void, Never>?
    private var lastLaunchpadRevision: UInt64 = 0
    private var lastLauncherRevision: UInt64 = 0
    private var lastLedfxRevision: UInt64 = 0
    private var lastMappedLogCount: Int = 0
    private var lastMappedLogTimestamp: Date?

    // MARK: - Store Logger (Debug)

    /// Action logger for debugging state changes - access via appState.storeLogger
    public let storeLogger = StoreLogger<SwiftVJCore.AppState, AppAction>()

    // MARK: - Init

    public convenience init() {
        self.init(testMode: false)
    }

    public init(testMode: Bool) {
        self.isTestMode = testMode
        // Create store with logging wrapper for state change insights
        self.store = Store(
            initialState: SwiftVJCore.AppState(),
            reducer: storeLogger.wrap(reducer: appReducer)
        )
        self.ledfxFeature = LedFXFeature(
            store: store,
            oscHub: oscHub,
            isTestMode: testMode,
            log: { [store] message, level in
                let mapped: LogLevelState = switch level {
                case .debug: .debug
                case .info: .info
                case .warning: .warning
                case .error: .error
                }
                store.send(.ui(.log(message, mapped)))
            }
        )

        // Configure logger: opt-in for regular debug runs to avoid reducer overhead.
        let loggerEnabled = ProcessInfo.processInfo.environment["SWIFTVJ_STORE_LOGGER"] == "1"
        storeLogger.isEnabled = loggerEnabled
        storeLogger.printToConsole = loggerEnabled
        storeLogger.excludedCategories = [.audio]
        storeLogger.filterHighFrequency()

        if !testMode {
            setupModules()
            setupRenderEngine()
            setupEffectEnvironment()
            startOSCHub()
        }
        setupStoreObservation()
        if !testMode {
            store.send(.loadPersistedState)
            ledfxFeature.seedDefaultsInStore()
        }
    }

    deinit {
        // LedFX feature owns its own async tasks
    }

    // MARK: - Actions

    public func send(_ action: AppAction) {
        store.send(action)
    }

    public func togglePipelineStepExpansion(_ stepName: String) {
        store.send(.pipeline(.toggleStepExpansion(stepName)))
    }

    // MARK: - Public API

    public func start() async throws {
        // Wire module dispatchers for unidirectional data flow
        await wireModuleDispatchers()

        // Start modules
        try await playbackModule?.start()

        let source: PlaybackSourceType = playbackSource == "vdj" ? .vdj : .spotify
        await playbackModule?.setSource(source)

        if source == .vdj {
            await setupVDJSubscriptionsAndQueries()
            log("VDJ subscribed", level: .info)
        }

        try await pipelineModule?.start()
        try await songsModule?.start()

        // Update store state
        store.send(.startup)

        if let backend = await aiModule?.backendInfo { log("AI: \(backend)", level: .info) }
        if let count = await shadersModule?.shaderCount {
            store.send(.render(.shaderCountUpdated(count)))
            log("Shaders: \(count) loaded", level: .info)
        }
        if let sources = await imagesModule?.availableSources { log("Images: \(sources)", level: .info) }
        log("Pipeline started", level: .info)

        try? await Task.sleep(for: .milliseconds(1000))
        await playbackModule?.poll()

        // Always-on LedFX integration (OSC → REST bridge)
        ledfxFeature.startIntegrationFromDefaults()

        // Process initial track if available
        if let track = await playbackModule?.currentTrack {
            log("♪ \(track.artist) - \(track.title)", level: .info)
            await processTrackChange(track)
        }
    }

    /// Process track change - triggers pipeline
    private func processTrackChange(_ track: Track) async {
        if let pipeline = pipelineModule {
            let result = await pipeline.process(track: track)
            logPipelineResult(result)
            if result.imagesFound, !result.imagesFolder.isEmpty {
                loadImagesFromFolder(URL(fileURLWithPath: result.imagesFolder))
            }
        }
    }

    public func stop() async {
        vdjQueryTask?.cancel()
        vdjQueryTask = nil
        await playbackModule?.stop()
        await pipelineModule?.stop()
        await songsModule?.stop()
        store.send(.shutdown)
    }

    public func setPlaybackSource(_ source: String) async {
        store.send(.playback(.sourceChanged(source)))
        let sourceType: PlaybackSourceType = source == "vdj" ? .vdj : .spotify
        await playbackModule?.setSource(sourceType)
        vdjQueryTask?.cancel()
        vdjQueryTask = nil
        if sourceType == .vdj { await setupVDJSubscriptionsAndQueries() }
    }

    public func selectShader(_ name: String) {
        // Dispatch action through store - effects handle render engine + OSC via EffectEnvironment
        store.send(.render(.selectShader(name)))
    }

    public func selectMaskShader(_ name: String) {
        store.send(.render(.selectMaskShader(name)))
    }

    public func selectNextShader() {
        store.send(.render(.selectNextShader))
    }

    public func selectPreviousShader() {
        store.send(.render(.selectPreviousShader))
    }

    public func selectRandomShader() {
        store.send(.render(.selectRandomShader))
    }

    public func selectNextMaskShader() {
        store.send(.render(.selectNextMaskShader))
    }

    public func selectPreviousMaskShader() {
        store.send(.render(.selectPreviousMaskShader))
    }

    public func selectRandomMaskShader() {
        store.send(.render(.selectRandomMaskShader))
    }

    public func setRenderEnabled(_ enabled: Bool) {
        store.send(.render(.setEnabled(enabled)))
    }

    public func setRenderOutputEnabled(_ output: RenderOutput, enabled: Bool) {
        store.send(.render(.setOutputEnabled(output: output, enabled: enabled)))
    }

    public func isRenderOutputEnabled(_ output: RenderOutput) -> Bool {
        renderOutputs.isEnabled(output)
    }

    public func renderOutputBinding(_ output: RenderOutput) -> Binding<Bool> {
        Binding(
            get: { self.isRenderOutputEnabled(output) },
            set: { enabled in self.setRenderOutputEnabled(output, enabled: enabled) }
        )
    }

    public var renderEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.renderEnabled },
            set: { enabled in self.setRenderEnabled(enabled) }
        )
    }

    /// Set the current phase via unidirectional data flow.
    /// Dispatches through Store → Reducer → @Published sync.
    /// Do NOT write directly to currentPhase to avoid state trickling.
    public func setPhase(_ phase: Phase?) {
        store.send(.render(.selectPhase(phase)))
    }

#if DEBUG
    /// Test-only helper for UI tests to seed Launchpad state.
    public func setLaunchpadStatusForTesting(status: LaunchpadStatus?, state: ControllerState?) {
        launchpadStatus = status
        launchpadState = state
    }
#endif

    /// Type-safe binding for Phase pickers that enforces unidirectional flow.
    /// Use this instead of $currentPhase to prevent direct @Published writes.
    public var phaseBinding: Binding<Phase?> {
        Binding(
            get: { self.currentPhase },
            set: { newPhase in self.setPhase(newPhase) }
        )
    }

    // MARK: - LedFX Bindings

    public var ledfxVirtualIds: [String] {
        ledfxVirtualIdsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var ledfxSlotIdsForPaths: [String] {
        if let config = ledfxGeneratedConfig, !config.slots.isEmpty {
            return config.slots.keys.sorted()
        }
        if !ledfxVirtualIds.isEmpty {
            return ledfxVirtualIds.indices.map { String($0) }
        }
        return ["0"]
    }

    public var ledfxBaseURLBinding: Binding<String> {
        Binding(
            get: { self.ledfxBaseURL },
            set: { newValue in
                self.send(.ledfx(.setBaseURL(newValue)))
            }
        )
    }

    public var ledfxVirtualIdsBinding: Binding<String> {
        Binding(
            get: { self.ledfxVirtualIdsString },
            set: { newValue in
                self.send(.ledfx(.setVirtualIds(newValue)))
            }
        )
    }

    public var ledfxSceneFilterBinding: Binding<String> {
        Binding(
            get: { self.ledfxSceneFilter },
            set: { newValue in
                self.send(.ledfx(.setSceneFilter(newValue)))
            }
        )
    }

    public var ledfxPlaylistFilterBinding: Binding<String> {
        Binding(
            get: { self.ledfxPlaylistFilter },
            set: { newValue in
                self.send(.ledfx(.setPlaylistFilter(newValue)))
            }
        )
    }

    // MARK: - OSC Debug State Methods

    /// Set OSC filter through Store → Reducer → @Published sync.
    public func setOscFilter(_ filter: String) {
        store.send(.ui(.setOscFilter(filter)))
    }

    /// Type-safe binding for OSC filter TextField.
    public var oscFilterBinding: Binding<String> {
        Binding(
            get: { self.oscFilter },
            set: { newFilter in self.setOscFilter(newFilter) }
        )
    }

    /// Set OSC debug enabled through Store.
    public func setOscDebugEnabled(_ enabled: Bool) {
        store.send(.ui(.setOscDebugEnabled(enabled)))
    }

    /// Type-safe binding for OSC debug toggle.
    public var oscDebugEnabledBinding: Binding<Bool> {
        Binding(
            get: { self.oscDebugEnabled },
            set: { enabled in self.setOscDebugEnabled(enabled) }
        )
    }

    /// Clear OSC messages through Store.
    public func clearOscMessages() {
        store.send(.ui(.clearOscMessages))
    }

    /// Clear log entries.
    public func clearLogs() {
        store.send(.ui(.clearLogs))
    }

    // MARK: - Cache Management

    /// Clear lyrics cache for a specific song.
    public func clearLyricsCache(artist: String, title: String) async {
        await lyricsFetcher?.clearCache(artist: artist, title: title)
        log("[Cache] Cleared lyrics cache for \(artist) - \(title)", level: .info)
    }

    /// Clear all lyrics cache.
    public func clearAllLyricsCache() async {
        await lyricsFetcher?.clearAllCache()
        log("[Cache] Cleared all lyrics cache", level: .info)
    }

    /// Clear all caches (lyrics, pipeline, songs database).
    public func clearAllCaches() async {
        // Lyrics cache
        await lyricsFetcher?.clearAllCache()
        // Pipeline cache
        await pipelineModule?.clearCache()
        // Songs database
        await songsModule?.clearAll()
        log("[Cache] Cleared all caches including songs database", level: .info)
    }

    // MARK: - Analysis State Methods

    /// Start shader analysis batch job.
    /// Analysis state is ephemeral (single async job) so methods mutate @Published directly.
    public func startAnalysis(shaderCount: Int) {
        isAnalyzingShaders = true
        analysisCancelled = false
        analysisProgress = 0
        analysisSuccessCount = 0
        analysisBlackCount = 0
        analysisErrorCount = 0
        analysisTotal = shaderCount
        analysisCurrent = 0
    }

    /// Cancel ongoing analysis.
    public func cancelAnalysis() {
        analysisCancelled = true
    }

    /// Update analysis progress during batch job.
    public func updateAnalysisProgress(current: Int, shaderName: String) {
        analysisCurrent = current
        currentAnalysisShader = shaderName
        analysisProgress = analysisTotal > 0 ? Double(current) / Double(analysisTotal) : 0
    }

    /// Update just the progress bar (0.0 to 1.0).
    public func setAnalysisProgress(_ progress: Double) {
        analysisProgress = progress
    }

    /// Set analysis counts directly (for complex update patterns).
    public func setAnalysisCounts(success: Int? = nil, black: Int? = nil, error: Int? = nil) {
        if let s = success { analysisSuccessCount = s }
        if let b = black { analysisBlackCount = b }
        if let e = error { analysisErrorCount = e }
    }

    /// Finish analysis batch job.
    public func finishAnalysis() {
        isAnalyzingShaders = false
        currentAnalysisShader = nil
    }

    // MARK: - Image Management

    public func loadImagesFromFolder(_ url: URL) {
        Task { @MainActor [weak self] in
            let imageFiles = await Task.detached(priority: .userInitiated) {
                Self.scanImageFolder(url)
            }.value
            guard let self = self else { return }
            if imageFiles.isEmpty {
                self.log("[Images] No images found", level: .warning)
                return
            }
            self.store.send(.render(.imagesLoaded(count: imageFiles.count, folderPath: url.path)))
        }
    }

    public func nextImage() {
        store.send(.render(.nextImage))
    }

    public func prevImage() {
        store.send(.render(.prevImage))
    }

    nonisolated private static func scanImageFolder(_ url: URL) -> [URL] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        return files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func loadImagesIntoRenderer(folderPath: String) async {
        let url = URL(fileURLWithPath: folderPath)
        let imageFiles = Self.scanImageFolder(url)
        guard !imageFiles.isEmpty else { return }
        await MainActor.run {
            guard let imageManager = self.renderEngine?.imageManager else { return }
            let currentCoverMode = imageManager.state.coverMode
            imageManager.state = ImageDisplayState(
                currentImageURL: imageFiles.first,
                nextImageURL: imageFiles.count > 1 ? imageFiles[1] : nil,
                crossfadeProgress: 0.0,
                isFading: false,
                coverMode: currentCoverMode,
                folderImages: imageFiles,
                folderIndex: 0,
                beatsPerChange: 8
            )
        }
    }

    private func setImageIndexInRenderer(_ index: Int) async {
        await MainActor.run {
            guard let imageManager = self.renderEngine?.imageManager else { return }
            let state = imageManager.state
            guard !state.folderImages.isEmpty else { return }
            let safeIndex = max(0, min(index, state.folderImages.count - 1))
            let nextIndex = (safeIndex + 1) % state.folderImages.count
            imageManager.state = ImageDisplayState(
                currentImageURL: state.folderImages[safeIndex],
                nextImageURL: state.folderImages[nextIndex],
                crossfadeProgress: 0.0,
                isFading: true,
                coverMode: state.coverMode,
                folderImages: state.folderImages,
                folderIndex: safeIndex,
                beatsPerChange: state.beatsPerChange
            )
        }
    }

    // MARK: - Logging

    public func log(_ message: String, level: LogLevel = .info) {
        store.send(.ui(.log(message, mapLogLevel(level))))
    }

    private func logRuntimeError(operation: String, error: Error) {
        log("[RuntimeError] \(operation): \(error)", level: .error)
    }

    public func recordOSCMessage(_ address: String, args: [String]) {
        store.send(.ui(.oscMessageReceived(address: address, args: args)))
    }

    private func mapLogLevel(_ level: LogLevel) -> LogLevelState {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

    private func mapLogLevel(_ level: LogLevelState) -> LogLevel {
        switch level {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }

    private func mapLogEntry(_ entry: LogEntryState) -> LogEntry {
        LogEntry(
            message: entry.message,
            level: mapLogLevel(entry.level),
            timestamp: entry.timestamp
        )
    }

    private func mapOSCEntry(_ entry: OSCLogEntryState) -> OSCLogEntry {
        OSCLogEntry(
            address: entry.address,
            args: entry.args,
            timestamp: entry.timestamp
        )
    }

    // MARK: - Private Setup

    private func setupModules() {
        let fetcher = LyricsFetcher()
        self.lyricsFetcher = fetcher
        let shaderMatcher = ShaderMatcher()
        let projectImagesDir = URL(fileURLWithPath: "/Users/abossard/Desktop/projects/synesthesia-visuals/data/song_images")
        let imageScraper = ImageScraper(cacheDir: projectImagesDir)
        let llm = LLMClient()
        self.llmClient = llm

        playbackModule = PlaybackModule(oscHub: oscHub)
        lyricsModule = LyricsModule(fetcher: fetcher)
        aiModule = AIModule(llmClient: llm)
        shadersModule = ShadersModule(matcher: shaderMatcher)
        imagesModule = ImagesModule(scraper: imageScraper)

        let launchpadOscSender = makeLaunchpadOscSender(oscHub: oscHub) { [weak self] message in
            Task { @MainActor in
                self?.log(message, level: .error)
            }
        }
        launchpadModule = LaunchpadModule(oscSender: launchpadOscSender)
        launchpadConfig = launchpadModule?.yamlConfig
        if let launchpadModule {
            launchpadGateway = LaunchpadGateway(module: launchpadModule)
        }
        launcherGateway = AppLauncherGateway()

        // Module dispatch sink - always hop to main actor before touching Store
        launchpadModule?.dispatch = makeLaunchpadDispatchSink { [weak self] action in
            self?.store.send(action)
        }

        for pattern in ["/scenes/*", "/presets/*", "/favslots/*", "/playlist/*", "/controls/meta/*", "/controls/global/*"] {
            oscHub.subscribe(pattern: pattern) { [weak self] address, values in
                let args: [OscArg] = values.compactMap { value in
                    if let v = value as? Int32 { return .int(Int(v)) }
                    if let v = value as? Float32 { return .float(Float(v)) }
                    if let v = value as? String { return .string(v) }
                    if let v = value as? Bool { return .bool(v) }
                    return nil
                }
                let event = OscEvent(address: address, args: args)
                Task { @MainActor in
                    self?.store.send(.launchpad(.oscEventReceived(event)))
                }
            }
        }

        pipelineModule = PipelineModule(
            lyricsModule: lyricsModule!,
            aiModule: aiModule!,
            shadersModule: shadersModule,
            imagesModule: imagesModule,
            oscHub: oscHub
        )

        songsModule = SongsModule()
    }

    private func wireModuleDispatchers() async {
        // Wire playback module to dispatch actions to store
        await playbackModule?.setDispatch { [weak self] action in
            guard let self else { return }
            await MainActor.run {
                self.store.send(action)
            }
        }

        // Wire pipeline module to dispatch actions to store
        await pipelineModule?.setDispatch { [weak self] action in
            guard let self else { return }
            await MainActor.run {
                self.store.send(action)
            }
        }
    }

    private func setupRenderEngine() {
        Task { [weak self] in
            guard let self = self else { return }
            let engine = await RenderEngine.create(synesthesiaAudio: self.synesthesiaAudio)
            await MainActor.run {
                self.renderEngine = engine
                if let shadersDir = ShaderDirectoryLocator.resolve(
                    customPath: UserDefaults.standard.string(forKey: "shaderDirectory")
                ) {
                    engine.shaderRepository.configure(metallibURL: nil, shadersDirectory: shadersDir)
                }
                engine.shaderManager.logger = { [weak self] message, coreLevel in
                    // Convert SwiftVJCore.LogLevel to SwiftVJApp.LogLevel
                    let level: LogLevel = switch coreLevel {
                    case .debug: .debug
                    case .info: .info
                    case .warning: .warning
                    case .error: .error
                    }
                    self?.log(message, level: level)
                }
            }

            // Keep shader navigation/select effects operational even when renderer is disabled.
            _ = await engine.shaderRepository.reload()
            self.applyInitialRenderSelections(using: engine)
            await MainActor.run {
                engine.setOutputState(self.store.state.render.outputs)
            }
            await self.applyRendererEnabledState(self.store.state.render.isEnabled)
        }
    }

    private func setupEffectEnvironment() {
        // Wire effect environment callbacks for UDF-compliant side effects
        EffectEnvironment.shared.loadShader = { [weak self] name in
            guard let self = self else { return }
            await MainActor.run {
                self.renderEngine?.shaderSelection.selectMain(name: name)
                do {
                    try self.oscHub.sendToMagic("/shader/load", values: [name, Float(0.5), Float(0.0)])
                } catch {
                    self.log("Failed to send shader to Magic: \(error)", level: .error)
                }
            }
        }

        EffectEnvironment.shared.loadMaskShader = { [weak self] name in
            guard let self = self else { return }
            await MainActor.run {
                self.renderEngine?.shaderSelection.selectMask(name: name)
            }
        }

        EffectEnvironment.shared.availableShaderNames = { [weak self] in
            await MainActor.run {
                self?.renderEngine?.shaderRepository.regularShaders.map(\.name) ?? []
            }
        }

        EffectEnvironment.shared.availableMaskShaderNames = { [weak self] in
            await MainActor.run {
                self?.renderEngine?.shaderRepository.masks.map(\.name) ?? []
            }
        }

        EffectEnvironment.shared.loadImagesFromFolder = { [weak self] folderPath in
            guard let self else { return }
            await self.loadImagesIntoRenderer(folderPath: folderPath)
        }

        EffectEnvironment.shared.setImageIndex = { [weak self] index in
            guard let self else { return }
            await self.setImageIndexInRenderer(index)
        }

        EffectEnvironment.shared.setRenderEnabled = { [weak self] enabled in
            guard let self else { return }
            await self.applyRendererEnabledState(enabled)
        }

        EffectEnvironment.shared.setRenderOutputEnabled = { [weak self] output, enabled in
            guard let self else { return }
            await MainActor.run {
                self.renderEngine?.setOutputEnabled(output, enabled: enabled)
            }
        }

        EffectEnvironment.shared.processPipelineTrack = { [weak self] track in
            guard let self = self else { return }
            await self.processTrackChange(track)
        }

        EffectEnvironment.shared.clearLyricsCache = { [weak self] artist, title in
            await self?.lyricsFetcher?.clearCache(artist: artist, title: title)
        }

        EffectEnvironment.shared.clearPipelineCache = { [weak self] artist, title in
            await self?.pipelineModule?.clearCacheForSong(artist: artist, title: title)
        }

        EffectEnvironment.shared.clearImagesCache = { [weak self] artist, title in
            await self?.imagesModule?.clearImagesForSong(artist: artist, title: title)
        }

        EffectEnvironment.shared.songsModule = songsModule
        EffectEnvironment.shared.currentPhaseProvider = { [weak self] in
            guard let self else { return nil }
            return await MainActor.run { self.currentPhase }
        }
        EffectEnvironment.shared.reloadLLMConfiguration = { [weak self] in
            guard let self else { return }
            await self.reloadLLMConfiguration()
        }

        EffectEnvironment.shared.ledfxActionHandler = { [weak self] action in
            guard let self else { return }
            await self.ledfxFeature.handle(action)
        }

        EffectEnvironment.shared.launchpadHandler = launchpadGateway
        EffectEnvironment.shared.launcherHandler = launcherGateway
    }

    private func reloadLLMConfiguration() async {
        guard let llmClient else { return }
        await llmClient.reloadConfiguration()
        await llmClient.start()
        let available = await llmClient.isAvailable
        if available {
            let backend = await llmClient.backendInfo
            log("Tachikoma config reloaded: \(backend)", level: .info)
        } else {
            let status = await llmClient.status()
            let error = status.error.isEmpty ? "unknown error" : status.error
            log("Tachikoma config reload failed: \(error)", level: .warning)
        }
    }

    private func startOSCHub() {
        do {
            try oscHub.start()
            log("OSC hub started on port \(oscHub.receivePort)", level: .info)

            oscHub.subscribe(pattern: "*") { [weak self] address, values in
                guard let self = self, self._oscDebugEnabledUnsafe else { return }
                let argsStr = values.map { "\($0)" }.joined(separator: ", ")
                Task { @MainActor in self.recordOSCMessage(address, args: [argsStr]) }
            }

            for pattern in ["/deck/*", "/vdj/*", "/crossfader"] {
                oscHub.subscribe(pattern: pattern) { [weak self] address, values in
                    guard let self = self else { return }
                    playbackOSCQueue.async {
                        Task { await self.playbackModule?.handleVDJOSC(address: address, values: values) }
                    }
                }
            }

            oscHub.subscribe(pattern: "/audio/*") { [weak self] address, values in
                self?.synesthesiaAudio.handleOSCFast(address, values)
            }

            oscHub.subscribe(pattern: "/image/folder") { [weak self] _, values in
                guard let folderPath = values.first as? String else { return }
                Task { @MainActor in self?.loadImagesFromFolder(URL(fileURLWithPath: folderPath)) }
            }

            oscHub.subscribe(pattern: "/render/enabled") { [weak self] _, values in
                guard
                    let value = values.first,
                    let enabled = Self.oscValueAsBool(value)
                else { return }
                Task { @MainActor in
                    self?.setRenderEnabled(enabled)
                }
            }
            
            ledfxFeature.registerOscSubscriptions()
        } catch {
            log("Failed to start OSC hub: \(error)", level: .error)
        }
    }

    private var lastTrackKey: String?

    private func setupStoreObservation() {
        store.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self else { return }

                // Track change logging - actual processing handled by Reducer effects
                let newTrackKey = newState.playback.currentTrack?.key
                if let track = newState.playback.currentTrack,
                   newTrackKey != self.lastTrackKey {
                    self.lastTrackKey = newTrackKey
                    self.log("♪ \(track.artist) - \(track.title)", level: .info)
                    if let engine = self.renderEngine {
                        engine.onTrackChange(artist: track.artist, title: track.title)
                    }
                    // Processing dispatched via EffectEnvironment in Reducer.trackChanged
                }

                // Sync @Published properties from store state for SwiftUI binding compatibility
                // Only update if changed to avoid unnecessary objectWillChange publishes
                if self.isRunning != newState.isRunning { self.isRunning = newState.isRunning }
                if self.currentTrack != newState.playback.currentTrack { self.currentTrack = newState.playback.currentTrack }
                if self.playbackPosition != newState.playback.position {
                    self.playbackPosition = newState.playback.position
                    // Feed position to KaraokeEngine for automatic line transitions
                    self.renderEngine?.onPlaybackPositionUpdate(newState.playback.position)
                }
                if self.isPlaying != newState.playback.isPlaying {
                    self.isPlaying = newState.playback.isPlaying
                    self.renderEngine?.onPlaybackStateChange(isPlaying: newState.playback.isPlaying)
                }
                if self.playbackSource != newState.playback.source { self.playbackSource = newState.playback.source }
                if self.renderEnabled != newState.render.isEnabled { self.renderEnabled = newState.render.isEnabled }
                if self.renderOutputs != newState.render.outputs { self.renderOutputs = newState.render.outputs }
                if self.selectedShader != newState.render.selectedShader { self.selectedShader = newState.render.selectedShader }
                if self.selectedMaskShader != newState.render.selectedMaskShader { self.selectedMaskShader = newState.render.selectedMaskShader }
                if self.currentPhase != newState.render.currentPhase { self.currentPhase = newState.render.currentPhase }
                if self.detectedSongPhase != newState.render.detectedSongPhase { self.detectedSongPhase = newState.render.detectedSongPhase }
                if self.imageIndex != newState.render.imageIndex { self.imageIndex = newState.render.imageIndex }
                if self.imageCount != newState.render.imageCount { self.imageCount = newState.render.imageCount }
                if self.shaderCount != newState.render.shaderCount { self.shaderCount = newState.render.shaderCount }
                if self.songsState != newState.songs { self.songsState = newState.songs }

                // UI state (logs + OSC)
                if self.oscFilter != newState.ui.oscFilter { self.oscFilter = newState.ui.oscFilter }
                if self.oscDebugEnabled != newState.ui.oscDebugEnabled { self.oscDebugEnabled = newState.ui.oscDebugEnabled }
                if self.oscMessageCount != newState.ui.oscMessageCount {
                    self.oscMessageCount = newState.ui.oscMessageCount
                    self.oscMessages = newState.ui.oscMessages.mapValues { self.mapOSCEntry($0) }
                }
                let rawLogEntries = newState.ui.logEntries
                let latestLogTimestamp = rawLogEntries.last?.timestamp
                if self.lastMappedLogCount != rawLogEntries.count ||
                    self.lastMappedLogTimestamp != latestLogTimestamp {
                    self.lastMappedLogCount = rawLogEntries.count
                    self.lastMappedLogTimestamp = latestLogTimestamp
                    self.logEntries = rawLogEntries.map(self.mapLogEntry)
                }

                // Launchpad state - only update if changed
                if let snapshot = newState.launchpad.status {
                    let newStatus = LaunchpadStatus(
                        isEnabled: snapshot.isConnected,
                        isConnected: snapshot.isConnected,
                        deviceName: snapshot.deviceName,
                        isLearnMode: snapshot.isLearnMode,
                        configuredPadCount: snapshot.padCount
                    )
                    if self.launchpadStatus != newStatus {
                        self.launchpadStatus = newStatus
                    }
                }
                if newState.launchpad.controllerState == nil {
                    self.lastLaunchpadRevision = 0
                    self.launchpadState = nil
                } else {
                    if self.lastLaunchpadRevision != newState.launchpad.controllerRevision {
                        self.lastLaunchpadRevision = newState.launchpad.controllerRevision
                        self.launchpadState = newState.launchpad.controllerState
                    }
                }

                // Launcher state
                let launcher = newState.launcher
                if self.lastLauncherRevision != launcher.revision {
                    self.lastLauncherRevision = launcher.revision
                    if self.launcherTargets != launcher.targets { self.launcherTargets = launcher.targets }
                    if self.launcherRunningTargetIDs != launcher.runningTargetIDs {
                        self.launcherRunningTargetIDs = launcher.runningTargetIDs
                    }
                    if self.launcherIsLaunchingAll != launcher.isLaunchingAll {
                        self.launcherIsLaunchingAll = launcher.isLaunchingAll
                    }
                    if self.launcherLastError != launcher.lastError { self.launcherLastError = launcher.lastError }
                    if self.launcherLastLaunchSummary != launcher.lastLaunchSummary {
                        self.launcherLastLaunchSummary = launcher.lastLaunchSummary
                    }
                }

                // LedFX state
                let ledfx = newState.ledfx
                if self.lastLedfxRevision != ledfx.revision {
                    self.lastLedfxRevision = ledfx.revision
                    if self.ledfxBaseURL != ledfx.baseURL { self.ledfxBaseURL = ledfx.baseURL }
                    if self.ledfxVirtualIdsString != ledfx.virtualIdsString { self.ledfxVirtualIdsString = ledfx.virtualIdsString }
                    if self.ledfxIsRefreshing != ledfx.isRefreshing { self.ledfxIsRefreshing = ledfx.isRefreshing }
                    if self.ledfxIsApplying != ledfx.isApplying { self.ledfxIsApplying = ledfx.isApplying }
                    if self.ledfxIsGeneratingConfig != ledfx.isGeneratingConfig { self.ledfxIsGeneratingConfig = ledfx.isGeneratingConfig }
                    if self.ledfxServerInfo != ledfx.serverInfo { self.ledfxServerInfo = ledfx.serverInfo }
                    if self.ledfxScenes != ledfx.scenes { self.ledfxScenes = ledfx.scenes }
                    if self.ledfxVirtuals != ledfx.virtuals { self.ledfxVirtuals = ledfx.virtuals }
                    if self.ledfxPlaylists != ledfx.playlists { self.ledfxPlaylists = ledfx.playlists }
                    if self.ledfxActivePlaylistId != ledfx.activePlaylistId { self.ledfxActivePlaylistId = ledfx.activePlaylistId }
                    if self.ledfxSceneFilter != ledfx.sceneFilter { self.ledfxSceneFilter = ledfx.sceneFilter }
                    if self.ledfxPlaylistFilter != ledfx.playlistFilter { self.ledfxPlaylistFilter = ledfx.playlistFilter }
                    if self.ledfxErrorMessage != ledfx.errorMessage { self.ledfxErrorMessage = ledfx.errorMessage }
                    if self.ledfxGeneratedYaml != ledfx.generatedYaml {
                        self.ledfxGeneratedYaml = ledfx.generatedYaml
                        if let yaml = ledfx.generatedYaml {
                            self.ledfxGeneratedConfig = try? ConfigLoader.load(from: yaml)
                        } else {
                            self.ledfxGeneratedConfig = nil
                        }
                    }
                    if self.ledfxPlaylistCount != ledfx.playlistCount { self.ledfxPlaylistCount = ledfx.playlistCount }
                    if self.ledfxEffectsCount != ledfx.effectsCount { self.ledfxEffectsCount = ledfx.effectsCount }
                    if self.ledfxIsRunning != ledfx.isRunning { self.ledfxIsRunning = ledfx.isRunning }
                    if self.ledfxHealthSummary != ledfx.healthSummary { self.ledfxHealthSummary = ledfx.healthSummary }
                    if self.ledfxLastHealthCheck != ledfx.lastHealthCheck { self.ledfxLastHealthCheck = ledfx.lastHealthCheck }
                }

                // Pipeline state - only update if changed
                let newSteps = self.mapPipelineSteps(from: newState.pipeline)
                if self.pipelineSteps != newSteps {
                    self.pipelineSteps = newSteps
                }
                if self.pipelineExpandedSteps != newState.pipeline.expandedStepNames {
                    self.pipelineExpandedSteps = newState.pipeline.expandedStepNames
                }
                if let result = newState.pipeline.result, self.pipelineResult != result {
                    self.pipelineResult = result
                    self.renderEngine?.onLyricsLoaded(
                        result.lyricsLines,
                        refrainLines: result.refrainLines
                    )
                }
            }
            .store(in: &cancellables)
    }

    private func mapPipelineSteps(from pipeline: PipelineSubState) -> [PipelineStep] {
        pipeline.steps.map { stepState in
            PipelineStep(
                name: stepState.name,
                status: stepState.status,
                details: stepState.details,
                timestamp: stepState.timestamp
            )
        }
    }

    private func applyInitialRenderSelections(using engine: RenderEngine) {
        let renderState = store.state.render
        let initialMain = renderState.selectedShader.flatMap { $0.isEmpty ? nil : $0 }
            ?? engine.shaderRepository.regularShaders.first?.name
            ?? "3isacrowd"
        let initialMask = renderState.selectedMaskShader.flatMap { $0.isEmpty ? nil : $0 }
            ?? engine.shaderRepository.masks.first?.name
            ?? "BWrevolvingswirl"
        engine.shaderSelection.selectMain(name: initialMain)
        engine.shaderSelection.selectMask(name: initialMask)
        store.send(.render(.selectShader(initialMain)))
        store.send(.render(.selectMaskShader(initialMask)))
    }

    private func applyRendererEnabledState(_ enabled: Bool) async {
        guard let engine = renderEngine else { return }

        if enabled {
            guard !engine.isRunning else { return }
            do {
                try await engine.start()
            } catch {
                log("[RenderEngine] Failed to start: \(error)", level: .error)
            }
            return
        }

        guard engine.isRunning else { return }
        await engine.stop()
    }

    nonisolated private static func oscValueAsBool(_ value: Any) -> Bool? {
        if let boolValue = value as? Bool { return boolValue }
        if let intValue = value as? Int32 { return intValue != 0 }
        if let intValue = value as? Int { return intValue != 0 }
        if let floatValue = value as? Float32 { return floatValue != 0 }
        if let floatValue = value as? Float { return floatValue != 0 }
        if let stringValue = value as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "on", "yes":
                return true
            case "0", "false", "off", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private func setupVDJSubscriptionsAndQueries() async {
        do {
            for deck in [1, 2] {
                for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength", "loaded"] {
                    try oscHub.sendToVDJ("/vdj/subscribe/deck/\(deck)/\(verb)")
                }
            }
            try oscHub.sendToVDJ("/vdj/subscribe/crossfader")
        } catch {
            logRuntimeError(operation: "VDJ subscription send", error: error)
        }

        vdjQueryTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch is CancellationError {
                    break
                } catch {
                    Task { @MainActor [weak self] in
                        self?.logRuntimeError(operation: "VDJ query loop sleep", error: error)
                    }
                    continue
                }
                guard let self = self else { break }
                let hub = await MainActor.run { self.oscHub }
                playbackOSCQueue.async { [weak self] in
                    do {
                        for deck in [1, 2] {
                            for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength", "song_pos", "play", "volume", "is_audible"] {
                                try hub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                            }
                        }
                    } catch {
                        Task { @MainActor in
                            self?.logRuntimeError(operation: "VDJ query send", error: error)
                        }
                    }
                }
            }
        }
    }

    private func logPipelineResult(_ result: PipelineResult) {
        log("Pipeline: \(result.totalTimeMs)ms - \(result.artist) - \(result.title)", level: .info)
        if result.lyricsFound { log("  Lyrics: \(result.lyricsLineCount) lines", level: .info) }
        log("  AI: \(result.mood) (E:\(String(format: "%.1f", result.energy)) V:\(String(format: "%.1f", result.valence)))", level: .info)
        if result.shaderMatched { log("  Shader: \(result.shaderName)", level: .info) }
        if result.imagesFound { log("  Images: \(result.imagesCount) files", level: .info) }
    }
}

// MARK: - Supporting Types

public struct PipelineStep: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let name: String
    public var status: String
    public var details: [String]?
    public var timestamp: Date

    public static func == (lhs: PipelineStep, rhs: PipelineStep) -> Bool {
        lhs.name == rhs.name && lhs.status == rhs.status && lhs.details == rhs.details
    }

    public static let defaultSteps: [PipelineStep] = [
        PipelineStep(name: "lyrics", status: "pending", details: nil, timestamp: Date()),
        PipelineStep(name: "ai", status: "pending", details: nil, timestamp: Date()),
        PipelineStep(name: "shaders", status: "pending", details: nil, timestamp: Date()),
        PipelineStep(name: "images", status: "pending", details: nil, timestamp: Date()),
        PipelineStep(name: "osc", status: "pending", details: nil, timestamp: Date())
    ]
}

public struct LogEntry: Identifiable {
    public let id = UUID()
    public let message: String
    public let level: LogLevel
    public let timestamp: Date
}

public enum LogLevel: String, CaseIterable, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"

    public var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}

public struct OSCLogEntry: Identifiable {
    public let id = UUID()
    public let address: String
    public let args: [String]
    public let timestamp: Date
}

// SwiftVJApp - SwiftUI macOS Application
// Phase 7: Unidirectional Data Flow Architecture

import SwiftUI
import SwiftVJCore
import Metal
import AppKit
import Combine
import OSCKit

// Serial queue to process high-rate playback OSC off the main actor
private let playbackOSCQueue = DispatchQueue(label: "vj.playback.osc.queue", qos: .userInitiated)

@main
struct SwiftVJApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

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

    // MARK: - Modules

    public let oscHub = OSCHub()
    public let settings = Settings()
    public var playbackModule: PlaybackModule?
    public var lyricsModule: LyricsModule?
    public var aiModule: AIModule?
    public var shadersModule: ShadersModule?
    public var imagesModule: ImagesModule?
    public var pipelineModule: PipelineModule?
    public var launchpadModule: LaunchpadModule?
    public var songsModule: SongsModule?
    public let synesthesiaAudio = SynesthesiaAudioProcessor()

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
    @Published public private(set) var timingOffsetMs: Int = 0
    @Published public private(set) var launchpadStatus: LaunchpadStatus?
    @Published public private(set) var launchpadState: ControllerState?
    @Published public private(set) var pipelineSteps: [PipelineStep] = []
    @Published public private(set) var pipelineResult: PipelineResult?
    @Published public private(set) var imageIndex: Int = 0
    @Published public private(set) var imageCount: Int = 0
    @Published public private(set) var shaderCount: Int = 0
    @Published public private(set) var selectedShader: String?
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

    private let maxLogEntries = 500
    private var vdjQueryTask: Task<Void, Never>?

    // MARK: - Store Logger (Debug)

    /// Action logger for debugging state changes - access via appState.storeLogger
    public let storeLogger = StoreLogger<SwiftVJCore.AppState, AppAction>()

    // MARK: - Init

    public init() {
        // Create store with logging wrapper for state change insights
        self.store = Store(
            initialState: SwiftVJCore.AppState(),
            reducer: storeLogger.wrap(reducer: appReducer)
        )

        // Configure logger: exclude noisy actions, async console output
        storeLogger.excludedCategories = [.audio]
        storeLogger.filterHighFrequency()

        setupModules()
        setupRenderEngine()
        setupEffectEnvironment()
        startOSCHub()
        startBPMSync()
        loadPersistedState()
        setupStoreObservation()
    }

    // MARK: - Actions

    public func send(_ action: AppAction) {
        store.send(action)
    }

    // MARK: - Public API

    public func start() async throws {
        // Wire module dispatchers for unidirectional data flow
        await wireModuleDispatchers()

        // Start modules
        try await playbackModule?.start()
        launchpadModule?.start()
        launchpadStatus = launchpadModule?.getStatus()

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
        launchpadModule?.stop()
        isRunning = false
        log("Pipeline stopped", level: .info)
    }

    public func setPlaybackSource(_ source: String) async {
        playbackSource = source
        UserDefaults.standard.set(source, forKey: "playbackSource")
        let sourceType: PlaybackSourceType = source == "vdj" ? .vdj : .spotify
        await playbackModule?.setSource(sourceType)
        vdjQueryTask?.cancel()
        vdjQueryTask = nil
        if sourceType == .vdj { await setupVDJSubscriptionsAndQueries() }
        log("Playback source: \(source)", level: .info)
    }

    public func adjustTiming(_ deltaMs: Int) {
        timingOffsetMs += deltaMs
        Task { _ = await settings.adjustTiming(by: deltaMs) }
        log("Timing offset: \(timingOffsetMs)ms", level: .info)
    }

    public func selectShader(_ name: String) {
        // Dispatch action through store - effects handle render engine + OSC via EffectEnvironment
        store.send(.render(.selectShader(name)))
    }

    /// Set the current phase via unidirectional data flow.
    /// Dispatches through Store → Reducer → @Published sync.
    /// Do NOT write directly to currentPhase to avoid state trickling.
    public func setPhase(_ phase: Phase?) {
        store.send(.render(.selectPhase(phase)))
    }

    /// Type-safe binding for Phase pickers that enforces unidirectional flow.
    /// Use this instead of $currentPhase to prevent direct @Published writes.
    public var phaseBinding: Binding<Phase?> {
        Binding(
            get: { self.currentPhase },
            set: { newPhase in self.setPhase(newPhase) }
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
        log("[Images] Loading from: \(url.lastPathComponent)", level: .info)
        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            log("[Images] Failed to read directory", level: .error)
            return
        }
        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        let imageFiles = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !imageFiles.isEmpty else {
            log("[Images] No images found", level: .warning)
            return
        }
        log("[Images] Found \(imageFiles.count) images", level: .info)
        imageIndex = 0
        imageCount = imageFiles.count
        if let imageManager = renderEngine?.imageManager {
            let currentCoverMode = imageManager.state.coverMode
            imageManager.state = ImageDisplayState(
                currentImageURL: imageFiles.first,
                nextImageURL: imageFiles.count > 1 ? imageFiles[1] : nil,
                crossfadeProgress: 0.0, isFading: false, coverMode: currentCoverMode,
                folderImages: imageFiles, folderIndex: 0, beatsPerChange: 8
            )
        }
    }

    public func nextImage() {
        guard let imageManager = renderEngine?.imageManager else { return }
        let state = imageManager.state
        guard !state.folderImages.isEmpty else { return }
        let nextIdx = (state.folderIndex + 1) % state.folderImages.count
        imageManager.state = ImageDisplayState(
            currentImageURL: state.folderImages[nextIdx],
            nextImageURL: state.folderImages[(nextIdx + 1) % state.folderImages.count],
            crossfadeProgress: 0.0, isFading: true, coverMode: state.coverMode,
            folderImages: state.folderImages, folderIndex: nextIdx, beatsPerChange: state.beatsPerChange
        )
        imageIndex = nextIdx
    }

    public func prevImage() {
        guard let imageManager = renderEngine?.imageManager else { return }
        let state = imageManager.state
        guard !state.folderImages.isEmpty else { return }
        let prevIdx = (state.folderIndex - 1 + state.folderImages.count) % state.folderImages.count
        imageManager.state = ImageDisplayState(
            currentImageURL: state.folderImages[prevIdx],
            nextImageURL: state.folderImages[(prevIdx + 1) % state.folderImages.count],
            crossfadeProgress: 0.0, isFading: true, coverMode: state.coverMode,
            folderImages: state.folderImages, folderIndex: prevIdx, beatsPerChange: state.beatsPerChange
        )
        imageIndex = prevIdx
    }

    // MARK: - Logging

    public func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(message: message, level: level, timestamp: Date())
        logEntries.append(entry)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }

    public func recordOSCMessage(_ address: String, args: [String]) {
        guard oscDebugEnabled else { return }
        guard oscFilter.isEmpty || address.localizedCaseInsensitiveContains(oscFilter) else { return }
        oscMessages[address] = OSCLogEntry(address: address, args: args, timestamp: Date())
        oscMessageCount += 1
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

        launchpadModule = LaunchpadModule(oscSender: { [weak self] command in
            guard let self = self else { return }
            let values: [any OSCValue] = command.args.map { arg -> any OSCValue in
                switch arg {
                case .int(let v): return Int32(v)
                case .float(let v): return Float32(v)
                case .string(let v): return v
                case .bool(let v): return v ? Int32(1) : Int32(0)
                }
            }
            try? self.oscHub.sendToSynesthesia(command.address, values: values)
        })

        // Wire up dispatch closures - modules send actions to Store
        launchpadModule?.dispatch = { [weak self] action in
            self?.store.send(action)
            // Also update full launchpadState for views that need detailed state
            if case .launchpad(.stateUpdated(_)) = action {
                self?.launchpadState = self?.launchpadModule?.getFullState()
                self?.launchpadStatus = self?.launchpadModule?.getStatus()
            }
        }

        let lpModule = launchpadModule
        for pattern in ["/scenes/*", "/presets/*", "/favslots/*", "/playlist/*", "/controls/meta/*", "/controls/global/*"] {
            oscHub.subscribe(pattern: pattern) { address, values in
                guard let module = lpModule else { return }
                let args: [OscArg] = values.compactMap { value in
                    if let v = value as? Int32 { return .int(Int(v)) }
                    if let v = value as? Float32 { return .float(Float(v)) }
                    if let v = value as? String { return .string(v) }
                    if let v = value as? Bool { return .bool(v) }
                    return nil
                }
                module.receiveOscEvent(OscEvent(address: address, args: args))
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
            do { try await engine.start() } catch { print("[RenderEngine] Failed: \(error)") }
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
    }

    private func startOSCHub() {
        do {
            try oscHub.start()
            log("OSC hub started on port \(OSCHub.receivePort)", level: .info)

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
        } catch {
            log("Failed to start OSC hub: \(error)", level: .error)
        }
    }

    private func startBPMSync() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let (bpm, _, _) = await self.synesthesiaAudio.getBPM()
                if bpm > 0 { self.launchpadModule?.updateBpm(bpm) }
            }
        }
    }

    private func loadPersistedState() {
        playbackSource = UserDefaults.standard.string(forKey: "playbackSource") ?? "vdj"
        if let savedShader = UserDefaults.standard.string(forKey: "selectedShader") {
            selectedShader = savedShader
        }
        if let savedPhase = UserDefaults.standard.string(forKey: "currentPhase") {
            currentPhase = Phase.from(savedPhase)
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
                    // Processing dispatched via EffectEnvironment in Reducer.trackChanged
                }

                // Sync @Published properties from store state for SwiftUI binding compatibility
                // Only update if changed to avoid unnecessary objectWillChange publishes
                if self.isRunning != newState.isRunning { self.isRunning = newState.isRunning }
                if self.currentTrack != newState.playback.currentTrack { self.currentTrack = newState.playback.currentTrack }
                if self.playbackPosition != newState.playback.position { self.playbackPosition = newState.playback.position }
                if self.isPlaying != newState.playback.isPlaying {
                    self.isPlaying = newState.playback.isPlaying
                    if let engine = self.renderEngine, let track = newState.playback.currentTrack {
                        Task { @MainActor in
                            engine.textManager.setSongInfo(
                                artist: track.artist,
                                title: track.title,
                                album: track.album,
                                stayVisible: self.isPlaying
                            )
                        }
                    }
                }
                if self.playbackSource != newState.playback.source { self.playbackSource = newState.playback.source }
                if self.timingOffsetMs != newState.playback.timingOffsetMs { self.timingOffsetMs = newState.playback.timingOffsetMs }
                if self.selectedShader != newState.render.selectedShader { self.selectedShader = newState.render.selectedShader }
                if self.currentPhase != newState.render.currentPhase { self.currentPhase = newState.render.currentPhase }
                if self.detectedSongPhase != newState.render.detectedSongPhase { self.detectedSongPhase = newState.render.detectedSongPhase }
                if self.imageIndex != newState.render.imageIndex { self.imageIndex = newState.render.imageIndex }
                if self.imageCount != newState.render.imageCount { self.imageCount = newState.render.imageCount }
                if self.shaderCount != newState.render.shaderCount { self.shaderCount = newState.render.shaderCount }
                if self.songsState != newState.songs { self.songsState = newState.songs }

                // Launchpad state - only update if changed
                if let snapshot = newState.launchpad.status {
                    let newStatus = LaunchpadStatus(
                        isEnabled: snapshot.isConnected,
                        isConnected: snapshot.isConnected,
                        deviceName: snapshot.deviceName,
                        isLearnMode: false,
                        configuredPadCount: snapshot.padCount,
                        currentBpm: 120
                    )
                    if self.launchpadStatus != newStatus {
                        self.launchpadStatus = newStatus
                    }
                }

                // Pipeline state - only update if changed
                let newSteps = self.mapPipelineSteps(from: newState.pipeline)
                if self.pipelineSteps != newSteps {
                    self.pipelineSteps = newSteps
                }
                if let result = newState.pipeline.result, self.pipelineResult != result {
                    self.pipelineResult = result
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

    private func setupVDJSubscriptionsAndQueries() async {
        do {
            for deck in [1, 2] {
                for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength", "loaded"] {
                    try oscHub.sendToVDJ("/vdj/subscribe/deck/\(deck)/\(verb)")
                }
            }
            try oscHub.sendToVDJ("/vdj/subscribe/crossfader")
        } catch {
            log("Failed to send VDJ subscriptions: \(error)", level: .error)
        }

        vdjQueryTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self = self else { break }
                let hub = await MainActor.run { self.oscHub }
                playbackOSCQueue.async {
                    do {
                        for deck in [1, 2] {
                            for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength", "song_pos", "play", "volume", "is_audible"] {
                                try hub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                            }
                        }
                    } catch {}
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

public struct PipelineStep: Identifiable, Equatable {
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

public enum LogLevel: String, CaseIterable {
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

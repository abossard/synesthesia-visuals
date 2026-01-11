// AppStateV2.swift - Store-backed AppState with backward compatibility
// Phase 7: Unidirectional Data Flow Migration
//
// This class wraps the new Store architecture while maintaining backward
// compatibility with existing SwiftUI views that use @Published properties.

import SwiftUI
import SwiftVJCore
import Metal
import Combine
import OSCKit

// Serial queue to process high-rate playback OSC off the main actor
private let playbackOSCQueue = DispatchQueue(label: "vj.playback.osc.queue", qos: .userInitiated)

/// Store-backed application state.
///
/// This class provides:
/// - @Published properties for SwiftUI backward compatibility
/// - Store-based state management for new code
/// - Automatic synchronization between Store and @Published
@MainActor
public final class AppStateV2: ObservableObject {

    // MARK: - Store

    /// The underlying store for unidirectional data flow
    public let store: Store<AppState, AppAction>

    // MARK: - Modules (unchanged from original)

    public let oscHub = OSCHub()
    public let settings = Settings()
    public var playbackModule: PlaybackModule?
    public var lyricsModule: LyricsModule?
    public var aiModule: AIModule?
    public var shadersModule: ShadersModule?
    public var imagesModule: ImagesModule?
    public var pipelineModule: PipelineModule?
    public var launchpadModule: LaunchpadModule?

    /// Audio processing from Synesthesia OSC
    public let synesthesiaAudio = SynesthesiaAudioProcessor()

    // MARK: - Rendering Engine

    @Published public var renderEngine: RenderEngine?

    // MARK: - UI State (@Published for backward compatibility)
    // These sync with store.state automatically

    @Published public var isRunning = false
    @Published public var currentTrack: Track?
    @Published public var playbackPosition: Double = 0
    @Published public var isPlaying: Bool = false
    @Published public var playbackSource: String = UserDefaults.standard.string(forKey: "playbackSource") ?? "vdj"
    @Published public var timingOffsetMs: Int = 0

    // Launchpad State
    @Published public var launchpadStatus: LaunchpadStatus?
    @Published public var launchpadState: ControllerState?

    // Pipeline State
    @Published public var pipelineSteps: [PipelineStep] = []
    @Published public var pipelineResult: PipelineResult?

    // Image State
    @Published public var imageIndex: Int = 0
    @Published public var imageCount: Int = 0

    // OSC State
    @Published public var oscMessages: [String: OSCLogEntry] = [:]
    @Published public var oscMessageCount: Int = 0
    @Published public var oscFilter: String = ""
    @Published public var oscDebugEnabled: Bool = false {
        didSet { _oscDebugEnabledUnsafe = oscDebugEnabled }
    }
    nonisolated(unsafe) private var _oscDebugEnabledUnsafe: Bool = false

    // Shader State
    @Published public var shaderCount: Int = 0
    @Published public var selectedShader: String? {
        didSet {
            if let shader = selectedShader {
                UserDefaults.standard.set(shader, forKey: "selectedShader")
            }
            renderEngine?.shaderManager.selectShader(name: selectedShader ?? "")
        }
    }

    // Phase State
    @Published public var currentPhase: Phase? = nil {
        didSet {
            if let phase = currentPhase {
                UserDefaults.standard.set(phase.rawValue, forKey: "currentPhase")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentPhase")
            }
        }
    }
    @Published public var detectedSongPhase: Phase? = nil

    public var effectivePhase: Phase? {
        currentPhase ?? detectedSongPhase
    }

    // Log State
    @Published public var logEntries: [LogEntry] = []
    private let maxLogEntries = 500

    // MARK: - State Sync

    private var cancellables = Set<AnyCancellable>()

    // MARK: - VDJ Query Task

    private var vdjQueryTask: Task<Void, Never>?

    // MARK: - Init

    public init() {
        // Create store with initial state and reducer
        self.store = Store(
            initialState: AppState(),
            reducer: appReducer
        )

        // Setup modules
        setupModules()

        // Setup render engine
        setupRenderEngine()

        // Start OSC hub
        startOSCHub()

        // Start BPM sync
        startBPMSync()

        // Sync store state to @Published properties
        setupStoreSync()

        // Load persisted state
        loadPersistedState()
    }

    // MARK: - Store Actions (new way)

    /// Send an action to the store
    public func send(_ action: AppAction) {
        store.send(action)
    }

    // MARK: - Public API (backward compatible)

    public func start() async throws {
        // Register callbacks before starting modules
        let pipeline = pipelineModule

        await playbackModule?.onTrackChange { @Sendable [weak self] track in
            guard let self = self else { return }
            await MainActor.run { [weak self] in
                self?.currentTrack = track
                self?.log("♪ \(track.artist) - \(track.title)", level: .info)
            }

            if let pipeline = pipeline {
                let result = await pipeline.process(track: track)
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.pipelineResult = result
                    self.updatePipelineSteps(from: result)
                    self.logPipelineResult(result)
                    if result.imagesFound, !result.imagesFolder.isEmpty {
                        self.loadImagesFromFolder(URL(fileURLWithPath: result.imagesFolder))
                    }
                }
            }
        }

        await playbackModule?.onPositionUpdate { @Sendable [weak self] position, isPlaying in
            guard let self = self else { return }
            await MainActor.run { [weak self] in
                self?.playbackPosition = position
                self?.isPlaying = isPlaying
            }
        }

        try await playbackModule?.start()

        launchpadModule?.start()
        launchpadStatus = launchpadModule?.getStatus()

        await pipelineModule?.onStepStart { @Sendable [weak self] stepName in
            guard let self = self else { return }
            await MainActor.run {
                self.updatePipelineStep(stepName, status: "running", details: nil)
            }
        }

        await pipelineModule?.onStepComplete { @Sendable [weak self] stepName, stepStatus in
            guard let self = self else { return }
            await MainActor.run {
                self.updatePipelineStep(stepName, status: stepStatus.displayText, details: stepStatus.logDetails)
                if case .ai(_, _, _, let keywords, let themes) = stepStatus {
                    if !keywords.isEmpty {
                        self.log("  Keywords: \(keywords.joined(separator: ", "))", level: .info)
                    }
                    if !themes.isEmpty {
                        self.log("  Themes: \(themes.joined(separator: ", "))", level: .info)
                    }
                }
                if case .images(let count, let folder, _, _) = stepStatus, count > 0 {
                    self.log("  Images: \(count) → \(folder)", level: .info)
                }
            }
        }

        let source: PlaybackSourceType = playbackSource == "vdj" ? .vdj : .spotify
        await playbackModule?.setSource(source)

        if source == .vdj {
            await setupVDJSubscriptionsAndQueries()
            log("VDJ subscribed", level: .info)
        }

        try await pipelineModule?.start()
        isRunning = true

        if let backend = await aiModule?.backendInfo {
            log("AI: \(backend)", level: .info)
        }
        if let count = await shadersModule?.shaderCount {
            shaderCount = count
            log("Shaders: \(count) loaded", level: .info)
        }
        if let sources = await imagesModule?.availableSources {
            log("Images: \(sources)", level: .info)
        }
        log("Pipeline started", level: .info)

        try? await Task.sleep(for: .milliseconds(1000))
        await playbackModule?.poll()

        if let track = await playbackModule?.currentTrack {
            log("♪ \(track.artist) - \(track.title)", level: .info)
            currentTrack = track
            if let pipeline = pipelineModule {
                let result = await pipeline.process(track: track)
                await MainActor.run {
                    self.updatePipelineSteps(from: result)
                    self.pipelineResult = result
                    self.logPipelineResult(result)
                    if result.imagesFound, !result.imagesFolder.isEmpty {
                        self.loadImagesFromFolder(URL(fileURLWithPath: result.imagesFolder))
                    }
                }
            }
        }
    }

    public func stop() async {
        vdjQueryTask?.cancel()
        vdjQueryTask = nil
        await playbackModule?.stop()
        await pipelineModule?.stop()
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

        if sourceType == .vdj {
            await setupVDJSubscriptionsAndQueries()
        }

        log("Playback source: \(source)", level: .info)
    }

    public func adjustTiming(_ deltaMs: Int) {
        timingOffsetMs += deltaMs
        Task {
            _ = await settings.adjustTiming(by: deltaMs)
        }
        log("Timing offset: \(timingOffsetMs)ms", level: .info)
    }

    public func selectShader(_ name: String) async {
        selectedShader = name
        do {
            try oscHub.sendToMagic("/shader/load", values: [name, Float(0.5), Float(0.0)])
            log("Selected shader: \(name)", level: .info)
        } catch {
            log("Failed to send shader: \(error)", level: .error)
        }
    }

    // MARK: - Image Management

    public func loadImagesFromFolder(_ url: URL) {
        log("[Images] Loading from: \(url.lastPathComponent)", level: .info)

        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            log("[Images] Failed to read directory: \(url.path)", level: .error)
            return
        }

        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        let imageFiles = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !imageFiles.isEmpty else {
            log("[Images] No images found in folder", level: .warning)
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
                crossfadeProgress: 0.0,
                isFading: false,
                coverMode: currentCoverMode,
                folderImages: imageFiles,
                folderIndex: 0,
                beatsPerChange: 8
            )
            log("[Images] Loaded with 8-beat auto-cycle", level: .info)
        } else {
            log("[Images] ImageManager not available", level: .error)
        }
    }

    public func nextImage() {
        guard let imageManager = renderEngine?.imageManager else { return }
        let state = imageManager.state
        guard !state.folderImages.isEmpty else { return }

        let nextIndex = (state.folderIndex + 1) % state.folderImages.count
        let current = state.folderImages[nextIndex]
        let next = state.folderImages[(nextIndex + 1) % state.folderImages.count]

        imageManager.state = ImageDisplayState(
            currentImageURL: current,
            nextImageURL: next,
            crossfadeProgress: 0.0,
            isFading: true,
            coverMode: state.coverMode,
            folderImages: state.folderImages,
            folderIndex: nextIndex,
            beatsPerChange: state.beatsPerChange
        )
        imageIndex = nextIndex
    }

    public func prevImage() {
        guard let imageManager = renderEngine?.imageManager else { return }
        let state = imageManager.state
        guard !state.folderImages.isEmpty else { return }

        let prevIndex = (state.folderIndex - 1 + state.folderImages.count) % state.folderImages.count
        let current = state.folderImages[prevIndex]
        let next = state.folderImages[(prevIndex + 1) % state.folderImages.count]

        imageManager.state = ImageDisplayState(
            currentImageURL: current,
            nextImageURL: next,
            crossfadeProgress: 0.0,
            isFading: true,
            coverMode: state.coverMode,
            folderImages: state.folderImages,
            folderIndex: prevIndex,
            beatsPerChange: state.beatsPerChange
        )
        imageIndex = prevIndex
    }

    public func setImageFitMode(_ cover: Bool) {
        guard let imageManager = renderEngine?.imageManager else { return }
        let state = imageManager.state
        imageManager.state = ImageDisplayState(
            currentImageURL: state.currentImageURL,
            nextImageURL: state.nextImageURL,
            crossfadeProgress: state.crossfadeProgress,
            isFading: state.isFading,
            coverMode: cover,
            folderImages: state.folderImages,
            folderIndex: state.folderIndex,
            beatsPerChange: state.beatsPerChange
        )
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
        let entry = OSCLogEntry(address: address, args: args, timestamp: Date())
        oscMessages[address] = entry
        oscMessageCount += 1
    }

    // MARK: - Private Setup

    private func setupModules() {
        let lyricsFetcher = LyricsFetcher()
        let shaderMatcher = ShaderMatcher()
        let projectImagesDir = URL(fileURLWithPath: "/Users/abossard/Desktop/projects/synesthesia-visuals/data/song_images")
        let imageScraper = ImageScraper(cacheDir: projectImagesDir)
        let llmClient = LLMClient()

        playbackModule = PlaybackModule(oscHub: oscHub)
        lyricsModule = LyricsModule(fetcher: lyricsFetcher)
        aiModule = AIModule(llmClient: llmClient)
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
            Task { @MainActor in
                self.recordOSCMessage(command.address, args: values.map { "\($0)" })
            }
        })

        launchpadModule?.onConnectionChange = { [weak self] connected, deviceName in
            Task { @MainActor in
                self?.launchpadStatus = self?.launchpadModule?.getStatus()
                self?.log("Launchpad: \(connected ? "Connected to \(deviceName ?? "device")" : "Disconnected")", level: .info)
            }
        }

        launchpadModule?.onStateChange = { [weak self] state in
            Task { @MainActor in
                self?.launchpadState = state
                self?.launchpadStatus = self?.launchpadModule?.getStatus()
            }
        }

        let lpModule = launchpadModule
        let launchpadPrefixes = ["/scenes/*", "/presets/*", "/favslots/*", "/playlist/*", "/controls/meta/*", "/controls/global/*"]
        for pattern in launchpadPrefixes {
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
    }

    private func setupRenderEngine() {
        Task { [weak self] in
            guard let self = self else { return }
            let engine = await RenderEngine.create(synesthesiaAudio: self.synesthesiaAudio)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.renderEngine = engine
                engine.shaderManager.logger = { [weak self] message, level in
                    self?.log(message, level: level)
                }
            }
            do {
                try await engine.start()
            } catch {
                print("[RenderEngine] Failed to auto-start: \(error)")
            }
        }
    }

    private func startOSCHub() {
        do {
            try oscHub.start()
            log("OSC hub started on port \(OSCHub.receivePort)", level: .info)

            oscHub.subscribe(pattern: "*") { [weak self] address, values in
                guard let self = self else { return }
                guard self._oscDebugEnabledUnsafe else { return }
                let argsStr = values.map { "\($0)" }.joined(separator: ", ")
                Task { @MainActor in
                    self.recordOSCMessage(address, args: [argsStr])
                }
            }

            oscHub.subscribe(pattern: "/deck/*") { [weak self] address, values in
                guard let self = self else { return }
                playbackOSCQueue.async { [weak self] in
                    guard let self = self else { return }
                    Task { await self.playbackModule?.handleVDJOSC(address: address, values: values) }
                }
            }

            oscHub.subscribe(pattern: "/vdj/*") { [weak self] address, values in
                guard let self = self else { return }
                playbackOSCQueue.async { [weak self] in
                    guard let self = self else { return }
                    Task { await self.playbackModule?.handleVDJOSC(address: address, values: values) }
                }
            }

            oscHub.subscribe(pattern: "/crossfader") { [weak self] address, values in
                guard let self = self else { return }
                playbackOSCQueue.async { [weak self] in
                    guard let self = self else { return }
                    Task { await self.playbackModule?.handleVDJOSC(address: address, values: values) }
                }
            }

            oscHub.subscribe(pattern: "/audio/*") { [weak self] address, values in
                guard let self = self else { return }
                self.synesthesiaAudio.handleOSCFast(address, values)
            }

            oscHub.subscribe(pattern: "/image/folder") { [weak self] _, values in
                guard let self = self, let folderPath = values.first as? String else { return }
                Task { @MainActor in
                    self.loadImagesFromFolder(URL(fileURLWithPath: folderPath))
                }
            }

            oscHub.subscribe(pattern: "/image/fit") { [weak self] _, values in
                guard let self = self, let mode = values.first as? String else { return }
                Task { @MainActor in
                    self.setImageFitMode(mode == "cover")
                }
            }
        } catch {
            log("Failed to start OSC hub: \(error)", level: .error)
        }
    }

    private func startBPMSync() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let (bpm, _, _) = await self.synesthesiaAudio.getBPM()
                if bpm > 0 {
                    self.launchpadModule?.updateBpm(bpm)
                }
            }
        }
    }

    private func setupStoreSync() {
        // Sync store state changes to @Published properties
        // This enables gradual migration while maintaining backward compatibility
        store.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                // Sync only if values differ to avoid loops
                if self.isRunning != state.isRunning { self.isRunning = state.isRunning }
            }
            .store(in: &cancellables)
    }

    private func loadPersistedState() {
        if let savedShader = UserDefaults.standard.string(forKey: "selectedShader") {
            selectedShader = savedShader
        }
        if let savedPhase = UserDefaults.standard.string(forKey: "currentPhase") {
            currentPhase = Phase.from(savedPhase)
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
            log("VDJ subscriptions sent", level: .info)
        } catch {
            log("Failed to send VDJ subscriptions: \(error)", level: .error)
        }

        await queryVDJState()

        vdjQueryTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self = self else { break }
                let hub = await MainActor.run(body: { self.oscHub })
                playbackOSCQueue.async {
                    do {
                        for deck in [1, 2] {
                            for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength"] {
                                try hub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                            }
                            for verb in ["song_pos", "play", "volume", "is_audible"] {
                                try hub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                            }
                        }
                    } catch { }
                }
            }
        }
    }

    private func queryVDJState() async {
        do {
            for deck in [1, 2] {
                for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength"] {
                    try oscHub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                }
                for verb in ["song_pos", "play", "volume", "is_audible"] {
                    try oscHub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                }
            }
        } catch { }
    }

    private func updatePipelineSteps(from result: PipelineResult) {
        pipelineSteps = [
            PipelineStep(name: "lyrics", status: result.lyricsFound ? "✓ \(result.lyricsLineCount) lines" : "✗ Not found", timestamp: Date()),
            PipelineStep(name: "ai", status: result.aiAvailable ? "✓ \(result.mood)" : "✗ Unavailable", timestamp: Date()),
            PipelineStep(name: "shaders", status: result.shaderMatched ? "✓ \(result.shaderName)" : "✗ No match", timestamp: Date()),
            PipelineStep(name: "images", status: result.imagesFound ? "✓ \(result.imagesCount) images" : "✗ None fetched", timestamp: Date()),
            PipelineStep(name: "osc", status: result.stepsCompleted.contains("osc") ? "✓ Sent" : "✗ Failed", timestamp: Date())
        ]
    }

    private func updatePipelineStep(_ step: String, status: String, details: [String]?) {
        if status == "running" && step == "lyrics" {
            pipelineSteps = [
                PipelineStep(name: "lyrics", status: "pending", details: nil, timestamp: Date()),
                PipelineStep(name: "ai", status: "pending", details: nil, timestamp: Date()),
                PipelineStep(name: "shaders", status: "pending", details: nil, timestamp: Date()),
                PipelineStep(name: "images", status: "pending", details: nil, timestamp: Date()),
                PipelineStep(name: "osc", status: "pending", details: nil, timestamp: Date())
            ]
        }

        if let index = pipelineSteps.firstIndex(where: { $0.name == step }) {
            pipelineSteps[index].status = status
            pipelineSteps[index].details = details
            pipelineSteps[index].timestamp = Date()
        } else {
            pipelineSteps.append(PipelineStep(name: step, status: status, details: details, timestamp: Date()))
        }
    }

    private func logPipelineResult(_ result: PipelineResult) {
        log("Pipeline: \(result.totalTimeMs)ms - \(result.artist) - \(result.title)", level: .info)
        if result.lyricsFound {
            log("  Lyrics: \(result.lyricsLineCount) lines, \(result.keywords.count) keywords", level: .info)
        }
        log("  AI: \(result.mood) (E:\(String(format: "%.1f", result.energy)) V:\(String(format: "%.1f", result.valence)))", level: .info)
        if result.shaderMatched {
            log("  Shader: \(result.shaderName) (\(Int(result.shaderScore * 100))%)", level: .info)
        }
        if result.imagesFound {
            log("  Images: \(result.imagesCount) files → \(result.imagesFolder)", level: .info)
        }
    }
}

// MARK: - Supporting Types (duplicated for backward compatibility)

public struct PipelineStep: Identifiable {
    public let id = UUID()
    public let name: String
    public var status: String
    public var details: [String]?
    public var timestamp: Date
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

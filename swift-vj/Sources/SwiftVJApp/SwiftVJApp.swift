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
    public let synesthesiaAudio = SynesthesiaAudioProcessor()

    // MARK: - Render Engine

    @Published public var renderEngine: RenderEngine?

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
    @Published public var logEntries: [LogEntry] = []
    @Published public var oscMessages: [String: OSCLogEntry] = [:]
    @Published public var oscMessageCount: Int = 0
    @Published public var oscFilter: String = ""
    @Published public var oscDebugEnabled: Bool = false {
        didSet { _oscDebugEnabledUnsafe = oscDebugEnabled }
    }
    nonisolated(unsafe) private var _oscDebugEnabledUnsafe: Bool = false

    public var effectivePhase: Phase? { currentPhase ?? detectedSongPhase }

    private let maxLogEntries = 500
    private var vdjQueryTask: Task<Void, Never>?

    // MARK: - Init

    public init() {
        self.store = Store(
            initialState: SwiftVJCore.AppState(),
            reducer: appReducer
        )
        setupModules()
        setupRenderEngine()
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
        let pipeline = pipelineModule

        // Register track change callback
        await playbackModule?.onTrackChange { @Sendable [weak self] track in
            guard let self = self else { return }
            await MainActor.run {
                self.currentTrack = track
                self.log("♪ \(track.artist) - \(track.title)", level: .info)
            }
            if let pipeline = pipeline {
                let result = await pipeline.process(track: track)
                await MainActor.run {
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
            await MainActor.run {
                self?.playbackPosition = position
                self?.isPlaying = isPlaying
            }
        }

        try await playbackModule?.start()
        launchpadModule?.start()
        launchpadStatus = launchpadModule?.getStatus()

        await pipelineModule?.onStepStart { @Sendable [weak self] stepName in
            await MainActor.run { self?.updatePipelineStep(stepName, status: "running", details: nil) }
        }

        await pipelineModule?.onStepComplete { @Sendable [weak self] stepName, stepStatus in
            await MainActor.run {
                self?.updatePipelineStep(stepName, status: stepStatus.displayText, details: stepStatus.logDetails)
                if case .ai(_, _, _, let keywords, let themes) = stepStatus {
                    if !keywords.isEmpty { self?.log("  Keywords: \(keywords.joined(separator: ", "))", level: .info) }
                    if !themes.isEmpty { self?.log("  Themes: \(themes.joined(separator: ", "))", level: .info) }
                }
                if case .images(let count, let folder, _, _) = stepStatus, count > 0 {
                    self?.log("  Images: \(count) → \(folder)", level: .info)
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

        if let backend = await aiModule?.backendInfo { log("AI: \(backend)", level: .info) }
        if let count = await shadersModule?.shaderCount {
            shaderCount = count
            log("Shaders: \(count) loaded", level: .info)
        }
        if let sources = await imagesModule?.availableSources { log("Images: \(sources)", level: .info) }
        log("Pipeline started", level: .info)

        try? await Task.sleep(for: .milliseconds(1000))
        await playbackModule?.poll()

        if let track = await playbackModule?.currentTrack {
            log("♪ \(track.artist) - \(track.title)", level: .info)
            currentTrack = track
            if let pipeline = pipelineModule {
                let result = await pipeline.process(track: track)
                updatePipelineSteps(from: result)
                pipelineResult = result
                logPipelineResult(result)
                if result.imagesFound, !result.imagesFolder.isEmpty {
                    loadImagesFromFolder(URL(fileURLWithPath: result.imagesFolder))
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
        if sourceType == .vdj { await setupVDJSubscriptionsAndQueries() }
        log("Playback source: \(source)", level: .info)
    }

    public func adjustTiming(_ deltaMs: Int) {
        timingOffsetMs += deltaMs
        Task { _ = await settings.adjustTiming(by: deltaMs) }
        log("Timing offset: \(timingOffsetMs)ms", level: .info)
    }

    public func selectShader(_ name: String) {
        selectedShader = name
        UserDefaults.standard.set(name, forKey: "selectedShader")
        renderEngine?.shaderManager.selectShader(name: name)
        do {
            try oscHub.sendToMagic("/shader/load", values: [name, Float(0.5), Float(0.0)])
            log("Selected shader: \(name)", level: .info)
        } catch {
            log("Failed to send shader: \(error)", level: .error)
        }
    }

    public func setPhase(_ phase: Phase?) {
        currentPhase = phase
        if let phase = phase {
            UserDefaults.standard.set(phase.rawValue, forKey: "currentPhase")
        } else {
            UserDefaults.standard.removeObject(forKey: "currentPhase")
        }
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
    }

    private func setupRenderEngine() {
        Task { [weak self] in
            guard let self = self else { return }
            let engine = await RenderEngine.create(synesthesiaAudio: self.synesthesiaAudio)
            await MainActor.run {
                self.renderEngine = engine
                engine.shaderManager.logger = { [weak self] message, level in
                    self?.log(message, level: level)
                }
            }
            do { try await engine.start() } catch { print("[RenderEngine] Failed: \(error)") }
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

    private func setupStoreObservation() {
        store.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Future: sync additional state from store if needed
            }
            .store(in: &cancellables)
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

    private func updatePipelineSteps(from result: PipelineResult) {
        pipelineSteps = [
            PipelineStep(name: "lyrics", status: result.lyricsFound ? "✓ \(result.lyricsLineCount) lines" : "✗ Not found", timestamp: Date()),
            PipelineStep(name: "ai", status: result.aiAvailable ? "✓ \(result.mood)" : "✗ Unavailable", timestamp: Date()),
            PipelineStep(name: "shaders", status: result.shaderMatched ? "✓ \(result.shaderName)" : "✗ No match", timestamp: Date()),
            PipelineStep(name: "images", status: result.imagesFound ? "✓ \(result.imagesCount) images" : "✗ None", timestamp: Date()),
            PipelineStep(name: "osc", status: result.stepsCompleted.contains("osc") ? "✓ Sent" : "✗ Failed", timestamp: Date())
        ]
    }

    private func updatePipelineStep(_ step: String, status: String, details: [String]?) {
        if status == "running" && step == "lyrics" {
            pipelineSteps = PipelineStep.defaultSteps
        }
        if let index = pipelineSteps.firstIndex(where: { $0.name == step }) {
            pipelineSteps[index].status = status
            pipelineSteps[index].details = details
            pipelineSteps[index].timestamp = Date()
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

public struct PipelineStep: Identifiable {
    public let id = UUID()
    public let name: String
    public var status: String
    public var details: [String]?
    public var timestamp: Date

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

// SwiftVJApp - SwiftUI macOS Application
// Phase 4: SwiftUI Shell for VJ Control
// Phase 6: Rendering Integration

import SwiftUI
import SwiftVJCore
import Metal
import AppKit
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

// MARK: - App Delegate for Window Management

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // CRITICAL: Set activation policy to regular (foreground GUI app)
        // Without this, SPM-built SwiftUI apps won't show windows
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure app is active and frontmost
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Force window creation and display
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApplication.shared.windows {
                window.makeKeyAndOrderFront(nil)
                window.center()
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - App State (Observable)

@MainActor
final class AppState: ObservableObject {
    // Modules
    let oscHub = OSCHub()
    let settings = Settings()
    var playbackModule: PlaybackModule?
    var lyricsModule: LyricsModule?
    var aiModule: AIModule?
    var shadersModule: ShadersModule?
    var imagesModule: ImagesModule?
    var pipelineModule: PipelineModule?
    var launchpadModule: LaunchpadModule?

    // Audio processing from Synesthesia OSC
    let synesthesiaAudio = SynesthesiaAudioProcessor()

    // Rendering Engine (Phase 6)
    @Published var renderEngine: RenderEngine?

    // UI State
    @Published var isRunning = false
    @Published var currentTrack: Track?
    @Published var playbackPosition: Double = 0
    @Published var isPlaying: Bool = false
    @Published var playbackSource: String = UserDefaults.standard.string(forKey: "playbackSource") ?? "vdj"
    @Published var timingOffsetMs: Int = 0
    
    // Launchpad State
    @Published var launchpadStatus: LaunchpadStatus?
    @Published var launchpadState: ControllerState?

    // Pipeline State
    @Published var pipelineSteps: [PipelineStep] = []
    @Published var pipelineResult: PipelineResult?

    // Image State (for UI binding)
    @Published var imageIndex: Int = 0
    @Published var imageCount: Int = 0

    // OSC State
    @Published var oscMessages: [String: OSCLogEntry] = [:]  // Grouped by address
    @Published var oscMessageCount: Int = 0
    @Published var oscFilter: String = ""  // Filter at capture time
    @Published var oscDebugEnabled: Bool = false {  // Only capture when OSC view is active
        didSet { _oscDebugEnabledUnsafe = oscDebugEnabled }
    }
    // Nonisolated mirror for high-frequency OSC callback (avoids 1000+ MainActor hops/sec)
    nonisolated(unsafe) private var _oscDebugEnabledUnsafe: Bool = false

    // Shader State
    @Published var shaderCount: Int = 0
    
    // Shader Analysis State (persists across navigation)
    @Published var isAnalyzingShaders: Bool = false
    @Published var analysisProgress: Double = 0
    @Published var analysisCurrent: Int = 0
    @Published var analysisTotal: Int = 0
    @Published var currentAnalysisShader: String = ""
    @Published var analysisSuccessCount: Int = 0
    @Published var analysisBlackCount: Int = 0
    @Published var analysisErrorCount: Int = 0
    @Published var analysisCancelled: Bool = false
    
    /// Single source of truth for current shader - all UI should use this
    /// Persisted to UserDefaults and syncs to render engine automatically
    @Published var selectedShader: String? {
        didSet {
            // Persist to UserDefaults
            if let shader = selectedShader {
                UserDefaults.standard.set(shader, forKey: "selectedShader")
            }
            // Sync to render engine
            renderEngine?.shaderManager.selectShader(name: selectedShader ?? "")
        }
    }

    // Phase State
    /// Current set phase - controlled by UI slider
    /// nil = auto (use detected song phase)
    @Published var currentPhase: Phase? = nil {
        didSet {
            if let phase = currentPhase {
                UserDefaults.standard.set(phase.rawValue, forKey: "currentPhase")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentPhase")
            }
        }
    }

    /// Detected phase from current song analysis (suggested by LLM)
    @Published var detectedSongPhase: Phase? = nil

    /// Effective phase = slider override or detected
    var effectivePhase: Phase? {
        currentPhase ?? detectedSongPhase
    }

    // Log State
    @Published var logEntries: [LogEntry] = []
    private let maxLogEntries = 500

    init() {
        setupModules()
        setupRenderEngine()
        startOSCHub()
        startBPMSync()

        // Load persisted shader selection (after render engine is ready)
        if let savedShader = UserDefaults.standard.string(forKey: "selectedShader") {
            selectedShader = savedShader
        }

        // Load persisted phase selection
        if let savedPhase = UserDefaults.standard.string(forKey: "currentPhase") {
            currentPhase = Phase.from(savedPhase)
        }
    }
    
    private func startBPMSync() {
        // Sync BPM every 5 seconds
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
    
    /// Start OSC hub immediately on app launch
    private func startOSCHub() {
        do {
            try oscHub.start()
            log("OSC hub started on port \(OSCHub.receivePort)", level: .info)
            
            // Debug: Log OSC messages (when oscDebugEnabled is true)
            // Audio messages are recorded but filtered in OSCDebugView display
            oscHub.subscribe(pattern: "*") { [weak self] address, values in
                guard let self = self else { return }
                // Check debug flag BEFORE creating Task to avoid 1000+ Task allocations/sec
                guard self._oscDebugEnabledUnsafe else { return }
                let argsStr = values.map { "\($0)" }.joined(separator: ", ")
                Task { @MainActor in
                    self.recordOSCMessage(address, args: [argsStr])
                }
            }
            
            // Wire VDJ OSC messages to VDJMonitor (no logging - use OSC view instead)
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
            
            // Wire Synesthesia audio OSC to audio processor and render engine
            // Uses nonisolated fast path for minimal overhead at 1000+ msg/sec
            oscHub.subscribe(pattern: "/audio/*") { [weak self] address, values in
                guard let self = self else { return }
                // FAST PATH: nonisolated accumulator, no await
                self.synesthesiaAudio.handleOSCFast(address, values)

                // NOTE: RenderEngine now pulls audio levels directly from synesthesiaAudio
                // in its render loop (60fps). We NO LONGER dispatch to MainActor here
                // to avoid flooding the main thread with 1000+ tasks/sec.
            }

            // Wire image folder OSC from pipeline to ImageRenderer
            oscHub.subscribe(pattern: "/image/folder") { [weak self] _, values in
                guard let self = self,
                      let folderPath = values.first as? String else { return }
                Task { @MainActor in
                    self.loadImagesFromFolder(URL(fileURLWithPath: folderPath))
                }
            }

            // Wire image fit mode OSC from pipeline
            oscHub.subscribe(pattern: "/image/fit") { [weak self] _, values in
                guard let self = self,
                      let mode = values.first as? String else { return }
                Task { @MainActor in
                    self.setImageFitMode(mode == "cover")
                }
            }
        } catch {
            log("Failed to start OSC hub: \(error)", level: .error)
        }
    }

    private func setupRenderEngine() {
        // Create render engine for VJUniverse visual output
        // Inject synesthesiaAudio processor so RenderEngine can pull levels in render loop
        // Auto-start on app launch
        Task { [weak self] in
            guard let self = self else { return }
            let engine = await RenderEngine.create(synesthesiaAudio: self.synesthesiaAudio)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.renderEngine = engine

                // Wire up shader state manager logger for UI visibility
                engine.shaderManager.logger = { [weak self] message, level in
                    self?.log(message, level: level)
                }
            }
            // Auto-start the render engine
            do {
                try await engine.start()
                print("[RenderEngine] Auto-started on app launch")
            } catch {
                print("[RenderEngine] Failed to auto-start: \(error)")
            }
        }
    }
    
    private func setupModules() {
        // Create adapters
        let lyricsFetcher = LyricsFetcher()
        let shaderMatcher = ShaderMatcher()

        // Store images in project folder instead of ~/Library/Application Support
        let projectImagesDir = URL(fileURLWithPath: "/Users/abossard/Desktop/projects/synesthesia-visuals/data/song_images")
        let imageScraper = ImageScraper(cacheDir: projectImagesDir)

        let llmClient = LLMClient()
        
        // Create modules - pass OSCHub to PlaybackModule for VDJ subscription
        playbackModule = PlaybackModule(oscHub: oscHub)
        lyricsModule = LyricsModule(fetcher: lyricsFetcher)
        aiModule = AIModule(llmClient: llmClient)
        shadersModule = ShadersModule(matcher: shaderMatcher)
        imagesModule = ImagesModule(scraper: imageScraper)
        
        // Launchpad Module
        launchpadModule = LaunchpadModule(oscSender: { [weak self] (command: OscCommand) -> Void in
            guard let self = self else { return }
            // Convert OscCommand to OSCKit values
            let values: [any OSCValue] = command.args.map { (arg: OscArg) -> any OSCValue in
                switch arg {
                case .int(let v): return Int32(v)
                case .float(let v): return Float32(v)
                case .string(let v): return v
                case .bool(let v): return v ? Int32(1) : Int32(0)
                }
            }
            
            // Send to Synesthesia (port 7777)
            try? self.oscHub.sendToSynesthesia(command.address, values: values)
            
            // Also log it
            Task { @MainActor in
                self.recordOSCMessage(command.address, args: values.map { "\($0)" })
            }
        })
        
        // Wire up Launchpad callbacks
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
        
        // Subscribe Launchpad only to Synesthesia control/selectable prefixes (ignore audio)
        // Capture the module reference to avoid main actor isolation issues
        let lpModule = launchpadModule
        let launchpadPrefixes = [
            "/scenes/*",
            "/presets/*",
            "/favslots/*",
            "/playlist/*",
            "/controls/meta/*",
            "/controls/global/*"
        ]
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
        
        // Pipeline
        pipelineModule = PipelineModule(
            lyricsModule: lyricsModule!,
            aiModule: aiModule!,
            shadersModule: shadersModule,
            imagesModule: imagesModule,
            oscHub: oscHub
        )
        
        // Track changes via playback module (registered in start())
    }
    
    // VDJ query task for periodic position updates
    private var vdjQueryTask: Task<Void, Never>?
    
    func start() async throws {
        // Capture references for Sendable closure (avoid capturing self)
        let pipeline = pipelineModule
        
        // Register track change callback BEFORE starting playback module
        // This ensures we don't miss the first track detection
        await playbackModule?.onTrackChange { @Sendable [weak self] track in
            guard let self = self else { return }
            
            // Update UI state on main thread
            await MainActor.run { [weak self] in
                self?.currentTrack = track
                self?.log("♪ \(track.artist) - \(track.title)", level: .info)
            }
            
            // Process through pipeline
            if let pipeline = pipeline {
                let result = await pipeline.process(track: track)
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.pipelineResult = result
                    self.updatePipelineSteps(from: result)
                    self.logPipelineResult(result)
                    // Load images directly from pipeline result
                    if result.imagesFound, !result.imagesFolder.isEmpty {
                        self.loadImagesFromFolder(URL(fileURLWithPath: result.imagesFolder))
                    }
                }
            }
        }
        
        // Register position update callback
        await playbackModule?.onPositionUpdate { @Sendable [weak self] position, isPlaying in
            guard let self = self else { return }
            await MainActor.run { [weak self] in
                self?.playbackPosition = position
                self?.isPlaying = isPlaying
            }
        }
        
        // NOW start playback module (after callbacks registered)
        try await playbackModule?.start()
        
        // Start Launchpad
        launchpadModule?.start()
        launchpadStatus = launchpadModule?.getStatus()
        
        // Register pipeline step callbacks for real-time UI updates (no logging - results logged at end)
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
                // Log detailed info for AI step (keywords, themes)
                if case .ai(_, _, _, let keywords, let themes) = stepStatus {
                    if !keywords.isEmpty {
                        self.log("  Keywords: \(keywords.joined(separator: ", "))", level: .info)
                    }
                    if !themes.isEmpty {
                        self.log("  Themes: \(themes.joined(separator: ", "))", level: .info)
                    }
                }
                // Log image folder for easy access
                if case .images(let count, let folder, _, _) = stepStatus, count > 0 {
                    self.log("  Images: \(count) → \(folder)", level: .info)
                }
            }
        }
        
        // Set initial source (this also triggers VDJ subscription)
        let source: PlaybackSourceType = playbackSource == "vdj" ? .vdj : .spotify
        await playbackModule?.setSource(source)
        
        // If VDJ, send subscriptions and start periodic queries
        if source == .vdj {
            await setupVDJSubscriptionsAndQueries()
            log("VDJ subscribed", level: .info)
        }
        
        try await pipelineModule?.start()
        isRunning = true
        
        // Log startup summary
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
        
        // Process current track immediately if one is already playing
        try? await Task.sleep(for: .milliseconds(1000))  // Give VDJ time to respond
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
                    // Load images directly from pipeline result
                    if result.imagesFound, !result.imagesFolder.isEmpty {
                        self.loadImagesFromFolder(URL(fileURLWithPath: result.imagesFolder))
                    }
                }
            }
        }
    }
    
    @MainActor
    private func updatePipelineSteps(from result: PipelineResult) {
        // Update pipeline steps from result
        // Differentiate between "not found" (ran but no results) vs "skipped" (didn't run)
        pipelineSteps = [
            PipelineStep(
                name: "lyrics",
                status: result.lyricsFound ? "✓ \(result.lyricsLineCount) lines" : "✗ Not found",
                timestamp: Date()
            ),
            PipelineStep(
                name: "ai",
                status: result.aiAvailable ? "✓ \(result.mood)" : "✗ Unavailable",
                timestamp: Date()
            ),
            PipelineStep(
                name: "shaders",
                status: result.shaderMatched ? "✓ \(result.shaderName)" : "✗ No match",
                timestamp: Date()
            ),
            PipelineStep(
                name: "images",
                status: result.imagesFound ? "✓ \(result.imagesCount) images" : "✗ None fetched",
                timestamp: Date()
            ),
            PipelineStep(
                name: "osc",
                status: result.stepsCompleted.contains("osc") ? "✓ Sent" : "✗ Failed",
                timestamp: Date()
            )
        ]
    }
    
    func stop() async {
        vdjQueryTask?.cancel()
        vdjQueryTask = nil
        await playbackModule?.stop()
        await pipelineModule?.stop()
        launchpadModule?.stop()
        isRunning = false
        log("Pipeline stopped", level: .info)
    }
    
    func setPlaybackSource(_ source: String) async {
        playbackSource = source
        UserDefaults.standard.set(source, forKey: "playbackSource")
        let sourceType: PlaybackSourceType = source == "vdj" ? .vdj : .spotify
        await playbackModule?.setSource(sourceType)
        
        // Stop existing VDJ query task
        vdjQueryTask?.cancel()
        vdjQueryTask = nil
        
        // If VDJ, setup subscriptions and queries
        if sourceType == .vdj {
            await setupVDJSubscriptionsAndQueries()
        }
        
        log("Playback source: \(source)", level: .info)
    }
    
    /// Setup VDJ subscriptions (track changes) and periodic queries (position updates)
    private func setupVDJSubscriptionsAndQueries() async {
        // Send subscription commands to VDJ for track change notifications
        do {
            // Subscriptions: VDJ pushes these on change
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
        
        // Initial query for current state
        await queryVDJState()
        
        // Start periodic query task for position updates
        vdjQueryTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self = self else { break }
                // Capture hub on main actor, then send on background queue
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
                    } catch {
                        // ignore transient VDJ errors
                    }
                }
            }
        }
    }
    
    /// Query VDJ for current deck state (metadata + position)
    private func queryVDJState() async {
        do {
            for deck in [1, 2] {
                // Query metadata (title, artist, etc.) - subscriptions only push on change
                for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength"] {
                    try oscHub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                }
                // Query playback state
                for verb in ["song_pos", "play", "volume", "is_audible"] {
                    try oscHub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                }
            }
        } catch {
            // Silently ignore query errors (VDJ may not be running)
        }
    }
    
    func adjustTiming(_ deltaMs: Int) {
        timingOffsetMs += deltaMs
        Task {
            _ = await settings.adjustTiming(by: deltaMs)
        }
        log("Timing offset: \(timingOffsetMs)ms", level: .info)
    }
    
    func selectShader(_ name: String) async {
        selectedShader = name
        // Send shader load command via OSC to Magic
        do {
            try oscHub.sendToMagic("/shader/load", values: [name, Float(0.5), Float(0.0)])
            log("Selected shader: \(name)", level: .info)
        } catch {
            log("Failed to send shader: \(error)", level: .error)
        }
    }

    // MARK: - Image Loading (from pipeline OSC)

    /// Load images from a folder path (called via /image/folder OSC)
    func loadImagesFromFolder(_ url: URL) {
        log("[Images] Loading from: \(url.lastPathComponent)", level: .info)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else {
            log("[Images] Failed to read directory: \(url.path)", level: .error)
            return
        }

        let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
        let imageFiles = files.filter { file in
            imageExtensions.contains(file.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !imageFiles.isEmpty else {
            log("[Images] No images found in folder", level: .warning)
            return
        }

        log("[Images] Found \(imageFiles.count) images", level: .info)

        // Update published state for UI binding
        imageIndex = 0
        imageCount = imageFiles.count

        // Update the imageManager state (which RenderEngine syncs to renderer each frame)
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
                beatsPerChange: 8  // Default to 8-beat auto-cycle
            )
            log("[Images] Loaded with 8-beat auto-cycle", level: .info)
        } else {
            log("[Images] ImageManager not available", level: .error)
        }
    }

    /// Navigate to next image
    func nextImage() {
        guard let imageManager = renderEngine?.imageManager else {
            log("[Images] nextImage: imageManager not available", level: .error)
            return
        }
        let state = imageManager.state
        guard !state.folderImages.isEmpty else {
            log("[Images] nextImage: no images loaded", level: .warning)
            return
        }

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
        log("[Images] → Next image: \(nextIndex + 1)/\(state.folderImages.count)", level: .debug)
    }

    /// Navigate to previous image
    func prevImage() {
        guard let imageManager = renderEngine?.imageManager else {
            log("[Images] prevImage: imageManager not available", level: .error)
            return
        }
        let state = imageManager.state
        guard !state.folderImages.isEmpty else {
            log("[Images] prevImage: no images loaded", level: .warning)
            return
        }

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
        log("[Images] ← Prev image: \(prevIndex + 1)/\(state.folderImages.count)", level: .debug)
    }

    /// Set image fit mode (called via /image/fit OSC)
    func setImageFitMode(_ cover: Bool) {
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

    // MARK: - Private
    
    private func updatePipelineStep(_ step: String, status: String, details: [String]?) {
        // If status is "running", we're starting a new pipeline - reset all steps to pending first
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
    
    func log(_ message: String, level: LogLevel = .info) {
        let entry = LogEntry(message: message, level: level, timestamp: Date())
        logEntries.append(entry)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }
    
    /// Log pipeline result summary with timing
    private func logPipelineResult(_ result: PipelineResult) {
        // Summary line with timing
        log("Pipeline: \(result.totalTimeMs)ms - \(result.artist) - \(result.title)", level: .info)
        
        // Lyrics
        if result.lyricsFound {
            log("  Lyrics: \(result.lyricsLineCount) lines, \(result.keywords.count) keywords", level: .info)
        } else {
            log("  Lyrics: not found", level: .debug)
        }
        
        // AI
        log("  AI: \(result.mood) (E:\(String(format: "%.1f", result.energy)) V:\(String(format: "%.1f", result.valence)))", level: .info)
        
        // Shader
        if result.shaderMatched {
            log("  Shader: \(result.shaderName) (\(Int(result.shaderScore * 100))%)", level: .info)
        } else {
            log("  Shader: no match", level: .debug)
        }
        
        // Images - show folder path for easy access
        if result.imagesFound {
            log("  Images: \(result.imagesCount) files → \(result.imagesFolder)", level: .info)
        } else {
            log("  Images: none", level: .debug)
        }
    }
    
    func recordOSCMessage(_ address: String, args: [String]) {
        // Only record when OSC debug view is active
        guard oscDebugEnabled else { return }
        
        // Filter at capture time - only record if filter is empty or address matches
        if !oscFilter.isEmpty && !address.localizedCaseInsensitiveContains(oscFilter) {
            return
        }
        let entry = OSCLogEntry(address: address, args: args, timestamp: Date())
        oscMessages[address] = entry  // Replace existing entry for this address
        oscMessageCount += 1
    }
}

// MARK: - Supporting Types

struct PipelineStep: Identifiable {
    let id = UUID()
    let name: String
    var status: String
    var details: [String]?  // Extra info for modal/hover
    var timestamp: Date
}

struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let level: LogLevel
    let timestamp: Date
}

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
    
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct OSCLogEntry: Identifiable {
    let id = UUID()
    let address: String
    let args: [String]
    let timestamp: Date
}

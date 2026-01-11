// AppStore.swift - Application store with environment and module management
// Bridges the Store with modules and provides dependency injection

import Foundation
import Combine

/// Application store that manages state, modules, and effects.
///
/// This is the main entry point for the unidirectional data flow architecture.
/// It wraps the generic Store with application-specific setup and module management.
@MainActor
public final class AppStore: ObservableObject {

    // MARK: - Store

    /// The underlying store
    public let store: Store<AppState, AppAction>

    /// Convenience accessor for current state
    public var state: AppState { store.state }

    // MARK: - Modules (kept for backward compatibility)

    public let oscHub: OSCHub
    public let settings: Settings
    public private(set) var playbackModule: PlaybackModule?
    public private(set) var lyricsModule: LyricsModule?
    public private(set) var aiModule: AIModule?
    public private(set) var shadersModule: ShadersModule?
    public private(set) var imagesModule: ImagesModule?
    public private(set) var pipelineModule: PipelineModule?
    public private(set) var launchpadModule: LaunchpadModule?
    public let synesthesiaAudio: SynesthesiaAudioProcessor

    // MARK: - State Subscriptions

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    public init() {
        // Create OSC hub and settings
        self.oscHub = OSCHub()
        self.settings = Settings()
        self.synesthesiaAudio = SynesthesiaAudioProcessor()

        // Create store with initial state and reducer
        self.store = Store(
            initialState: AppState(),
            reducer: appReducer
        )

        // Setup modules
        setupModules()

        // Start OSC hub
        startOSCHub()
    }

    // MARK: - Public API

    /// Send an action to the store
    public func send(_ action: AppAction) {
        store.send(action)
    }

    /// Start the VJ system
    public func start() async throws {
        send(.startup)

        // Setup module callbacks that dispatch to store
        await setupModuleCallbacks()

        // Start modules
        try await playbackModule?.start()
        launchpadModule?.start()
        try await pipelineModule?.start()

        // Update initial state
        if let count = await shadersModule?.shaderCount {
            send(.render(.shaderCountUpdated(count)))
        }

        // Poll for current track
        try? await Task.sleep(for: .milliseconds(500))
        await playbackModule?.poll()

        // Process current track if one is playing
        if let track = await playbackModule?.currentTrack {
            send(.playback(.trackChanged(track)))
            send(.pipeline(.startProcessing(track)))
        }

        send(.systemReady)
    }

    /// Stop the VJ system
    public func stop() async {
        send(.shutdown)
        await playbackModule?.stop()
        launchpadModule?.stop()
        await pipelineModule?.stop()
    }

    // MARK: - Convenience Methods (backward compatibility)

    /// Set playback source
    public func setPlaybackSource(_ source: String) {
        send(.playback(.sourceChanged(source)))
    }

    /// Select a shader
    public func selectShader(_ name: String) {
        send(.render(.selectShader(name)))
    }

    /// Adjust timing offset
    public func adjustTiming(_ deltaMs: Int) {
        let newOffset = state.playback.timingOffsetMs + deltaMs
        send(.playback(.timingOffsetChanged(newOffset)))
    }

    /// Navigate to next image
    public func nextImage() {
        send(.render(.nextImage))
    }

    /// Navigate to previous image
    public func prevImage() {
        send(.render(.prevImage))
    }

    /// Log a message
    public func log(_ message: String, level: LogLevelState = .info) {
        send(.ui(.log(message, level)))
    }

    // MARK: - Private Setup

    private func setupModules() {
        // Create adapters
        let lyricsFetcher = LyricsFetcher()
        let shaderMatcher = ShaderMatcher()
        let projectImagesDir = URL(fileURLWithPath: "/Users/abossard/Desktop/projects/synesthesia-visuals/data/song_images")
        let imageScraper = ImageScraper(cacheDir: projectImagesDir)
        let llmClient = LLMClient()

        // Create modules
        playbackModule = PlaybackModule(oscHub: oscHub)
        lyricsModule = LyricsModule(fetcher: lyricsFetcher)
        aiModule = AIModule(llmClient: llmClient)
        shadersModule = ShadersModule(matcher: shaderMatcher)
        imagesModule = ImagesModule(scraper: imageScraper)

        // Launchpad module with OSC sender
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

        // Pipeline module
        pipelineModule = PipelineModule(
            lyricsModule: lyricsModule!,
            aiModule: aiModule!,
            shadersModule: shadersModule,
            imagesModule: imagesModule,
            oscHub: oscHub
        )
    }

    private func startOSCHub() {
        do {
            try oscHub.start()
            log("OSC hub started on port \(OSCHub.receivePort)", level: .info)
            setupOSCSubscriptions()
        } catch {
            log("Failed to start OSC hub: \(error)", level: .error)
        }
    }

    private func setupOSCSubscriptions() {
        // VDJ messages
        oscHub.subscribe(pattern: "/deck/*") { [weak self] address, values in
            guard let self = self else { return }
            Task { await self.playbackModule?.handleVDJOSC(address: address, values: values) }
        }

        oscHub.subscribe(pattern: "/vdj/*") { [weak self] address, values in
            guard let self = self else { return }
            Task { await self.playbackModule?.handleVDJOSC(address: address, values: values) }
        }

        oscHub.subscribe(pattern: "/crossfader") { [weak self] address, values in
            guard let self = self else { return }
            Task { await self.playbackModule?.handleVDJOSC(address: address, values: values) }
        }

        // Audio messages (nonisolated fast path)
        oscHub.subscribe(pattern: "/audio/*") { [weak self] address, values in
            guard let self = self else { return }
            self.synesthesiaAudio.handleOSCFast(address, values)
        }

        // Image folder OSC
        oscHub.subscribe(pattern: "/image/folder") { [weak self] _, values in
            guard let self = self,
                  let folderPath = values.first as? String else { return }
            Task { @MainActor in
                self.send(.render(.imagesLoaded(count: 0, folderPath: folderPath)))
            }
        }

        // Launchpad OSC subscriptions
        let lpModule = launchpadModule
        let launchpadPrefixes = [
            "/scenes/*", "/presets/*", "/favslots/*", "/playlist/*",
            "/controls/meta/*", "/controls/global/*"
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
    }

    private func setupModuleCallbacks() async {
        // Playback callbacks
        await playbackModule?.onTrackChange { [weak self] track in
            guard let self = self else { return }
            await MainActor.run {
                self.send(.playback(.trackChanged(track)))
                self.send(.pipeline(.startProcessing(track)))
            }
        }

        await playbackModule?.onPositionUpdate { [weak self] position, isPlaying in
            guard let self = self else { return }
            await MainActor.run {
                self.send(.playback(.positionUpdated(position: position, isPlaying: isPlaying)))
            }
        }

        // Pipeline callbacks
        await pipelineModule?.onStepStart { [weak self] stepName in
            guard let self = self else { return }
            await MainActor.run {
                self.send(.pipeline(.stepStarted(stepName)))
            }
        }

        await pipelineModule?.onStepComplete { [weak self] stepName, status in
            guard let self = self else { return }
            await MainActor.run {
                self.send(.pipeline(.stepCompleted(stepName, status)))
            }
        }

        await pipelineModule?.onComplete { [weak self] result in
            guard let self = self else { return }
            await MainActor.run {
                self.send(.pipeline(.processingCompleted(result)))
            }
        }

        // Launchpad callbacks
        launchpadModule?.onConnectionChange = { [weak self] connected, deviceName in
            guard let self = self else { return }
            Task { @MainActor in
                if connected, let name = deviceName {
                    self.send(.launchpad(.connected(name)))
                } else {
                    self.send(.launchpad(.disconnected))
                }
            }
        }

        launchpadModule?.onStateChange = { [weak self] state in
            guard let self = self else { return }
            Task { @MainActor in
                self.send(.launchpad(.stateUpdated(ControllerStateSnapshot(from: state))))
            }
        }

        // VDJ setup
        if state.playback.source == "vdj" {
            await setupVDJSubscriptions()
        }
    }

    private func setupVDJSubscriptions() async {
        do {
            for deck in [1, 2] {
                for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength", "loaded"] {
                    try oscHub.sendToVDJ("/vdj/subscribe/deck/\(deck)/\(verb)")
                }
            }
            try oscHub.sendToVDJ("/vdj/subscribe/crossfader")
            log("VDJ subscribed", level: .info)
        } catch {
            log("Failed to send VDJ subscriptions: \(error)", level: .error)
        }

        // Start BPM sync timer
        startBPMSync()
    }

    private func startBPMSync() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                let (bpm, _, _) = await self.synesthesiaAudio.getBPM()
                if bpm > 0 {
                    self.launchpadModule?.updateBpm(bpm)
                }
            }
        }
    }
}

// MARK: - Combine Integration

extension AppStore {
    /// Publisher for state changes (for Combine integration)
    public var statePublisher: AnyPublisher<AppState, Never> {
        store.$state.eraseToAnyPublisher()
    }
}

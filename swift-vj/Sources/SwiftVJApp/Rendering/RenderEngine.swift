// RenderEngine.swift - Main rendering orchestrator for VJ system
// Pure CVDisplayLink-based rendering on a dedicated high-priority thread
// GPU work runs synchronously in the display link callback

import Foundation
import Metal
import MetalKit
import Combine
import SwiftUI
import CoreVideo
import os.lock
import SwiftVJCore

// MARK: - Render Frame Context

/// Snapshot of all state needed for one render frame
/// Gathered from MainActor state managers
struct RenderFrameContext: Sendable {
    let audioState: AudioState
    let shaderState: ShaderDisplayState
    let maskState: ShaderDisplayState
    let imageState: ImageDisplayState
}

// MARK: - Render Engine

/// Main rendering engine that orchestrates headless tile rendering and Syphon output
/// CVDisplayLink callback runs GPU work synchronously on a real-time thread
final class RenderEngine: ObservableObject, @unchecked Sendable {
    // MARK: - Published State (MainActor for SwiftUI)

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var fps: Double = 0
    @Published private(set) var frameCount: Int = 0

    // State managers (MainActor isolated for SwiftUI binding)
    @Published var audioManager: AudioStateManager
    @Published var imageManager: ImageStateManager

    /// Karaoke engine for automatic lyrics transitions based on timecodes
    @Published var karaokeEngine: KaraokeEngine
    /// Refrain engine (timecoded refrains only)
    @Published var refrainEngine: KaraokeEngine
    /// Song info engine (artist/title transitions)
    @Published var songInfoEngine: SongInfoEngine

    /// Single source of truth for all shader data
    @Published var shaderRepository: ObservableShaderRepository
    
    /// Selection state for main/mask outputs (reads from repository)
    @Published var shaderSelection: ShaderSelectionManager
    
    /// Legacy accessor - use shaderSelection instead
    var shaderManager: ShaderSelectionManager { shaderSelection }
    var maskManager: ShaderSelectionManager { shaderSelection }

    // Audio Processor (actor isolated, not MainActor)
    private var synesthesiaAudio: SynesthesiaAudioProcessor?
    
    // Logger closure for UI logging
    var logger: ((String) -> Void)?

    // MARK: - Render Thread State (accessed from CVDisplayLink thread)
    
    private var device: MTLDevice?
    private(set) var headlessRenderer: HeadlessRenderer?
    private var displayLink: CVDisplayLink?
    
    // Thread-safe Syphon manager (NOT MainActor)
    var syphonManager: SyphonOutputManager?
    
    // Cached state for render thread (updated via atomic swap)
    private let cachedContext = OSAllocatedUnfairLock<RenderFrameContext?>(initialState: nil)
    private let pendingShaderName = OSAllocatedUnfairLock<String?>(initialState: nil)
    private let pendingMaskName = OSAllocatedUnfairLock<String?>(initialState: nil)
    
    // FPS tracking (render thread only)
    private var lastFrameTime: CFAbsoluteTime = 0
    private var frameTimeAccum: Double = 0
    private var fpsUpdateCounter: Int = 0
    private var localFrameCount: Int = 0

    // MARK: - Init

    static func create(synesthesiaAudio: SynesthesiaAudioProcessor? = nil) async -> RenderEngine {
        let audioManager = await MainActor.run { AudioStateManager() }
        let imageManager = await MainActor.run { ImageStateManager() }
        let karaokeEngine = await MainActor.run { KaraokeEngine() }
        let refrainEngine = await MainActor.run { KaraokeEngine() }
        let songInfoEngine = await MainActor.run { SongInfoEngine() }

        // Create repository and selection manager with proper wiring
        let shaderRepository = await MainActor.run { ObservableShaderRepository() }
        let shaderSelection = await MainActor.run { ShaderSelectionManager() }
        await MainActor.run { shaderSelection.configure(repository: shaderRepository) }

        return RenderEngine(
            synesthesiaAudio: synesthesiaAudio,
            audioManager: audioManager,
            imageManager: imageManager,
            karaokeEngine: karaokeEngine,
            refrainEngine: refrainEngine,
            songInfoEngine: songInfoEngine,
            shaderRepository: shaderRepository,
            shaderSelection: shaderSelection
        )
    }

    private init(
        synesthesiaAudio: SynesthesiaAudioProcessor?,
        audioManager: AudioStateManager,
        imageManager: ImageStateManager,
        karaokeEngine: KaraokeEngine,
        refrainEngine: KaraokeEngine,
        songInfoEngine: SongInfoEngine,
        shaderRepository: ObservableShaderRepository,
        shaderSelection: ShaderSelectionManager
    ) {
        self.synesthesiaAudio = synesthesiaAudio
        self.audioManager = audioManager
        self.imageManager = imageManager
        self.karaokeEngine = karaokeEngine
        self.refrainEngine = refrainEngine
        self.songInfoEngine = songInfoEngine
        self.shaderRepository = shaderRepository
        self.shaderSelection = shaderSelection
    }

    // MARK: - Lifecycle

    @MainActor
    func start() async throws {
        guard !isRunning else { return }

        // Initialize Metal
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderEngineError.noMetalDevice
        }
        self.device = device

        // Create headless renderer
        let renderer = HeadlessRenderer(device: device, logger: logger)
        self.headlessRenderer = renderer
        logger?("[RenderEngine] Initialized headless renderer")
        
        // Initialize SwiftUI lyrics renderer on main thread
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            let lyricsRenderer = SwiftUITextTileRenderer(name: "swiftui-lyrics", device: device)
            let refrainRenderer = SwiftUITextTileRenderer(name: "swiftui-refrain", device: device)
            let songInfoRenderer = SwiftUITextTileRenderer(name: "swiftui-songinfo", device: device)
            renderer.setSwiftUITextRenderers(
                lyrics: lyricsRenderer,
                refrain: refrainRenderer,
                songInfo: songInfoRenderer
            )
            self.logger?("[RenderEngine] SwiftUI text renderers configured")
        }
        
        // Load shaders from repository
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            Task {
                await self.shaderRepository.reload()
                // Select default shaders after reload
                self.shaderSelection.selectMain(name: "3isacrowd")
                self.shaderSelection.selectMask(name: "BWrevolvingswirl")
            }
        }
        
        // Load default shaders in renderer
        renderer.shaderRenderer.loadShader(name: "3isacrowd")
        renderer.maskRenderer.loadShader(name: "BWrevolvingswirl")

        // Create thread-safe Syphon manager and start servers
        self.syphonManager = SyphonOutputManager.shared
        syphonManager?.createStandardServers()
        
        // Start MainActor managers
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.audioManager.start()
        }

        // Start render loop
        startRenderLoop()

        await MainActor.run { [weak self] in self?.isRunning = true }
        print("[RenderEngine] Started with CVDisplayLink rendering")
    }

    @MainActor
    func stop() async {
        guard isRunning else { return }

        stopRenderLoop()
        syphonManager?.stopAll()
        syphonManager = nil
        
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.audioManager.stop()
            self.isRunning = false
        }

        print("[RenderEngine] Stopped")
    }

    // MARK: - CVDisplayLink Render Loop

    private func startRenderLoop() {
        lastFrameTime = CFAbsoluteTimeGetCurrent()
        
        // Create CVDisplayLink
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        
        guard let link = link else {
            print("[RenderEngine] ❌ Failed to create CVDisplayLink")
            return
        }
        
        self.displayLink = link
        
        // CVDisplayLink callback - runs on high-priority real-time thread
        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo = userInfo else { return kCVReturnSuccess }
            let engine = Unmanaged<RenderEngine>.fromOpaque(userInfo).takeUnretainedValue()
            engine.renderFrameSync()
            return kCVReturnSuccess
        }
        
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, callback, userInfo)
        CVDisplayLinkStart(link)
        
        // Start state update task (runs async, pushes to cached state)
        startStateUpdateTask()
        
        print("[RenderEngine] CVDisplayLink started (vsync)")
    }
    
    private func stopRenderLoop() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
            self.displayLink = nil
        }
    }
    
    /// Async task that gathers state from MainActor and pushes to cache
    private func startStateUpdateTask() {
        Task { [weak self] in
            while let self = self, self.displayLink != nil {
                await self.updateCachedState()
                // Update at ~60Hz (slightly faster than display to stay ahead)
                try? await Task.sleep(for: .milliseconds(14))
            }
        }
    }
    
    /// Gather state from MainActor managers and cache for render thread
    private func updateCachedState() async {
        // Get audio from processor (actor, not MainActor)
        var audioLevels: OSCAudioLevels?
        var audioStats: (messageCount: Int, lastMessage: Date, isActive: Bool, messageRate: Int)?
        if let processor = synesthesiaAudio {
            audioLevels = await processor.getLevels()
            audioStats = await processor.stats
        }

        // Process audio off MainActor
        var processedAudioState: AudioState?
        if let levels = audioLevels {
            processedAudioState = await audioManager.processAudioOffMain(oscLevels: levels)
        }
        
        let capturedStats = audioStats
        let capturedAudioState = processedAudioState
        let shouldPublishFPS = fpsUpdateCounter >= 30

        // Single MainActor hop
        let context = await MainActor.run { [weak self] () -> RenderFrameContext? in
            guard let self = self else { return nil }

            if let audioState = capturedAudioState {
                self.audioManager.setStateDirectly(audioState)
            }

            if let stats = capturedStats {
                self.audioManager.updateStats(
                    messageRate: stats.messageRate,
                    messageCount: stats.messageCount,
                    isActive: stats.isActive
                )
            }

            if shouldPublishFPS {
                self.fps = Double(30) / self.frameTimeAccum
                self.frameTimeAccum = 0
                self.frameCount = self.localFrameCount
            }
            
            // Update SwiftUI lyrics renderer if enabled (runs on MainActor)
            if let renderer = self.headlessRenderer {
                if let swiftUIRenderer = renderer.getSwiftUILyricsRenderer() {
                    let hash = Self.buildKaraokeContentHash(
                        displayState: self.karaokeEngine.displayState,
                        configuration: self.karaokeEngine.configuration
                    )
                    let view = AnyView(KaraokeView(
                        displayState: self.karaokeEngine.displayState,
                        configuration: self.karaokeEngine.configuration
                    ))
                    swiftUIRenderer.update(contentHash: hash, view: view)
                }

                if let refrainRenderer = renderer.getSwiftUIRefrainRenderer() {
                    let hash = Self.buildKaraokeContentHash(
                        displayState: self.refrainEngine.displayState,
                        configuration: self.refrainEngine.configuration
                    )
                    let view = AnyView(KaraokeView(
                        displayState: self.refrainEngine.displayState,
                        configuration: self.refrainEngine.configuration
                    ))
                    refrainRenderer.update(contentHash: hash, view: view)
                }

                if let songInfoRenderer = renderer.getSwiftUISongInfoRenderer() {
                    let hash = Self.buildSongInfoContentHash(
                        displayState: self.songInfoEngine.displayState,
                        configuration: self.songInfoEngine.configuration
                    )
                    let view = AnyView(SongInfoView(
                        displayState: self.songInfoEngine.displayState,
                        configuration: self.songInfoEngine.configuration
                    ))
                    songInfoRenderer.update(contentHash: hash, view: view)
                }
            }

            return RenderFrameContext(
                audioState: self.audioManager.state,
                shaderState: self.shaderSelection.mainState,
                maskState: self.shaderSelection.maskState,
                imageState: self.imageManager.state
            )
        }
        
        guard let context = context else { return }
        
        // Atomically update cached state for render thread
        cachedContext.withLock { $0 = context }
        
        // Check for shader changes
        if let shaderName = context.shaderState.current?.name {
            pendingShaderName.withLock { $0 = shaderName }
        }
        if let maskName = context.maskState.current?.name {
            pendingMaskName.withLock { $0 = maskName }
        }
        
        if shouldPublishFPS {
            fpsUpdateCounter = 0
        }
    }

    /// Synchronous render called from CVDisplayLink thread
    /// This is the hot path - no async, no MainActor
    private func renderFrameSync() {
        guard let renderer = headlessRenderer else { return }
        
        // Get cached context
        guard let context = cachedContext.withLock({ $0 }) else { return }
        
        // Track frame timing
        let now = CFAbsoluteTimeGetCurrent()
        let deltaTime = now - lastFrameTime
        lastFrameTime = now
        frameTimeAccum += deltaTime
        fpsUpdateCounter += 1
        localFrameCount += 1
        
        // Update renderer state
        renderer.imageRenderer.imageState = context.imageState
        
        // Handle shader changes
        let currentShaderName = renderer.shaderRenderer.currentShaderName
        if let shaderName = pendingShaderName.withLock({ val -> String? in
            let current = val
            if current != currentShaderName {
                return current
            }
            return nil
        }) {
            renderer.shaderRenderer.loadShader(name: shaderName)
        }
        
        let currentMaskName = renderer.maskRenderer.currentShaderName
        if let maskName = pendingMaskName.withLock({ val -> String? in
            let current = val
            if current != currentMaskName {
                return current
            }
            return nil
        }) {
            renderer.maskRenderer.loadShader(name: maskName)
        }
        
        // Render all tiles + publish to Syphon (synchronous GPU work)
        renderer.renderFrame(
            audioState: context.audioState,
            syphonManager: syphonManager
        )
    }

    // MARK: - Convenience Methods

    /// Get texture for a specific tile (for debugging only - UI should use Syphon clients)
    func getTexture(for tileName: String) -> MTLTexture? {
        guard let renderer = headlessRenderer else { return nil }
        switch tileName {
        case "shader": return renderer.shaderRenderer.texture
        case "mask": return renderer.maskRenderer.texture
        case "lyrics": return renderer.lyricsTexture
        case "refrain": return renderer.refrainTexture
        case "songInfo": return renderer.songInfoTexture
        case "image": return renderer.imageRenderer.texture
        default: return nil
        }
    }

    /// Get all tile names
    func getTileNames() -> [String] {
        ["shader", "mask", "lyrics", "refrain", "songInfo", "image"]
    }

    // MARK: - SwiftUI Text Hashing

    private static func buildKaraokeContentHash(
        displayState: KaraokeDisplayState,
        configuration: KaraokeConfiguration
    ) -> String {
        let progressBucket = Int(displayState.transitionProgress * 60)
        let configSignature = karaokeConfigSignature(configuration)
        return "karaoke-\(displayState.currentLine ?? "")-\(displayState.nextLine ?? "")-\(displayState.activeIndex)-\(progressBucket)-\(configSignature)"
    }

    private static func karaokeConfigSignature(_ config: KaraokeConfiguration) -> String {
        func bucket(_ value: CGFloat) -> Int { Int(value * 100) }
        func bucket(_ value: Double) -> Int { Int(value * 100) }

        return [
            bucket(config.prevLineY),
            bucket(config.currentLineY),
            bucket(config.nextLineY),
            bucket(config.newNextEntryY),
            bucket(config.currentFontSize),
            bucket(config.nextFontSize),
            bucket(config.prevFontSize),
            bucket(config.currentLineOpacity),
            bucket(config.nextLineOpacity),
            bucket(config.prevLineOpacity),
            bucket(config.transitionDuration),
            bucket(config.prerollTime),
            bucket(config.textShadowRadius),
            bucket(config.textShadowOpacity),
            bucket(config.maxLineWidthRatio),
            config.easing.rawValue.hashValue,
            String(describing: config.fontWeight).hashValue,
            String(describing: config.fontDesign).hashValue,
            config.animationMode.rawValue.hashValue,
            bucket(config.canvasWidth),
            bucket(config.canvasHeight)
        ].map(String.init).joined(separator: "-")
    }

    private static func buildSongInfoContentHash(
        displayState: SongInfoDisplayState,
        configuration: SongInfoConfiguration
    ) -> String {
        func bucket(_ value: CGFloat) -> Int { Int(value * 100) }
        func bucket(_ value: Double) -> Int { Int(value * 100) }

        let configSignature = [
            bucket(configuration.artistY),
            bucket(configuration.titleY),
            bucket(configuration.artistFontSize),
            bucket(configuration.titleFontSize),
            bucket(configuration.transitionDuration),
            bucket(configuration.textShadowRadius),
            bucket(configuration.textShadowOpacity),
            bucket(configuration.maxLineWidthRatio),
            configuration.animationMode.rawValue.hashValue,
            String(describing: configuration.fontWeight).hashValue,
            String(describing: configuration.fontDesign).hashValue,
            bucket(configuration.canvasWidth),
            bucket(configuration.canvasHeight)
        ].map(String.init).joined(separator: "-")

        let progressBucket = Int(displayState.transitionProgress * 60)
        return "songinfo-\(displayState.artist)-\(displayState.title)-\(displayState.isVisible)-\(progressBucket)-\(configSignature)"
    }

    private static func resolveRefrainLines(
        lyrics: [LyricLine],
        refrainTexts: [String]
    ) -> [LyricLine] {
        guard !lyrics.isEmpty else { return [] }

        let normalize: (String) -> String = { text in
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .joined(separator: "")
        }

        let normalizedRefrains = refrainTexts
            .map(normalize)
            .filter { !$0.isEmpty }

        if !normalizedRefrains.isEmpty {
            let exactSet = Set(normalizedRefrains)
            let exactMatches = lyrics.filter { exactSet.contains(normalize($0.text)) }
            if !exactMatches.isEmpty {
                return exactMatches
            }

            let containsMatches = lyrics.filter { line in
                let normalizedLine = normalize(line.text)
                guard !normalizedLine.isEmpty else { return false }
                return normalizedRefrains.contains { refrain in
                    normalizedLine.contains(refrain) || refrain.contains(normalizedLine)
                }
            }
            if !containsMatches.isEmpty {
                return containsMatches
            }
        }

        return lyrics.filter { $0.isRefrain }
    }

    // MARK: - Pipeline Integration

    /// Called when playback position updates (call frequently, e.g. from OSC or timer)
    /// Drives the karaoke engine for automatic line transitions
    func onPlaybackPositionUpdate(_ position: Double) {
        Task { @MainActor [karaokeEngine, refrainEngine] in
            karaokeEngine.updatePosition(position)
            refrainEngine.updatePosition(position)
        }
    }

    /// Called when track changes (update song info)
    func onTrackChange(artist: String, title: String) {
        Task { @MainActor [songInfoEngine] in
            songInfoEngine.show(artist: artist, title: title)
        }
    }

    /// Called when lyrics are loaded (from pipeline)
    func onLyricsLoaded(_ lines: [LyricLine], refrainLines: [String]) {
        Task { @MainActor [karaokeEngine, refrainEngine] in
            karaokeEngine.loadLyrics(lines)

            let resolvedRefrains = Self.resolveRefrainLines(
                lyrics: lines,
                refrainTexts: refrainLines
            )
            if resolvedRefrains.isEmpty {
                refrainEngine.reset()
            } else {
                refrainEngine.loadLyrics(resolvedRefrains)
            }
        }
    }

    /// Called when track changes - resets karaoke engine
    func onTrackReset() {
        Task { @MainActor [karaokeEngine, refrainEngine, songInfoEngine] in
            karaokeEngine.reset()
            refrainEngine.reset()
            songInfoEngine.hide()
        }
    }

    /// Called when playback state changes (show/hide song info)
    func onPlaybackStateChange(isPlaying: Bool) {
        Task { @MainActor [songInfoEngine] in
            if isPlaying {
                return
            }
            songInfoEngine.hide()
        }
    }

    /// Called when shader should change (from pipeline)
    func onShaderChange(name: String) {
        Task { @MainActor [shaderSelection] in
            shaderSelection.selectMain(name: name)
        }
    }

    /// Called with audio update (from pipeline or OSC)
    func onAudioUpdate(_ levels: OSCAudioLevels, stats: (messageRate: Int, messageCount: Int, isActive: Bool)? = nil) async {
        await audioManager.update(oscLevels: levels)
        if let s = stats {
            await MainActor.run { [audioManager] in
                audioManager.updateStats(messageRate: s.messageRate, messageCount: s.messageCount, isActive: s.isActive)
            }
        }
    }
}

// MARK: - Errors

enum RenderEngineError: Error, LocalizedError {
    case noMetalDevice
    case shaderCompilationFailed(String)
    case textureCreationFailed

    var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            return "No Metal-compatible GPU found"
        case .shaderCompilationFailed(let message):
            return "Shader compilation failed: \(message)"
        case .textureCreationFailed:
            return "Failed to create texture"
        }
    }
}

// MARK: - Render Engine Provider

/// Environment key for RenderEngine
struct RenderEngineKey: EnvironmentKey {
    static let defaultValue: RenderEngine? = nil
}

extension EnvironmentValues {
    var renderEngine: RenderEngine? {
        get { self[RenderEngineKey.self] }
        set { self[RenderEngineKey.self] = newValue }
    }
}

// RenderEngine.swift - Main rendering orchestrator for VJ system
// Port of TileManager.pde and VJUniverse main loop to Swift

import Foundation
import Metal
import MetalKit
import Combine
import SwiftUI
import SwiftVJCore

// MARK: - Render Frame Context

/// Snapshot of all state needed for one render frame
/// Gathered in a single MainActor hop to minimize thread switching
struct RenderFrameContext: Sendable {
    let audioState: AudioState
    let lyricsState: LyricsDisplayState
    let refrainState: RefrainDisplayState
    let songInfoState: SongInfoDisplayState
    let shaderState: ShaderDisplayState
    let maskState: ShaderDisplayState
    let imageState: ImageDisplayState
}

// MARK: - Tile Manager Actor

/// Manages all tiles and their lifecycle
/// Port of TileManager.pde
actor TileManager {
    private var tiles: [String: any Tile] = [:]
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
    }

    func setup() async {
        // Create tiles
        tiles["shader"] = ShaderTile(device: device)
        tiles["mask"] = MaskShaderTile(device: device)
        tiles["lyrics"] = LyricsTile(device: device)
        tiles["refrain"] = RefrainTile(device: device)
        tiles["songInfo"] = SongInfoTile(device: device)
        tiles["image"] = ImageTile(device: device)

        print("[TileManager] Created \(tiles.count) tiles")
    }

    func update(audioState: AudioState, deltaTime: Float) async {
        for tile in tiles.values {
            tile.update(audioState: audioState, deltaTime: deltaTime)
        }
    }

    func render() async {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        for tile in tiles.values {
            tile.render(commandBuffer: commandBuffer)
        }

        commandBuffer.commit()
            // Removed blocking waitUntilCompleted
    }

    /// Render with Syphon publishing
    func renderAndPublish(syphonManager: SyphonOutputManager?) async {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Render all tiles
        for tile in tiles.values {
            tile.render(commandBuffer: commandBuffer)
        }

        // NOTE: Syphon publishing now handled by MTKView tiles via onTextureReady callback
        // The old actor-based tiles here are deprecated in favor of MTKViewTiles.swift

        commandBuffer.commit()
            // Removed blocking waitUntilCompleted
    }

    /// Map tile name to Syphon server name
    private func syphonNameForTile(_ tileName: String) -> String {
        switch tileName {
        case "shader": return TileConfig.shader.syphonName
        case "mask": return TileConfig.mask.syphonName
        case "lyrics": return TileConfig.lyrics.syphonName
        case "refrain": return TileConfig.refrain.syphonName
        case "songInfo": return TileConfig.songInfo.syphonName
        case "image": return TileConfig.image.syphonName
        default: return "SwiftVJ/\(tileName.capitalized)"
        }
    }

    func getTile(_ name: String) -> (any Tile)? {
        tiles[name]
    }

    func getTexture(_ name: String) -> MTLTexture? {
        tiles[name]?.texture
    }

    func getAllTileNames() -> [String] {
        Array(tiles.keys).sorted()
    }

    var shaderTile: ShaderTile? {
        tiles["shader"] as? ShaderTile
    }

    var lyricsTile: LyricsTile? {
        tiles["lyrics"] as? LyricsTile
    }

    var refrainTile: RefrainTile? {
        tiles["refrain"] as? RefrainTile
    }

    var songInfoTile: SongInfoTile? {
        tiles["songInfo"] as? SongInfoTile
    }

    var imageTile: ImageTile? {
        tiles["image"] as? ImageTile
    }

    var maskTile: MaskShaderTile? {
        tiles["mask"] as? MaskShaderTile
    }
}

// MARK: - Render Engine

/// Main rendering engine that orchestrates tiles, audio, and output
/// Observable for SwiftUI integration
/// NOTE: Not main-actor isolated; only minimal UI-facing mutations hop to main.
final class RenderEngine: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var fps: Double = 0
    @Published private(set) var frameCount: Int = 0

    // State managers
    @Published var audioManager: AudioStateManager
    @Published var textManager: TextStateManager
    @Published var shaderManager: ShaderStateManager
    @Published var maskManager: MaskStateManager
    @Published var imageManager: ImageStateManager

    // Audio Processor (injected)
    private var synesthesiaAudio: SynesthesiaAudioProcessor?

    // MARK: - Private

    private var device: MTLDevice?
    private(set) var tileManager: TileManager?
    private var displayLink: CVDisplayLink?
    private var renderTimer: Timer?
    private var dispatchTimer: DispatchSourceTimer?
    private var renderThread: Thread?

    // Syphon output
    var syphonManager: SyphonOutputManager?
    @Published private(set) var syphonEnabled: Bool = true

    private var lastFrameTime: Date = Date()
    private var frameTimeAccum: Double = 0
    private var fpsUpdateCounter: Int = 0

    // Target framerate
    private let targetFPS: Double = 60

    // MARK: - Init

    static func create(synesthesiaAudio: SynesthesiaAudioProcessor? = nil) async -> RenderEngine {
        let audioManager = await MainActor.run { AudioStateManager() }
        let textManager = await MainActor.run { TextStateManager() }
        let shaderManager = await MainActor.run { ShaderStateManager() }
        let maskManager = await MainActor.run { MaskStateManager() }
        let imageManager = await MainActor.run { ImageStateManager() }

        return RenderEngine(
            synesthesiaAudio: synesthesiaAudio,
            audioManager: audioManager,
            textManager: textManager,
            shaderManager: shaderManager,
            maskManager: maskManager,
            imageManager: imageManager
        )
    }

    private init(
        synesthesiaAudio: SynesthesiaAudioProcessor?,
        audioManager: AudioStateManager,
        textManager: TextStateManager,
        shaderManager: ShaderStateManager,
        maskManager: MaskStateManager,
        imageManager: ImageStateManager
    ) {
        self.synesthesiaAudio = synesthesiaAudio
        self.audioManager = audioManager
        self.textManager = textManager
        self.shaderManager = shaderManager
        self.maskManager = maskManager
        self.imageManager = imageManager
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !isRunning else { return }

        // Initialize Metal
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RenderEngineError.noMetalDevice
        }
        self.device = device

        // Create tile manager
        let manager = TileManager(device: device)
        await manager.setup()
        self.tileManager = manager

        // Create Syphon output manager
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.syphonManager = SyphonOutputManager(device: device)
            self.syphonManager?.createStandardServers()
            self.audioManager.start()
            self.textManager.start()
        }

        // Start render loop
        startRenderLoop()

        DispatchQueue.main.async { [weak self] in self?.isRunning = true }
        print("[RenderEngine] Started with Syphon output")
    }

    func stop() async {
        guard isRunning else { return }

        stopRenderLoop()
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.audioManager.stop()
            self.textManager.stop()
            self.syphonManager?.stopAll()
            self.syphonManager = nil
        }

        DispatchQueue.main.async { [weak self] in self?.isRunning = false }
        print("[RenderEngine] Stopped")
    }

    /// Toggle Syphon output
    func setSyphonEnabled(_ enabled: Bool) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.syphonEnabled = enabled
            self.syphonManager?.isEnabled = enabled
        }
    }

    // MARK: - Render Loop

    private func startRenderLoop() {
        lastFrameTime = Date()
        
        // Use a dedicated thread with its own run loop for reliable timing
        let thread = Thread { [weak self] in
            guard let self = self else { return }
            
            let interval = 1.0 / self.targetFPS
            var lastTime = CFAbsoluteTimeGetCurrent()
            
            while !Thread.current.isCancelled {
                autoreleasepool {
                    let currentTime = CFAbsoluteTimeGetCurrent()
                    let elapsed = currentTime - lastTime
                    
                    if elapsed >= interval {
                        lastTime = currentTime
                        // Run render loop directly on this thread (off main)
                        Task { await self.renderFrame() }
                    }
                }
                // Sleep briefly to avoid spinning CPU
                Thread.sleep(forTimeInterval: 0.001)
            }
        }
        thread.name = "RenderLoop"
        thread.qualityOfService = .userInteractive
        renderThread = thread
        thread.start()
        
        print("[RenderEngine] Render loop started on dedicated thread at \(targetFPS) FPS")
    }

    private func stopRenderLoop() {
        renderThread?.cancel()
        renderThread = nil
        
        renderTimer?.invalidate()
        renderTimer = nil
        dispatchTimer?.cancel()
        dispatchTimer = nil
        
        if let link = displayLink {
            CVDisplayLinkStop(link)
            self.displayLink = nil
        }
    }

    private func renderFrame() async {
        let now = Date()
        let deltaTime = Float(now.timeIntervalSince(lastFrameTime))
        lastFrameTime = now

        // Update FPS counter (only publish every 30 frames to reduce main thread hops)
        frameTimeAccum += Double(deltaTime)
        fpsUpdateCounter += 1
        let shouldPublishFPS = fpsUpdateCounter >= 30
        if shouldPublishFPS {
            fpsUpdateCounter = 0
        }
        let newFrame = frameCount + 1
        frameCount = newFrame

        // Get audio levels from processor (off main thread)
        var audioLevels: OSCAudioLevels?
        var audioStats: (messageCount: Int, lastMessage: Date, isActive: Bool, messageRate: Int)?
        if let processor = synesthesiaAudio {
            audioLevels = await processor.getLevels()
            audioStats = await processor.stats
        }

        // Process audio OFF MainActor (AudioProcessor is an actor, not @MainActor)
        var processedAudioState: AudioState?
        if let levels = audioLevels {
            processedAudioState = await audioManager.processAudioOffMain(oscLevels: levels)
        }

        // Capture for closure
        let capturedStats = audioStats
        let capturedAudioState = processedAudioState

        // SINGLE MainActor hop to set state and gather ALL state
        let context = await MainActor.run { [weak self] () -> RenderFrameContext? in
            guard let self = self else { return nil }

            // Set processed audio state directly (no async needed)
            if let audioState = capturedAudioState {
                self.audioManager.setStateDirectly(audioState)
            }

            // Update stats (lightweight, no async needed)
            if let stats = capturedStats {
                self.audioManager.updateStats(
                    messageRate: stats.messageRate,
                    messageCount: stats.messageCount,
                    isActive: stats.isActive
                )
            }

            // Publish FPS only when batched
            if shouldPublishFPS {
                self.fps = Double(30) / self.frameTimeAccum
                self.frameTimeAccum = 0
            }

            // Gather all state in one hop
            return RenderFrameContext(
                audioState: self.audioManager.state,
                lyricsState: self.textManager.lyricsState,
                refrainState: self.textManager.refrainState,
                songInfoState: self.textManager.songInfoState,
                shaderState: self.shaderManager.state,
                maskState: self.maskManager.state,
                imageState: self.imageManager.state
            )
        }

        guard let context = context, let manager = tileManager else { return }

        // Update tile states from context (no MainActor hops needed)
        await updateTileStates(with: context, manager: manager)

        // Update and render all tiles
        await manager.update(audioState: context.audioState, deltaTime: deltaTime)
        await manager.renderAndPublish(syphonManager: syphonManager)
    }

    private func updateTileStates(with context: RenderFrameContext, manager: TileManager) async {
        // Update lyrics tile
        if let lyricsTile = await manager.lyricsTile {
            lyricsTile.updateState(context.lyricsState)
        }

        // Update refrain tile
        if let refrainTile = await manager.refrainTile {
            refrainTile.updateState(context.refrainState)
        }

        // Update song info tile
        if let songInfoTile = await manager.songInfoTile {
            songInfoTile.updateState(context.songInfoState)
        }

        // Update shader tile
        if let shaderTile = await manager.shaderTile {
            shaderTile.updateState(context.shaderState)
        }

        // Update mask tile
        if let maskTile = await manager.maskTile {
            maskTile.updateState(context.maskState)
        }

        // Update image tile
        if let imageTile = await manager.imageTile {
            imageTile.updateState(context.imageState)
        }
    }

    // MARK: - Convenience Methods

    /// Get texture for a specific tile (for SwiftUI preview)
    func getTexture(for tileName: String) async -> MTLTexture? {
        await tileManager?.getTexture(tileName)
    }

    /// Get all tile names
    func getTileNames() async -> [String] {
        await tileManager?.getAllTileNames() ?? []
    }

    // MARK: - Pipeline Integration

    /// Called when track changes (from pipeline)
    func onTrackChange(artist: String, title: String, album: String) {
        Task { @MainActor [textManager] in
            textManager.setSongInfo(artist: artist, title: title, album: album)
        }
    }

    /// Called when lyrics are loaded (from pipeline)
    func onLyricsLoaded(_ lines: [LyricLine]) {
        Task { @MainActor [textManager] in
            textManager.setLyrics(lines)
        }
    }

    /// Called when active lyric line changes (from pipeline)
    func onActiveLine(_ index: Int) {
        Task { @MainActor [textManager] in
            textManager.setActiveLine(index)
        }
    }

    /// Called when refrain is active (from pipeline)
    func onRefrain(_ text: String) {
        Task { @MainActor [textManager] in
            textManager.setRefrain(text)
        }
    }

    /// Called when shader should change (from pipeline)
    func onShaderChange(name: String) {
        Task { @MainActor [shaderManager] in
            shaderManager.selectShader(name: name)
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

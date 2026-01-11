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
    let lyricsState: LyricsDisplayState
    let refrainState: RefrainDisplayState
    let songInfoState: SongInfoDisplayState
    let shaderState: ShaderDisplayState
    let maskState: ShaderDisplayState
    let imageState: ImageDisplayState
}

// MARK: - Render Engine

/// Main rendering engine that orchestrates headless tile rendering and Syphon output
/// CVDisplayLink callback runs GPU work synchronously on a real-time thread
final class RenderEngine: ObservableObject {
    // MARK: - Published State (MainActor for SwiftUI)

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var fps: Double = 0
    @Published private(set) var frameCount: Int = 0

    // State managers (MainActor isolated for SwiftUI binding)
    @Published var audioManager: AudioStateManager
    @Published var textManager: TextStateManager
    @Published var shaderManager: ShaderStateManager
    @Published var maskManager: MaskStateManager
    @Published var imageManager: ImageStateManager

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

        // Create headless renderer
        let renderer = HeadlessRenderer(device: device, logger: logger)
        self.headlessRenderer = renderer
        logger?("[RenderEngine] Initialized headless renderer")
        
        // Load default shaders
        renderer.shaderRenderer.loadShader(name: "3isacrowd")
        renderer.maskRenderer.loadShader(name: "BWrevolvingswirl")

        // Create thread-safe Syphon manager and start servers
        self.syphonManager = SyphonOutputManager.shared
        syphonManager?.createStandardServers()
        
        // Start MainActor managers
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.audioManager.start()
            self.textManager.start()
        }

        // Start render loop
        startRenderLoop()

        await MainActor.run { [weak self] in self?.isRunning = true }
        print("[RenderEngine] Started with CVDisplayLink rendering")
    }

    func stop() async {
        guard isRunning else { return }

        stopRenderLoop()
        syphonManager?.stopAll()
        syphonManager = nil
        
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.audioManager.stop()
            self.textManager.stop()
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
        renderer.lyricsRenderer.lyricsState = context.lyricsState
        renderer.refrainRenderer.refrainState = context.refrainState
        renderer.songInfoRenderer.songInfoState = context.songInfoState
        renderer.imageRenderer.imageState = context.imageState
        
        // Handle shader changes
        if let shaderName = pendingShaderName.withLock({ val -> String? in
            let current = val
            if current != renderer.shaderRenderer.currentShaderName {
                return current
            }
            return nil
        }) {
            renderer.shaderRenderer.loadShader(name: shaderName)
        }
        
        if let maskName = pendingMaskName.withLock({ val -> String? in
            let current = val
            if current != renderer.maskRenderer.currentShaderName {
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
        case "lyrics": return renderer.lyricsRenderer.texture
        case "refrain": return renderer.refrainRenderer.texture
        case "songInfo": return renderer.songInfoRenderer.texture
        default: return nil
        }
    }

    /// Get all tile names
    func getTileNames() -> [String] {
        ["shader", "mask", "lyrics", "refrain", "songInfo"]
    }

    // MARK: - Pipeline Integration

    /// Called when track changes (from pipeline)
    func onTrackChange(artist: String, title: String, album: String) {
        Task { @MainActor [textManager] in
            textManager.setSongInfo(artist: artist, title: title, album: album)
        }
    }

    /// Called when lyrics are loaded (from pipeline)
    func onLyricsLoaded(_ lines: [DisplayLyricLine]) {
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

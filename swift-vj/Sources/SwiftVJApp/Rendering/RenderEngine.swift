// RenderEngine.swift - Main rendering orchestrator for VJ system
// Headless rendering with single command buffer per frame
// All UI previews consume via Syphon clients only

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

// MARK: - Render Engine

/// Main rendering engine that orchestrates headless tile rendering and Syphon output
/// Observable for SwiftUI integration
/// NOTE: All rendering is headless - UI previews consume via Syphon clients only
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
    
    // Logger closure for UI logging
    var logger: ((String) -> Void)?

    // MARK: - Private

    private var device: MTLDevice?
    private(set) var headlessRenderer: HeadlessRenderer?
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

        // Create headless renderer (replaces TileManager)
        let renderer = HeadlessRenderer(device: device, logger: logger)
        self.headlessRenderer = renderer
        logger?("[RenderEngine] Initialized headless renderer")
        
        // Load default shaders (verified to exist in metallib)
        renderer.shaderRenderer.loadShader(name: "3isacrowd")
        renderer.maskRenderer.loadShader(name: "BWrevolvingswirl")

        // Create Syphon output manager (singleton to avoid duplicate servers)
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            self.syphonManager = SyphonOutputManager.shared
            self.syphonManager?.createStandardServers()
            self.audioManager.start()
            self.textManager.start()
        }

        // Start render loop
        startRenderLoop()

        DispatchQueue.main.async { [weak self] in self?.isRunning = true }
        print("[RenderEngine] Started with headless rendering + Syphon output")
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

        guard let context = context, let renderer = headlessRenderer else { return }
        
        // Update renderer state from context
        renderer.lyricsRenderer.lyricsState = context.lyricsState
        renderer.refrainRenderer.refrainState = context.refrainState
        renderer.songInfoRenderer.songInfoState = context.songInfoState
        
        // Sync imageManager state with renderer (imageRenderer is source of truth)
        await MainActor.run { [weak self] in
            self?.imageManager.state = renderer.imageRenderer.imageState
        }
        
        // Handle shader changes
        if let shaderName = context.shaderState.current?.name,
           shaderName != renderer.shaderRenderer.currentShaderName {
            renderer.shaderRenderer.loadShader(name: shaderName)
        }
        if let maskName = context.maskState.current?.name,
           maskName != renderer.maskRenderer.currentShaderName {
            renderer.maskRenderer.loadShader(name: maskName)
        }

        // Render all tiles in single command buffer → publish → commit
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            renderer.renderFrame(
                audioState: context.audioState,
                syphonManager: self.syphonManager
            )
        }
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
    
    // MARK: - Analysis Support
    
    /// Load a shader directly into headless renderer and render a frame for analysis/screenshots.
    /// This bypasses the normal render loop to guarantee the shader is rendered.
    /// - Parameter shaderName: Bare shader name (e.g., "Electriclava") matching metallib function names
    /// - Returns: True if shader was loaded and rendered successfully
    @discardableResult
    func loadAndRenderForAnalysis(shaderName: String) async -> Bool {
        guard let renderer = headlessRenderer else {
            print("[RenderEngine] ❌ No headless renderer for analysis")
            return false
        }
        
        print("[RenderEngine] loadAndRenderForAnalysis: '\(shaderName)'")
        
        // Directly load the shader into headless renderer
        let loadSuccess = renderer.shaderRenderer.loadShader(name: shaderName)
        
        if !loadSuccess {
            print("[RenderEngine] ❌ FAILED to load shader '\(shaderName)' for analysis")
            return false
        }
        
        // Create a default audio state for rendering (mid-energy for screenshots)
        let audioState = AudioState(
            bass: 0.4,
            lowMid: 0.3,
            mid: 0.4,
            highs: 0.3,
            level: 0.4,
            energyFast: 0.4,
            energySlow: 0.35,
            kickEnv: 0.0,
            kickPulse: false,
            beatPhase: 0.0,
            beat4: 0,
            bpmTwitcher: 0.5,
            bpmSin4: 0.0,
            bpmConfidence: 0.8,
            bassPresence: 0.4,
            midPresence: 0.3,
            highPresence: 0.2,
            timestamp: Date()
        )
        
        // Render the frame
        await MainActor.run { [syphonManager] in
            renderer.renderFrame(audioState: audioState, syphonManager: syphonManager)
        }
        
        return true
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

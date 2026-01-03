// RenderEngine.swift - Main rendering orchestrator for VJ system
// Port of TileManager.pde and VJUniverse main loop to Swift

import Foundation
import Metal
import MetalKit
import Combine
import SwiftUI

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
        commandBuffer.waitUntilCompleted()
    }

    /// Render with Syphon publishing
    func renderAndPublish(syphonManager: SyphonOutputManager?) async {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Render all tiles
        for tile in tiles.values {
            tile.render(commandBuffer: commandBuffer)
        }

        // Publish to Syphon
        if let syphon = syphonManager {
            for (name, tile) in tiles {
                if let texture = tile.texture {
                    let syphonName = syphonNameForTile(name)
                    syphon.publish(name: syphonName, texture: texture, commandBuffer: commandBuffer)
                }
            }
        }

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
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
@MainActor
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

    // MARK: - Private

    private var device: MTLDevice?
    private(set) var tileManager: TileManager?
    private var displayLink: CVDisplayLink?
    private var renderTimer: Timer?

    // Syphon output
    var syphonManager: SyphonOutputManager?
    @Published private(set) var syphonEnabled: Bool = true

    private var lastFrameTime: Date = Date()
    private var frameTimeAccum: Double = 0
    private var fpsUpdateCounter: Int = 0

    // Target framerate
    private let targetFPS: Double = 60

    // MARK: - Init

    init() {
        audioManager = AudioStateManager()
        textManager = TextStateManager()
        shaderManager = ShaderStateManager()
        maskManager = MaskStateManager()
        imageManager = ImageStateManager()
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
        syphonManager = SyphonOutputManager(device: device)
        syphonManager?.createStandardServers()

        // Start state managers
        audioManager.start()
        textManager.start()

        // Start render loop
        startRenderLoop()

        isRunning = true
        print("[RenderEngine] Started with Syphon output")
    }

    func stop() async {
        guard isRunning else { return }

        stopRenderLoop()
        audioManager.stop()
        textManager.stop()

        // Stop Syphon servers
        syphonManager?.stopAll()
        syphonManager = nil

        isRunning = false
        print("[RenderEngine] Stopped")
    }

    /// Toggle Syphon output
    func setSyphonEnabled(_ enabled: Bool) {
        syphonEnabled = enabled
        syphonManager?.isEnabled = enabled
    }

    // MARK: - Render Loop

    private func startRenderLoop() {
        lastFrameTime = Date()

        // Use timer for render loop (simpler than CVDisplayLink for now)
        renderTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / targetFPS,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.renderFrame()
            }
        }
    }

    private func stopRenderLoop() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    private func renderFrame() async {
        let now = Date()
        let deltaTime = Float(now.timeIntervalSince(lastFrameTime))
        lastFrameTime = now

        // Update FPS
        frameTimeAccum += Double(deltaTime)
        fpsUpdateCounter += 1
        if fpsUpdateCounter >= 30 {
            fps = Double(fpsUpdateCounter) / frameTimeAccum
            frameTimeAccum = 0
            fpsUpdateCounter = 0
        }

        frameCount += 1

        // Get current audio state
        let audioState = audioManager.state

        // Update tile states from managers
        await updateTileStates()

        // Update and render all tiles
        guard let manager = tileManager else { return }

        await manager.update(audioState: audioState, deltaTime: deltaTime)
        await manager.renderAndPublish(syphonManager: syphonManager)
    }

    private func updateTileStates() async {
        guard let manager = tileManager else { return }

        // Update lyrics tile
        if let lyricsTile = await manager.lyricsTile {
            lyricsTile.updateState(textManager.lyricsState)
        }

        // Update refrain tile
        if let refrainTile = await manager.refrainTile {
            refrainTile.updateState(textManager.refrainState)
        }

        // Update song info tile
        if let songInfoTile = await manager.songInfoTile {
            songInfoTile.updateState(textManager.songInfoState)
        }

        // Update shader tile
        if let shaderTile = await manager.shaderTile {
            shaderTile.updateState(shaderManager.state)
        }

        // Update mask tile
        if let maskTile = await manager.maskTile {
            maskTile.updateState(maskManager.state)
        }

        // Update image tile
        if let imageTile = await manager.imageTile {
            imageTile.updateState(imageManager.state)
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
        textManager.setSongInfo(artist: artist, title: title, album: album)
    }

    /// Called when lyrics are loaded (from pipeline)
    func onLyricsLoaded(_ lines: [LyricLine]) {
        textManager.setLyrics(lines)
    }

    /// Called when active lyric line changes (from pipeline)
    func onActiveLine(_ index: Int) {
        textManager.setActiveLine(index)
    }

    /// Called when refrain is active (from pipeline)
    func onRefrain(_ text: String) {
        textManager.setRefrain(text)
    }

    /// Called when shader should change (from pipeline)
    func onShaderChange(name: String) {
        shaderManager.selectShader(name: name)
    }

    /// Called with audio update (from pipeline or OSC)
    func onAudioUpdate(_ levels: RawAudioLevels) async {
        await audioManager.update(rawLevels: levels)
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

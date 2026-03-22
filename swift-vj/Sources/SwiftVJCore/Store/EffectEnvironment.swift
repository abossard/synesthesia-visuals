// EffectEnvironment.swift - Dependency injection for effects
// Provides access to app-layer services without coupling to concrete implementations

import Foundation
import SongRepository

public protocol LaunchpadEffectHandling: Sendable {
    func start() async
    func stop() async
    func buttonPressed(x: Int, y: Int) async
    func buttonReleased(x: Int, y: Int) async
    func enterLearnMode() async
    func exitLearnMode() async
    func forceProgrammerMode() async
    func flashAll() async
    func rainbowPattern() async
    func clearAll() async
    func receiveOscEvent(_ event: OscEvent) async
}

public protocol LauncherEffectHandling: Sendable {
    func analyzeDroppedItems(_ urls: [URL]) async -> [LaunchTarget]
    func launchTarget(_ target: LaunchTarget) async -> (launched: Bool, error: String?)
    func launchTargetsIfNeeded(_ targets: [LaunchTarget]) async -> LauncherLaunchReport
}

/// Environment for effect execution, providing dependency injection.
///
/// This follows TCA's environment pattern where side effects access
/// external services through injected dependencies rather than
/// directly importing concrete implementations.
///
/// Usage:
/// 1. App layer sets callbacks during initialization
/// 2. Effects access services via `EffectEnvironment.shared`
/// 3. Enables testing by replacing callbacks with mocks
///
/// Example:
/// ```swift
/// // In SwiftVJApp.init():
/// EffectEnvironment.shared.loadShader = { name in
///     self.renderEngine?.shaderManager.selectShader(name: name)
///     try? self.oscHub.sendToMagic("/shader/load", values: [name, 0.5, 0.0])
/// }
/// ```
@MainActor
public final class EffectEnvironment {
    
    /// Shared environment instance
    public static let shared = EffectEnvironment()
    
    private init() {}
    
    // MARK: - Render Effects
    
    /// Load a shader by name (updates render engine + sends OSC)
    public var loadShader: (@Sendable (String) async -> Void)?

    /// Load a mask shader by name (updates render engine mask pipeline)
    public var loadMaskShader: (@Sendable (String) async -> Void)?

    /// Query available main shader names from the app layer
    public var availableShaderNames: (@Sendable () async -> [String])?

    /// Query available mask shader names from the app layer
    public var availableMaskShaderNames: (@Sendable () async -> [String])?

    /// Set the current image index
    public var setImageIndex: (@Sendable (Int) async -> Void)?
    
    /// Load images from a folder path
    public var loadImagesFromFolder: (@Sendable (String) async -> Void)?

    /// Enable or disable rendering lifecycle (render loop + Syphon exposure)
    public var setRenderEnabled: (@Sendable (Bool) async -> Void)?

    /// Enable or disable a specific Syphon/render output
    public var setRenderOutputEnabled: (@Sendable (RenderOutput, Bool) async -> Void)?
    
    // MARK: - Pipeline Effects
    
    /// Process a track through the pipeline
    public var processPipelineTrack: (@Sendable (Track) async -> Void)?
    
    /// Clear lyrics cache for a song (for reanalysis)
    public var clearLyricsCache: (@Sendable (String, String) async -> Void)?
    
    /// Clear pipeline cache for a song (for reanalysis)
    public var clearPipelineCache: (@Sendable (String, String) async -> Void)?
    
    /// Clear images cache for a song (for reanalysis)
    public var clearImagesCache: (@Sendable (String, String) async -> Void)?

    /// Current DJ phase provider
    public var currentPhaseProvider: (@Sendable () async -> Phase?)?

    // MARK: - AI Effects

    /// Reload Tachikoma configuration in app-layer AI clients.
    public var reloadLLMConfiguration: (@Sendable () async -> Void)?
    
    // MARK: - OSC Effects

    /// Send OSC message to a target
    public var sendOSC: (@Sendable (String, String, [any Sendable], String?) async throws -> Void)?

    // MARK: - Songs Module

    /// Songs module for song management
    public var songsModule: SongsModule?

    // MARK: - LedFX Effects

    /// Handle LedFX actions in the app layer
    public var ledfxActionHandler: (@Sendable (LedFXAction) async -> Void)?

    // MARK: - Launchpad Effects

    /// Launchpad side-effect handler (implemented in app layer, actor-isolated)
    public var launchpadHandler: (any LaunchpadEffectHandling)?

    // MARK: - Launcher Effects

    /// App/command launcher handler (implemented in app layer, actor-isolated)
    public var launcherHandler: (any LauncherEffectHandling)?

    // MARK: - Moodboard Effects

    /// Result type for moodboard loading
    public struct MoodboardLoadResult: Sendable {
        public let nodes: [MoodboardNode]
        public let edges: [MoodboardEdge]
        public let connections: [SongConnection]
        public let phaseEdges: [PhaseFlowEdge]
        public let positions: [CanvasPositionEntry]

        public init(
            nodes: [MoodboardNode], edges: [MoodboardEdge],
            connections: [SongConnection], phaseEdges: [PhaseFlowEdge],
            positions: [CanvasPositionEntry]
        ) {
            self.nodes = nodes
            self.edges = edges
            self.connections = connections
            self.phaseEdges = phaseEdges
            self.positions = positions
        }
    }

    /// Load moodboard graph from song data
    public var loadMoodboardFromSongs: (@Sendable () async -> MoodboardLoadResult)?

    /// Save an explicit song connection
    public var saveSongConnection: (@Sendable (SongConnection) async -> Void)?

    /// Remove an explicit song connection
    public var removeSongConnection: (@Sendable (SongID, SongID) async -> Void)?

    /// Save canvas node positions
    public var saveCanvasPositions: (@Sendable ([CanvasPositionEntry]) async -> Void)?

    /// Save phase flow edges
    public var savePhaseEdges: (@Sendable ([PhaseFlowEdge]) async -> Void)?

    /// Update a song tag (add = true, remove = false)
    public var updateSongTag: (@Sendable (SongID, String, TagCategory, Bool) async -> Void)?

    // MARK: - Reset (for testing)

    /// Reset all callbacks to nil (useful for testing)
    public func reset() {
        loadShader = nil
        loadMaskShader = nil
        availableShaderNames = nil
        availableMaskShaderNames = nil
        setImageIndex = nil
        loadImagesFromFolder = nil
        setRenderEnabled = nil
        setRenderOutputEnabled = nil
        processPipelineTrack = nil
        clearLyricsCache = nil
        clearPipelineCache = nil
        clearImagesCache = nil
        reloadLLMConfiguration = nil
        sendOSC = nil
        songsModule = nil
        ledfxActionHandler = nil
        launchpadHandler = nil
        launcherHandler = nil
        loadMoodboardFromSongs = nil
        saveSongConnection = nil
        removeSongConnection = nil
        saveCanvasPositions = nil
        savePhaseEdges = nil
        updateSongTag = nil
    }
}

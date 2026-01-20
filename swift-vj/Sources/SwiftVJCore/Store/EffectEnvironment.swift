// EffectEnvironment.swift - Dependency injection for effects
// Provides access to app-layer services without coupling to concrete implementations

import Foundation

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
    
    /// Set the current image index
    public var setImageIndex: (@Sendable (Int) async -> Void)?
    
    /// Load images from a folder path
    public var loadImagesFromFolder: (@Sendable (String) async -> Void)?
    
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
    
    // MARK: - OSC Effects

    /// Send OSC message to a target
    public var sendOSC: (@Sendable (String, String, [any Sendable]) async throws -> Void)?

    // MARK: - Songs Module

    /// Songs module for song management
    public var songsModule: SongsModule?

    // MARK: - Reset (for testing)

    /// Reset all callbacks to nil (useful for testing)
    public func reset() {
        loadShader = nil
        setImageIndex = nil
        loadImagesFromFolder = nil
        processPipelineTrack = nil
        clearLyricsCache = nil
        clearPipelineCache = nil
        clearImagesCache = nil
        sendOSC = nil
        songsModule = nil
    }
}

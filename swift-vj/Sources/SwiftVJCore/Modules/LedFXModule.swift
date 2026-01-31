// LedFXModule.swift - Module for LedFX integration
// Following A Philosophy of Software Design: deep module with simple interface

import Foundation

/// Module for managing LedFX integration and scene synchronization
public actor LedFXModule: Module {
    
    // MARK: - Dependencies
    
    private let client: LedFXClient
    private let virtualIds: [String]
    
    // MARK: - State
    
    public private(set) var isStarted: Bool = false
    private var serverInfo: LedFXInfo?
    private var currentScenes: [String: LedFXScene] = [:]
    private var currentVirtuals: [String: LedFXVirtual] = [:]
    private var activeSceneId: String?
    
    // MARK: - Callbacks
    
    private var sceneChangeCallback: ((String) async -> Void)?
    
    // MARK: - Initialization
    
    public init(
        baseURL: String = "http://127.0.0.1:8888",
        virtualIds: [String] = []
    ) {
        self.client = LedFXClient(baseURL: baseURL)
        self.virtualIds = virtualIds
    }
    
    // MARK: - Module Lifecycle
    
    public func start() async throws {
        guard !isStarted else {
            throw ModuleError.alreadyStarted
        }
        
        // Test connection and get server info
        do {
            serverInfo = try await client.getInfo()
        } catch {
            throw ModuleError.startupFailed("Failed to connect to LedFX: \(error.localizedDescription)")
        }
        
        // Load current state
        try await refreshScenes()
        try await refreshVirtuals()
        
        isStarted = true
    }
    
    public func stop() async {
        guard isStarted else { return }
        
        isStarted = false
        currentScenes = [:]
        currentVirtuals = [:]
        activeSceneId = nil
    }
    
    public func getStatus() -> ModuleStatus {
        var status = ModuleStatus()
        status["started"] = .bool(isStarted)
        status["server_version"] = serverInfo.map { .string($0.version) } ?? .string("unknown")
        status["scene_count"] = .int(currentScenes.count)
        status["virtual_count"] = .int(currentVirtuals.count)
        status["active_scene"] = activeSceneId.map { .string($0) } ?? .string("none")
        return status
    }
    
    // MARK: - Scene Management
    
    /// Refresh scenes from server
    public func refreshScenes() async throws {
        currentScenes = try await client.listScenes()
        
        // Find active scene
        activeSceneId = currentScenes.first(where: { $0.value.active })?.key
    }
    
    /// Get all scenes
    public func getScenes() -> [String: LedFXScene] {
        currentScenes
    }
    
    /// Get active scene ID
    public func getActiveSceneId() -> String? {
        activeSceneId
    }
    
    /// Create or update a scene
    public func saveScene(id: String, scene: LedFXScene) async throws {
        try await client.putScene(id: id, scene: scene)
        currentScenes[id] = scene
    }
    
    /// Activate a scene
    public func activateScene(id: String, delaySeconds: Int? = nil) async throws {
        guard currentScenes[id] != nil else {
            throw LedFXModuleError.sceneNotFound(id)
        }
        
        try await client.activateScene(id: id, activateIn: delaySeconds)
        
        // Update local state
        activeSceneId = id
        
        // Notify callback
        if let callback = sceneChangeCallback {
            await callback(id)
        }
    }
    
    /// Deactivate a scene
    public func deactivateScene(id: String) async throws {
        try await client.deactivateScene(id: id)
        
        if activeSceneId == id {
            activeSceneId = nil
        }
    }
    
    /// Delete a scene
    public func deleteScene(id: String) async throws {
        try await client.deleteScene(id: id)
        currentScenes.removeValue(forKey: id)
        
        if activeSceneId == id {
            activeSceneId = nil
        }
    }
    
    // MARK: - Virtual Management
    
    /// Refresh virtual devices from server
    public func refreshVirtuals() async throws {
        currentVirtuals = try await client.listVirtuals()
    }
    
    /// Get all virtual devices
    public func getVirtuals() -> [String: LedFXVirtual] {
        currentVirtuals
    }
    
    /// Update virtual brightness
    public func setVirtualBrightness(id: String, brightness: Double) async throws {
        let config = VirtualConfig(brightness: brightness)
        try await client.updateVirtual(id: id, config: config)
        
        // Refresh to get updated state
        try await refreshVirtuals()
    }
    
    // MARK: - Effects
    
    /// Set effect on a virtual device
    public func setEffect(virtualId: String, effect: Effect) async throws {
        try await client.setEffect(virtualId: virtualId, effect: effect)
    }
    
    /// Clear effect on a virtual device
    public func clearEffect(virtualId: String) async throws {
        try await client.clearEffect(virtualId: virtualId)
    }
    
    // MARK: - Oneshots
    
    /// Trigger a oneshot flash on all configured virtuals
    public func triggerFlash(color: String, hold: Int = 100, fade: Int = 200) async throws {
        for virtualId in virtualIds {
            try await client.triggerFlash(virtualId: virtualId, color: color, hold: hold, fade: fade)
        }
    }
    
    /// Trigger a oneshot on a specific virtual
    public func triggerOneshotOn(virtualId: String, oneshot: OneshotRequest) async throws {
        try await client.triggerOneshot(virtualId: virtualId, oneshot: oneshot)
    }
    
    // MARK: - Scene Generation & Sync
    
    /// Generate and save preset scenes
    public func generatePresetScenes() async throws {
        let scenes = SceneGenerator.generatePresetScenes(virtualIds: virtualIds)
        
        for (id, scene) in scenes {
            try await saveScene(id: id, scene: scene)
        }
        
        try await refreshScenes()
    }
    
    /// Generate scenes for a DJ set
    public func generateDJSetScenes(
        tracks: [(name: String, energy: Double, valence: Double, bpm: Double?)]
    ) async throws {
        let scenes = SceneGenerator.generateDJSetScenes(
            virtualIds: virtualIds,
            tracks: tracks
        )
        
        for (id, scene) in scenes {
            try await saveScene(id: id, scene: scene)
        }
        
        try await refreshScenes()
    }
    
    /// Generate a scene from track analysis
    public func generateSceneForTrack(
        name: String,
        energy: Double,
        valence: Double,
        bpm: Double?,
        tags: [String] = []
    ) async throws -> String {
        let sceneId = sanitizeSceneId(name)
        
        let scene = SceneGenerator.generateScene(
            name: name,
            virtualIds: virtualIds,
            energy: energy,
            valence: valence,
            bpm: bpm,
            tags: tags
        )
        
        try await saveScene(id: sceneId, scene: scene)
        try await refreshScenes()
        
        return sceneId
    }
    
    // MARK: - Callbacks
    
    /// Set callback for scene changes
    public func onSceneChange(_ callback: @escaping (String) async -> Void) {
        sceneChangeCallback = callback
    }
    
    // MARK: - Helpers
    
    private func sanitizeSceneId(_ name: String) -> String {
        name
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
    }
}

// MARK: - Errors

public enum LedFXModuleError: Error, LocalizedError {
    case sceneNotFound(String)
    case virtualNotFound(String)
    case invalidConfiguration(String)
    
    public var errorDescription: String? {
        switch self {
        case .sceneNotFound(let id):
            return "Scene not found: \(id)"
        case .virtualNotFound(let id):
            return "Virtual device not found: \(id)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        }
    }
}

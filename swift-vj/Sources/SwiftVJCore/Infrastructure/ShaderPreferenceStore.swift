// ShaderPreferenceStore - Track manual shader selections per song
// Remembers user's shader choices for specific tracks in auto-drive mode

import Foundation

/// Preference entry for a single track
public struct ShaderPreference: Codable, Sendable, Equatable {
    public let trackKey: String
    public let shaderName: String
    public let timestamp: Date
    
    public init(trackKey: String, shaderName: String, timestamp: Date = Date()) {
        self.trackKey = trackKey
        self.shaderName = shaderName
        self.timestamp = timestamp
    }
}

/// Store for shader preferences - tracks manual shader selections per song
///
/// When a user manually selects a shader in auto-drive mode, it's remembered
/// so the same shader is used when that song plays again.
///
/// Following Grokking Simplicity:
/// - Data: preferences dictionary (immutable entries)
/// - Calculations: getPreference, getAllPreferences (pure reads)
/// - Actions: setPreference, load, save (side effects)
public actor ShaderPreferenceStore {
    
    // MARK: - State (Data)
    
    private var preferences: [String: ShaderPreference] = [:]
    private let filePath: URL
    private var isLoaded: Bool = false
    
    // MARK: - Init
    
    public init(filePath: URL? = nil) {
        self.filePath = filePath ?? Config.dataDirectory.appendingPathComponent("shader_preferences.json")
        // Note: Don't load in init - keep init pure. Call loadIfNeeded() on first access.
    }
    
    // MARK: - Public API (Calculations - pure reads)
    
    /// Get preferred shader for a track
    ///
    /// - Parameter trackKey: Track key (artist::title)
    /// - Returns: Shader name if preference exists, nil otherwise
    public func getPreference(for trackKey: String) -> String? {
        loadIfNeeded()
        return preferences[trackKey]?.shaderName
    }
    
    /// Get all preferences
    public func getAllPreferences() -> [ShaderPreference] {
        loadIfNeeded()
        return Array(preferences.values).sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Get preference count
    public var count: Int {
        loadIfNeeded()
        return preferences.count
    }
    
    // MARK: - Public API (Actions - side effects)
    
    /// Set shader preference for a track
    ///
    /// - Parameters:
    ///   - trackKey: Track key (artist::title)
    ///   - shaderName: Name of preferred shader
    public func setPreference(trackKey: String, shaderName: String) {
        loadIfNeeded()
        preferences[trackKey] = ShaderPreference(trackKey: trackKey, shaderName: shaderName)
        save()
    }
    
    /// Remove preference for a track
    ///
    /// - Parameter trackKey: Track key to remove
    public func removePreference(for trackKey: String) {
        loadIfNeeded()
        preferences.removeValue(forKey: trackKey)
        save()
    }
    
    /// Clear all preferences
    public func clearAll() {
        preferences.removeAll()
        save()
    }
    
    // MARK: - Persistence (Actions - side effects)
    
    /// Load preferences from disk if not already loaded
    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        
        guard FileManager.default.fileExists(atPath: filePath.path) else { return }
        guard let data = try? Data(contentsOf: filePath) else { return }
        guard let decoded = try? JSONDecoder().decode([String: ShaderPreference].self, from: data) else { return }
        
        preferences = decoded
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        try? data.write(to: filePath, options: .atomic)
    }
}

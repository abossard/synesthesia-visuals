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
public actor ShaderPreferenceStore {
    
    // MARK: - State
    
    private var preferences: [String: ShaderPreference] = [:]
    private let filePath: URL
    
    // MARK: - Init
    
    public init(filePath: URL? = nil) {
        self.filePath = filePath ?? Config.dataDirectory.appendingPathComponent("shader_preferences.json")
        Task {
            await self.load()
        }
    }
    
    // MARK: - Public API
    
    /// Get preferred shader for a track
    ///
    /// - Parameter trackKey: Track key (artist::title)
    /// - Returns: Shader name if preference exists, nil otherwise
    public func getPreference(for trackKey: String) -> String? {
        preferences[trackKey]?.shaderName
    }
    
    /// Set shader preference for a track
    ///
    /// - Parameters:
    ///   - trackKey: Track key (artist::title)
    ///   - shaderName: Name of preferred shader
    public func setPreference(trackKey: String, shaderName: String) {
        preferences[trackKey] = ShaderPreference(trackKey: trackKey, shaderName: shaderName)
        save()
    }
    
    /// Remove preference for a track
    ///
    /// - Parameter trackKey: Track key to remove
    public func removePreference(for trackKey: String) {
        preferences.removeValue(forKey: trackKey)
        save()
    }
    
    /// Clear all preferences
    public func clearAll() {
        preferences.removeAll()
        save()
    }
    
    /// Get all preferences
    public func getAllPreferences() -> [ShaderPreference] {
        Array(preferences.values).sorted { $0.timestamp > $1.timestamp }
    }
    
    /// Get preference count
    public var count: Int {
        preferences.count
    }
    
    // MARK: - Persistence
    
    private func load() {
        guard FileManager.default.fileExists(atPath: filePath.path),
              let data = try? Data(contentsOf: filePath),
              let decoded = try? JSONDecoder().decode([String: ShaderPreference].self, from: data)
        else {
            return
        }
        preferences = decoded
    }
    
    private func save() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        try? data.write(to: filePath, options: .atomic)
    }
}

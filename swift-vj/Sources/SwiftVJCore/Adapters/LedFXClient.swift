// LedFXClient.swift - HTTP client for LedFX REST API
// Following A Philosophy of Software Design: deep module with simple interface

import Foundation

/// Client for interacting with LedFX REST API
/// Deep module: hides HTTP complexity behind clean async/await interface
public actor LedFXClient {
    
    // MARK: - Configuration
    
    private let baseURL: String
    private let timeoutSeconds: TimeInterval
    private let session: URLSession
    
    // MARK: - Initialization
    
    public init(baseURL: String = "http://127.0.0.1:8888", timeoutSeconds: TimeInterval = 5.0) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.timeoutSeconds = timeoutSeconds
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutSeconds
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Info
    
    /// Get LedFX server info
    public func getInfo() async throws -> LedFXInfo {
        try await get(path: "/api/info")
    }
    
    // MARK: - Scenes
    
    /// List all scenes
    public func listScenes() async throws -> [String: LedFXScene] {
        try await get(path: "/api/scenes")
    }
    
    /// Get a specific scene by ID
    public func getScene(id: String) async throws -> LedFXScene {
        try await get(path: "/api/scenes/\(id)")
    }
    
    /// Create or update a scene
    public func putScene(id: String, scene: LedFXScene) async throws {
        try await put(path: "/api/scenes", body: scene)
    }
    
    /// Activate a scene
    public func activateScene(id: String, activateIn: Int? = nil) async throws {
        let request = SceneActionRequest(id: id, action: .activate, activateIn: activateIn)
        try await put(path: "/api/scenes", body: request)
    }
    
    /// Deactivate a scene
    public func deactivateScene(id: String) async throws {
        let request = SceneActionRequest(id: id, action: .deactivate)
        try await put(path: "/api/scenes", body: request)
    }
    
    /// Delete a scene
    public func deleteScene(id: String) async throws {
        try await delete(path: "/api/scenes/\(id)")
    }
    
    // MARK: - Virtuals
    
    /// List all virtual devices
    public func listVirtuals() async throws -> [String: LedFXVirtual] {
        try await get(path: "/api/virtuals")
    }
    
    /// Get a specific virtual device
    public func getVirtual(id: String) async throws -> LedFXVirtual {
        try await get(path: "/api/virtuals/\(id)")
    }
    
    /// Update virtual configuration (e.g., brightness)
    public func updateVirtual(id: String, config: VirtualConfig) async throws {
        try await put(path: "/api/virtuals/\(id)", body: config)
    }
    
    // MARK: - Effects
    
    /// Get current effect on a virtual
    public func getEffect(virtualId: String) async throws -> Effect? {
        let virtual: LedFXVirtual = try await getVirtual(id: virtualId)
        return virtual.effect
    }
    
    /// Set effect on a virtual
    public func setEffect(virtualId: String, effect: Effect) async throws {
        try await put(path: "/api/virtuals/\(virtualId)/effects", body: effect)
    }
    
    /// Clear effect on a virtual
    public func clearEffect(virtualId: String) async throws {
        try await delete(path: "/api/virtuals/\(virtualId)/effects")
    }
    
    // MARK: - Presets
    
    /// List presets for a virtual
    public func listPresets(virtualId: String) async throws -> [String: LedFXPreset] {
        try await get(path: "/api/virtuals/\(virtualId)/presets")
    }
    
    /// Activate a preset on a virtual
    public func activatePreset(virtualId: String, presetId: String) async throws {
        let body = ["preset_id": presetId]
        try await put(path: "/api/virtuals/\(virtualId)/presets", body: body)
    }
    
    // MARK: - Virtual Tools (Oneshots)
    
    /// Trigger a oneshot effect on a virtual
    public func triggerOneshot(virtualId: String, oneshot: OneshotRequest) async throws {
        try await put(path: "/api/virtuals_tools/\(virtualId)", body: oneshot)
    }
    
    /// Trigger a simple color flash
    public func triggerFlash(virtualId: String, color: String, hold: Int = 100, fade: Int = 200) async throws {
        let oneshot = OneshotRequest(color: color, hold: hold, fade: fade)
        try await triggerOneshot(virtualId: virtualId, oneshot: oneshot)
    }
    
    // MARK: - Schema
    
    /// Get schema for a specific type (effects, devices, etc.)
    public func getSchema(type: String) async throws -> LedFXSchema {
        try await get(path: "/api/schema/\(type)")
    }
    
    /// Get all schemas
    public func getAllSchemas() async throws -> [String: LedFXSchema] {
        try await get(path: "/api/schema")
    }
    
    // MARK: - HTTP Helpers
    
    private func get<T: Decodable>(path: String) async throws -> T {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LedFXError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LedFXError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LedFXError.decodingError(error)
        }
    }
    
    private func put<T: Encodable>(path: String, body: T) async throws {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw LedFXError.encodingError(error)
        }
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LedFXError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LedFXError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    private func post<T: Encodable>(path: String, body: T) async throws {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw LedFXError.encodingError(error)
        }
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LedFXError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LedFXError.httpError(statusCode: httpResponse.statusCode)
        }
    }
    
    private func delete(path: String) async throws {
        let url = URL(string: "\(baseURL)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LedFXError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LedFXError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}

// MARK: - Errors

public enum LedFXError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case encodingError(Error)
    case decodingError(Error)
    case connectionFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from LedFX server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .encodingError(let error):
            return "Encoding error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .connectionFailed:
            return "Failed to connect to LedFX server"
        }
    }
}

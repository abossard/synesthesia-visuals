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
        let data = try await getData(path: "/api/scenes")

        if let wrapped = try? JSONDecoder().decode(LedFXScenesResponse.self, from: data) {
            guard wrapped.status.lowercased() == "success" else {
                throw LedFXError.apiError(wrapped.status)
            }
            return wrapped.scenes
        }

        do {
            return try JSONDecoder().decode([String: LedFXScene].self, from: data)
        } catch {
            throw LedFXError.decodingError(error)
        }
    }
    
    /// Get a specific scene by ID
    public func getScene(id: String) async throws -> LedFXScene {
        try await get(path: "/api/scenes/\(id)")
    }
    
    /// Create or update a scene
    public func putScene(id: String, scene: LedFXScene) async throws {
        let normalizedVirtuals = Self.normalizeSceneVirtuals(scene.virtuals)
        let request = SceneSaveRequest(id: id, scene: scene, virtuals: normalizedVirtuals)
        let data = try await postData(path: "/api/scenes", body: request)

        if let response = try? JSONDecoder().decode(SceneSaveResponse.self, from: data) {
            guard response.status.lowercased() == "success" else {
                let reason = response.payload?.reason ?? response.payload?.type
                let detail = [response.status, reason].compactMap { $0 }.joined(separator: ": ")
                throw LedFXError.apiError(detail)
            }
        }
    }

    /// Create a new scene (omit id per LedFX API)
    public func createScene(scene: LedFXScene) async throws -> String {
        let normalizedVirtuals = Self.normalizeSceneVirtuals(scene.virtuals)
        let request = SceneCreateRequest(scene: scene, virtuals: normalizedVirtuals)
        let data = try await postData(path: "/api/scenes", body: request)

        if let response = try? JSONDecoder().decode(SceneCreateResponse.self, from: data) {
            guard response.status.lowercased() == "success" else {
                let reason = response.payload?.reason ?? response.payload?.type
                let detail = [response.status, reason].compactMap { $0 }.joined(separator: ": ")
                throw LedFXError.apiError(detail)
            }
            if let id = response.payload?.id ?? response.payload?.sceneId {
                return id
            }
        } else if let response = try? JSONDecoder().decode(SceneSaveResponse.self, from: data) {
            guard response.status.lowercased() == "success" else {
                let reason = response.payload?.reason ?? response.payload?.type
                let detail = [response.status, reason].compactMap { $0 }.joined(separator: ": ")
                throw LedFXError.apiError(detail)
            }
        }

        let scenes = try await listScenes()
        if let match = scenes.first(where: { $0.value.name == scene.name }) {
            return match.key
        }
        throw LedFXError.apiError("Scene creation succeeded but id was not returned")
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
        let data = try await getData(path: "/api/virtuals")

        if let wrapped = try? JSONDecoder().decode(LedFXVirtualsResponse.self, from: data) {
            guard wrapped.status.lowercased() == "success" else {
                throw LedFXError.apiError(wrapped.status)
            }
            return wrapped.virtuals
        }

        do {
            return try JSONDecoder().decode([String: LedFXVirtual].self, from: data)
        } catch {
            throw LedFXError.decodingError(error)
        }
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
    public func getEffect(virtualId: String) async throws -> LedFXEffect? {
        let virtual: LedFXVirtual = try await getVirtual(id: virtualId)
        return virtual.effect
    }
    
    /// Set effect on a virtual
    public func setEffect(virtualId: String, effect: LedFXEffect) async throws {
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

    // MARK: - Playlists

    /// List playlists
    public func listPlaylists() async throws -> LedFXPlaylistsResponse {
        try await get(path: "/api/playlists")
    }

    /// Start a playlist by id
    public func startPlaylist(id: String) async throws {
        let request = PlaylistActionRequest(id: id, action: "start")
        try await put(path: "/api/playlists", body: request)
    }

    /// Stop the current playlist
    public func stopPlaylist() async throws {
        let request = PlaylistActionRequest(id: nil, action: "stop")
        try await put(path: "/api/playlists", body: request)
    }

    // MARK: - Effects Catalog

    /// List active effects per virtual
    public func listEffectsCatalog() async throws -> LedFXEffectsResponse {
        try await get(path: "/api/effects")
    }
    
    // MARK: - HTTP Helpers
    
    private func get<T: Decodable>(path: String) async throws -> T {
        let data = try await getData(path: path)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw LedFXError.decodingError(error)
        }
    }

    private func getData(path: String) async throws -> Data {
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

        return data
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
        _ = try await postData(path: path, body: body)
    }

    private func postData<T: Encodable>(path: String, body: T) async throws -> Data {
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
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LedFXError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw LedFXError.httpError(statusCode: httpResponse.statusCode)
        }

        return data
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

    private static func normalizeSceneVirtuals(_ virtuals: [String: VirtualAction]) -> [String: VirtualAction] {
        virtuals.mapValues { action in
            switch action.action {
            case .forceblack:
                let type = action.type ?? "singleColor"
                let config = action.config ?? EffectConfig(["color": .string("#000000")])
                return VirtualAction(action: .forceblack, type: type, config: config, preset: action.preset)
            case .ignore:
                let type = action.type ?? ""
                let config = action.config ?? EffectConfig()
                return VirtualAction(action: .ignore, type: type, config: config, preset: action.preset)
            case .activate, .stop:
                return action
            }
        }
    }
}

// MARK: - Scene Save Request/Response

private struct SceneSaveRequest: Encodable {
    let id: String
    let name: String
    let sceneImage: String?
    let sceneTags: String?
    let virtuals: [String: VirtualAction]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case sceneImage = "scene_image"
        case sceneTags = "scene_tags"
        case virtuals
    }

    init(id: String, scene: LedFXScene, virtuals: [String: VirtualAction]? = nil) {
        self.id = id
        self.name = scene.name
        self.sceneImage = scene.sceneImage
        self.sceneTags = scene.sceneTags
        self.virtuals = virtuals ?? scene.virtuals
    }
}

private struct SceneCreateRequest: Encodable {
    let name: String
    let sceneImage: String?
    let sceneTags: String?
    let virtuals: [String: VirtualAction]

    enum CodingKeys: String, CodingKey {
        case name
        case sceneImage = "scene_image"
        case sceneTags = "scene_tags"
        case virtuals
    }

    init(scene: LedFXScene, virtuals: [String: VirtualAction]? = nil) {
        self.name = scene.name
        self.sceneImage = scene.sceneImage
        self.sceneTags = scene.sceneTags
        self.virtuals = virtuals ?? scene.virtuals
    }
}

private struct SceneSaveResponse: Decodable {
    let status: String
    let payload: SceneSavePayload?
}

private struct SceneSavePayload: Decodable {
    let type: String?
    let reason: String?
}

private struct SceneCreateResponse: Decodable {
    let status: String
    let payload: SceneCreatePayload?
}

private struct SceneCreatePayload: Decodable {
    let id: String?
    let sceneId: String?
    let type: String?
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sceneId = "scene_id"
        case type
        case reason
    }
}

private struct PlaylistActionRequest: Encodable {
    let id: String?
    let action: String
}

// MARK: - Errors

public enum LedFXError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case encodingError(Error)
    case decodingError(Error)
    case connectionFailed
    case apiError(String)
    
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
        case .apiError(let status):
            return "LedFX API error: \(status)"
        }
    }
}

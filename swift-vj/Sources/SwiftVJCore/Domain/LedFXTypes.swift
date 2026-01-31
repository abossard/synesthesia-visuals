// LedFXTypes.swift - Domain types for LedFX integration
// Following Grokking Simplicity: immutable data types

import Foundation

// MARK: - LedFX Info

public struct LedFXInfo: Codable, Sendable, Equatable {
    public let url: String
    public let name: String
    public let version: String
    
    public init(url: String, name: String, version: String) {
        self.url = url
        self.name = name
        self.version = version
    }
}

// MARK: - Scene

public struct LedFXScene: Codable, Sendable, Equatable {
    public let name: String
    public let sceneImage: String?
    public let sceneTags: String?
    public let virtuals: [String: VirtualAction]
    public let active: Bool
    
    enum CodingKeys: String, CodingKey {
        case name
        case sceneImage = "scene_image"
        case sceneTags = "scene_tags"
        case virtuals
        case active
    }
    
    public init(
        name: String,
        sceneImage: String? = nil,
        sceneTags: String? = nil,
        virtuals: [String: VirtualAction],
        active: Bool = false
    ) {
        self.name = name
        self.sceneImage = sceneImage
        self.sceneTags = sceneTags
        self.virtuals = virtuals
        self.active = active
    }
    
    /// Create a new scene with updated active status
    public func withActive(_ active: Bool) -> LedFXScene {
        LedFXScene(
            name: name,
            sceneImage: sceneImage,
            sceneTags: sceneTags,
            virtuals: virtuals,
            active: active
        )
    }
}

// MARK: - Virtual Action

public struct VirtualAction: Codable, Sendable, Equatable {
    public let action: ActionType
    public let type: String?
    public let config: EffectConfig?
    public let preset: String?
    
    public enum ActionType: String, Codable, Sendable {
        case ignore
        case activate
        case stop
        case forceblack
    }
    
    public init(
        action: ActionType,
        type: String? = nil,
        config: EffectConfig? = nil,
        preset: String? = nil
    ) {
        self.action = action
        self.type = type
        self.config = config
        self.preset = preset
    }
}

// MARK: - Effect Config

/// Dynamic effect configuration - stores arbitrary key-value pairs
public struct EffectConfig: Codable, Sendable, Equatable {
    public let values: [String: EffectValue]
    
    public init(_ values: [String: EffectValue] = [:]) {
        self.values = values
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: EffectValue].self)
        self.values = dict
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
    
    public subscript(_ key: String) -> EffectValue? {
        get { values[key] }
    }
    
    /// Create a new config with an updated value
    public func with(_ key: String, _ value: EffectValue) -> EffectConfig {
        var newValues = values
        newValues[key] = value
        return EffectConfig(newValues)
    }
}

/// Represents possible effect configuration values
public enum EffectValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported effect value type"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Virtual Device

public struct LedFXVirtual: Codable, Sendable, Equatable {
    public let id: String
    public let config: VirtualConfig?
    public let effect: Effect?
    public let activePresetId: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case config
        case effect
        case activePresetId = "active_preset_id"
    }
    
    public init(
        id: String,
        config: VirtualConfig? = nil,
        effect: Effect? = nil,
        activePresetId: String? = nil
    ) {
        self.id = id
        self.config = config
        self.effect = effect
        self.activePresetId = activePresetId
    }
}

// MARK: - Virtual Config

public struct VirtualConfig: Codable, Sendable, Equatable {
    public let brightness: Double?
    public let name: String?
    
    public init(brightness: Double? = nil, name: String? = nil) {
        self.brightness = brightness
        self.name = name
    }
}

// MARK: - Effect

public struct Effect: Codable, Sendable, Equatable {
    public let type: String
    public let config: EffectConfig
    
    public init(type: String, config: EffectConfig) {
        self.type = type
        self.config = config
    }
}

// MARK: - Preset

public struct LedFXPreset: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let config: EffectConfig
    
    public init(id: String, name: String, config: EffectConfig) {
        self.id = id
        self.name = name
        self.config = config
    }
}

// MARK: - Schema

public struct LedFXSchema: Codable, Sendable, Equatable {
    public let type: String
    public let properties: [String: SchemaProperty]
    
    public init(type: String, properties: [String: SchemaProperty]) {
        self.type = type
        self.properties = properties
    }
}

public struct SchemaProperty: Codable, Sendable, Equatable {
    public let type: String
    public let description: String?
    public let defaultValue: EffectValue?
    
    enum CodingKeys: String, CodingKey {
        case type
        case description
        case defaultValue = "default"
    }
    
    public init(type: String, description: String? = nil, defaultValue: EffectValue? = nil) {
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
    }
}

// MARK: - Scene Action (for activation/deactivation)

public struct SceneActionRequest: Codable, Sendable, Equatable {
    public let id: String
    public let action: SceneAction
    public let activateIn: Int?
    
    public enum SceneAction: String, Codable, Sendable {
        case activate
        case deactivate
        case rename
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case action
        case activateIn = "activate_in"
    }
    
    public init(id: String, action: SceneAction, activateIn: Int? = nil) {
        self.id = id
        self.action = action
        self.activateIn = activateIn
    }
}

// MARK: - Oneshot Request

public struct OneshotRequest: Codable, Sendable, Equatable {
    public let tool: String
    public let color: String
    public let ramp: Int
    public let hold: Int
    public let fade: Int
    public let brightness: Double
    
    public init(
        color: String,
        ramp: Int = 0,
        hold: Int = 100,
        fade: Int = 200,
        brightness: Double = 1.0
    ) {
        self.tool = "oneshot"
        self.color = color
        self.ramp = ramp
        self.hold = hold
        self.fade = fade
        self.brightness = brightness
    }
}

// MARK: - Response Types

public struct LedFXResponse<T: Codable>: Codable {
    public let status: String
    public let data: T?
    
    public init(status: String, data: T? = nil) {
        self.status = status
        self.data = data
    }
}

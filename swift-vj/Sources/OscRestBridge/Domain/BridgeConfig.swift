// BridgeConfig.swift - Configuration domain models
// Following Grokking Simplicity: immutable data types

import Foundation
import Yams

// MARK: - Root Config

public struct BridgeConfig: Codable, Sendable, Equatable {
    public let version: Int
    public let server: ServerConfig
    public let slots: [String: SlotConfig]
    public let scenes: [String: SceneConfig]
    public let playlists: [String: PlaylistConfig]
    public let playlist_controls: [String: PlaylistControlConfig]
    public let oneshots: [String: OneshotConfig]
    public let params: [String: ParamConfig]
    
    public init(
        version: Int,
        server: ServerConfig,
        slots: [String: SlotConfig],
        scenes: [String: SceneConfig],
        playlists: [String: PlaylistConfig],
        playlist_controls: [String: PlaylistControlConfig],
        oneshots: [String: OneshotConfig],
        params: [String: ParamConfig]
    ) {
        self.version = version
        self.server = server
        self.slots = slots
        self.scenes = scenes
        self.playlists = playlists
        self.playlist_controls = playlist_controls
        self.oneshots = oneshots
        self.params = params
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case server
        case slots
        case scenes
        case playlists
        case playlist_controls
        case oneshots
        case params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        server = try container.decode(ServerConfig.self, forKey: .server)
        slots = try container.decode([String: SlotConfig].self, forKey: .slots)
        scenes = try container.decode([String: SceneConfig].self, forKey: .scenes)
        playlists = try container.decodeIfPresent([String: PlaylistConfig].self, forKey: .playlists) ?? [:]
        playlist_controls = try container.decodeIfPresent([String: PlaylistControlConfig].self, forKey: .playlist_controls) ?? [:]
        oneshots = try container.decode([String: OneshotConfig].self, forKey: .oneshots)
        params = try container.decode([String: ParamConfig].self, forKey: .params)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(server, forKey: .server)
        try container.encode(slots, forKey: .slots)
        try container.encode(scenes, forKey: .scenes)
        try container.encode(playlists, forKey: .playlists)
        try container.encode(playlist_controls, forKey: .playlist_controls)
        try container.encode(oneshots, forKey: .oneshots)
        try container.encode(params, forKey: .params)
    }
}

// MARK: - Server Config

public struct ServerConfig: Codable, Sendable, Equatable {
    public let osc_listen: OSCListenConfig
    public let http: HTTPConfig
    
    public init(osc_listen: OSCListenConfig, http: HTTPConfig) {
        self.osc_listen = osc_listen
        self.http = http
    }
}

public struct OSCListenConfig: Codable, Sendable, Equatable {
    public let host: String
    public let port: UInt16
    
    public init(host: String, port: UInt16) {
        self.host = host
        self.port = port
    }
}

public struct HTTPConfig: Codable, Sendable, Equatable {
    public let base_url: String
    public let timeout_ms: Int
    public let default_headers: [String: String]?
    
    public init(base_url: String, timeout_ms: Int, default_headers: [String: String]? = nil) {
        self.base_url = base_url
        self.timeout_ms = timeout_ms
        self.default_headers = default_headers
    }
}

// MARK: - Slot Config

public struct SlotConfig: Codable, Sendable, Equatable {
    public let name: String
    public let targets: SlotTargets
    public let blackout: BlackoutConfig?
    
    public init(name: String, targets: SlotTargets, blackout: BlackoutConfig? = nil) {
        self.name = name
        self.targets = targets
        self.blackout = blackout
    }
}

public struct SlotTargets: Codable, Sendable, Equatable {
    public let virtual_ids: [String]
    
    public init(virtual_ids: [String]) {
        self.virtual_ids = virtual_ids
    }
}

public struct BlackoutConfig: Codable, Sendable, Equatable {
    public let scene: String
    public let restore_previous_scene: Bool
    
    public init(scene: String, restore_previous_scene: Bool) {
        self.scene = scene
        self.restore_previous_scene = restore_previous_scene
    }
}

// MARK: - Scene Config

public struct SceneConfig: Codable, Sendable, Equatable {
    public let id: String
    public let on_activate: SceneAction
    public let on_deactivate: SceneDeactivateAction?
    
    public init(id: String, on_activate: SceneAction, on_deactivate: SceneDeactivateAction? = nil) {
        self.id = id
        self.on_activate = on_activate
        self.on_deactivate = on_deactivate
    }
}

public struct SceneAction: Codable, Sendable, Equatable {
    public let request: RequestTemplate
    
    public init(request: RequestTemplate) {
        self.request = request
    }
}

public struct SceneDeactivateAction: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let request: RequestTemplate
    
    public init(enabled: Bool, request: RequestTemplate) {
        self.enabled = enabled
        self.request = request
    }
}

// MARK: - Playlist Config

public struct PlaylistConfig: Codable, Sendable, Equatable {
    public let id: String
    public let on_start: RequestTemplate

    public init(id: String, on_start: RequestTemplate) {
        self.id = id
        self.on_start = on_start
    }
}

public struct PlaylistControlConfig: Codable, Sendable, Equatable {
    public let action: String
    public let request: RequestTemplate

    public init(action: String, request: RequestTemplate) {
        self.action = action
        self.request = request
    }
}

// MARK: - Oneshot Config

public struct OneshotConfig: Codable, Sendable, Equatable {
    public let request: RequestTemplate
    
    public init(request: RequestTemplate) {
        self.request = request
    }
}

// MARK: - Param Config

public struct ParamConfig: Codable, Sendable, Equatable {
    public let input: ParamInput
    public let scale: ParamScale
    public let request: ParamRequest
    
    public init(input: ParamInput, scale: ParamScale, request: ParamRequest) {
        self.input = input
        self.scale = scale
        self.request = request
    }
}

public struct ParamInput: Codable, Sendable, Equatable {
    public let accepted: [String]
    public let default_mode: String
    
    public init(accepted: [String], default_mode: String) {
        self.accepted = accepted
        self.default_mode = default_mode
    }
}

public struct ParamScale: Codable, Sendable, Equatable {
    public let type: String  // "linear" | "curve"
    public let curve: String?  // "linear" | "square" | "sqrt" | "exp"
    public let in_min: Double
    public let in_max: Double
    public let out_min: Double
    public let out_max: Double
    
    public init(type: String, curve: String? = nil, in_min: Double, in_max: Double, out_min: Double, out_max: Double) {
        self.type = type
        self.curve = curve
        self.in_min = in_min
        self.in_max = in_max
        self.out_min = out_min
        self.out_max = out_max
    }
}

public struct ParamRequest: Codable, Sendable, Equatable {
    public let method: String
    public let path: String
    public let body_template: AnyCodable?
    public let patch_ops: [PatchOp]?
    
    public init(method: String, path: String, body_template: AnyCodable? = nil, patch_ops: [PatchOp]? = nil) {
        self.method = method
        self.path = path
        self.body_template = body_template
        self.patch_ops = patch_ops
    }
}

// MARK: - Request Template

public struct RequestTemplate: Codable, Sendable, Equatable {
    public let method: String
    public let path: String
    public let body: AnyCodable?
    public let headers: [String: String]?
    
    public init(method: String, path: String, body: AnyCodable? = nil, headers: [String: String]? = nil) {
        self.method = method
        self.path = path
        self.body = body
        self.headers = headers
    }
}

// MARK: - Patch Operations

public struct PatchOp: Codable, Sendable, Equatable {
    public let op: String  // "set" | "merge" | "delete"
    public let pointer: String  // JSON Pointer
    public let value: AnyCodable?
    
    public init(op: String, pointer: String, value: AnyCodable? = nil) {
        self.op = op
        self.pointer = pointer
        self.value = value
    }
}

// MARK: - AnyCodable Helper

public struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    public let value: Any
    
    public init(_ value: Any) {
        self.value = value
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type"
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported type")
            )
        }
    }
    
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        // Simple equality for testing
        return "\(lhs.value)" == "\(rhs.value)"
    }
}

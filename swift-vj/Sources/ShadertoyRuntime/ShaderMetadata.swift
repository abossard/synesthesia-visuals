// ShaderMetadata.swift - Shader metadata schema and types
// Shadertoy Runtime for SwiftUI + Metal

import Foundation

// MARK: - Shader Pass Configuration

/// Size mode for render pass output
public enum SizeMode: String, Codable, Sendable {
    case screen = "screen"   // Match viewport size
    case fixed = "fixed"     // Fixed pixel dimensions
    case scale = "scale"     // Fraction of screen size
}

/// Sampler type (2D texture or Cube map)
public enum SamplerType: String, Codable, Sendable {
    case texture2D = "2D"
    case textureCube = "Cube"
}

/// Texture filter mode
public enum FilterMode: String, Codable, Sendable {
    case nearest = "nearest"
    case linear = "linear"
    case mipmap = "mipmap"
}

/// Texture wrap mode
public enum WrapMode: String, Codable, Sendable {
    case clamp = "clamp"
    case `repeat` = "repeat"
    case mirror = "mirror"
}

/// Channel input source type
public enum ChannelSource: String, Codable, Sendable {
    case none = "none"           // No input (1x1 black texture)
    case file = "file"           // External texture file
    case buffer = "buffer"       // Another pass's current frame output
    case bufferPrev = "bufferPrev" // Previous frame output (ping-pong)
    case noise = "noise"         // Procedural noise texture
    case keyboard = "keyboard"   // Keyboard state texture
    case video = "video"         // Video input
    case audioFFT = "audioFFT"   // Audio FFT spectrum
}

/// Pass name (matches Shadertoy convention)
public enum PassName: String, Codable, Sendable, CaseIterable {
    case bufA = "BufA"
    case bufB = "BufB"
    case bufC = "BufC"
    case bufD = "BufD"
    case image = "Image"

    /// Source file name for this pass
    public var sourceFileName: String {
        switch self {
        case .bufA: return "bufa.glsl"
        case .bufB: return "bufb.glsl"
        case .bufC: return "bufc.glsl"
        case .bufD: return "bufd.glsl"
        case .image: return "image.glsl"
        }
    }

    /// Render order (buffers before image)
    public var renderOrder: Int {
        switch self {
        case .bufA: return 0
        case .bufB: return 1
        case .bufC: return 2
        case .bufD: return 3
        case .image: return 4
        }
    }
}

// MARK: - Channel Configuration

/// Channel input configuration
public struct ChannelConfig: Codable, Sendable {
    public let index: Int            // 0-3
    public let source: ChannelSource
    public let ref: String?          // Path or pass name
    public let samplerType: SamplerType
    public let filter: FilterMode
    public let wrap: WrapMode
    public let vflip: Bool

    public init(
        index: Int,
        source: ChannelSource = .none,
        ref: String? = nil,
        samplerType: SamplerType = .texture2D,
        filter: FilterMode = .linear,
        wrap: WrapMode = .repeat,
        vflip: Bool = false
    ) {
        self.index = index
        self.source = source
        self.ref = ref
        self.samplerType = samplerType
        self.filter = filter
        self.wrap = wrap
        self.vflip = vflip
    }

    /// Default empty channel
    public static func empty(index: Int) -> ChannelConfig {
        ChannelConfig(index: index, source: .none)
    }
}

// MARK: - Pass Output Configuration

/// Output size configuration for a pass
public struct OutputConfig: Codable, Sendable {
    public let sizeMode: SizeMode
    public let width: Int?
    public let height: Int?
    public let scale: Float?

    public init(
        sizeMode: SizeMode = .screen,
        width: Int? = nil,
        height: Int? = nil,
        scale: Float? = nil
    ) {
        self.sizeMode = sizeMode
        self.width = width
        self.height = height
        self.scale = scale
    }

    /// Calculate actual dimensions for a given viewport
    public func dimensions(viewportWidth: Int, viewportHeight: Int) -> (width: Int, height: Int) {
        switch sizeMode {
        case .screen:
            return (viewportWidth, viewportHeight)
        case .fixed:
            return (width ?? viewportWidth, height ?? viewportHeight)
        case .scale:
            let s = scale ?? 1.0
            return (Int(Float(viewportWidth) * s), Int(Float(viewportHeight) * s))
        }
    }

    /// Default screen-sized output
    public static let screen = OutputConfig()
}

// MARK: - Pass Configuration

/// Configuration for a single render pass
public struct PassConfig: Codable, Sendable {
    public let name: PassName
    public let output: OutputConfig
    public let pingPong: Bool
    public let channels: [ChannelConfig]

    public init(
        name: PassName,
        output: OutputConfig = .screen,
        pingPong: Bool = false,
        channels: [ChannelConfig] = []
    ) {
        self.name = name
        self.output = output
        self.pingPong = pingPong
        // Ensure all 4 channels are defined
        var allChannels: [ChannelConfig] = []
        for i in 0..<4 {
            if let existing = channels.first(where: { $0.index == i }) {
                allChannels.append(existing)
            } else {
                allChannels.append(.empty(index: i))
            }
        }
        self.channels = allChannels
    }

    /// Check if this pass requires ping-pong (explicit or via bufferPrev reference)
    public var requiresPingPong: Bool {
        pingPong || channels.contains { $0.source == .bufferPrev }
    }
}

// MARK: - Global Shader Configuration

/// Global shader metadata
public struct GlobalConfig: Codable, Sendable {
    public let name: String?
    public let author: String?
    public let description: String?
    public let tags: [String]?
    public let defaultFilter: FilterMode?
    public let defaultWrap: WrapMode?

    public init(
        name: String? = nil,
        author: String? = nil,
        description: String? = nil,
        tags: [String]? = nil,
        defaultFilter: FilterMode? = nil,
        defaultWrap: WrapMode? = nil
    ) {
        self.name = name
        self.author = author
        self.description = description
        self.tags = tags
        self.defaultFilter = defaultFilter
        self.defaultWrap = defaultWrap
    }

    public static let empty = GlobalConfig()
}

// MARK: - Shader Metadata (shader.json)

/// Complete shader metadata matching shader.json schema
public struct ShaderMetadata: Codable, Sendable {
    public let passes: [PassConfig]
    public let global: GlobalConfig?

    public init(passes: [PassConfig], global: GlobalConfig? = nil) {
        self.passes = passes
        self.global = global
    }

    /// Default single-pass Image shader
    public static let defaultSinglePass = ShaderMetadata(
        passes: [PassConfig(name: .image)]
    )

    /// Sorted passes in render order
    public var sortedPasses: [PassConfig] {
        passes.sorted { $0.name.renderOrder < $1.name.renderOrder }
    }

    /// Check if this is a multi-pass shader
    public var isMultiPass: Bool {
        passes.count > 1 || passes.contains { $0.name != .image }
    }

    /// Get pass config by name
    public func pass(named name: PassName) -> PassConfig? {
        passes.first { $0.name == name }
    }
}

// MARK: - Shader Folder Structure

/// Represents a shader folder with all its components
public struct ShaderFolder: Sendable {
    public let url: URL
    public let name: String
    public let metadata: ShaderMetadata
    public let hasCommon: Bool
    public let availablePasses: [PassName]

    /// Initialize from a shader folder URL
    public init(url: URL) throws {
        self.url = url
        self.name = url.lastPathComponent

        let fm = FileManager.default

        // Check which passes exist
        var passes: [PassName] = []
        for passName in PassName.allCases {
            let passFile = url.appendingPathComponent(passName.sourceFileName)
            if fm.fileExists(atPath: passFile.path) {
                passes.append(passName)
            }
        }

        // Handle legacy single-file shaders
        if passes.isEmpty {
            // Check for legacy formats
            let legacyFormats = ["image.txt", "shader.glsl", "shader.txt", "\(url.lastPathComponent).glsl", "\(url.lastPathComponent).txt"]
            for format in legacyFormats {
                let legacyFile = url.appendingPathComponent(format)
                if fm.fileExists(atPath: legacyFile.path) {
                    passes.append(.image)
                    break
                }
            }
        }

        self.availablePasses = passes

        // Check for common.glsl
        let commonFile = url.appendingPathComponent("common.glsl")
        self.hasCommon = fm.fileExists(atPath: commonFile.path)

        // Load or generate metadata
        let metadataFile = url.appendingPathComponent("shader.json")
        if fm.fileExists(atPath: metadataFile.path) {
            let data = try Data(contentsOf: metadataFile)
            self.metadata = try JSONDecoder().decode(ShaderMetadata.self, from: data)
        } else {
            // Generate default metadata based on available passes
            let passConfigs = passes.map { PassConfig(name: $0) }
            self.metadata = ShaderMetadata(
                passes: passConfigs.isEmpty ? [PassConfig(name: .image)] : passConfigs,
                global: GlobalConfig(name: url.lastPathComponent)
            )
        }
    }

    /// Get source file URL for a pass
    public func sourceURL(for pass: PassName) -> URL? {
        let passFile = url.appendingPathComponent(pass.sourceFileName)
        if FileManager.default.fileExists(atPath: passFile.path) {
            return passFile
        }

        // Legacy format support
        if pass == .image {
            let legacyFormats = ["image.txt", "shader.glsl", "shader.txt", "\(name).glsl", "\(name).txt"]
            for format in legacyFormats {
                let legacyFile = url.appendingPathComponent(format)
                if FileManager.default.fileExists(atPath: legacyFile.path) {
                    return legacyFile
                }
            }
        }

        return nil
    }

    /// Get common.glsl URL if it exists
    public var commonURL: URL? {
        guard hasCommon else { return nil }
        return url.appendingPathComponent("common.glsl")
    }
}

// MARK: - JSON Schema

/// JSON Schema definition for shader.json validation
public enum ShaderJSONSchema {
    public static let schemaVersion = "1.0.0"

    /// Generate JSON Schema as a string
    public static var schemaJSON: String {
        """
        {
          "$schema": "http://json-schema.org/draft-07/schema#",
          "$id": "https://shadertoy-runtime/shader.schema.json",
          "title": "Shadertoy Shader Metadata",
          "description": "Configuration for Shadertoy-style GLSL shaders",
          "type": "object",
          "required": ["passes"],
          "properties": {
            "passes": {
              "type": "array",
              "description": "Render passes in execution order",
              "items": {
                "type": "object",
                "required": ["name"],
                "properties": {
                  "name": {
                    "type": "string",
                    "enum": ["BufA", "BufB", "BufC", "BufD", "Image"],
                    "description": "Pass identifier"
                  },
                  "output": {
                    "type": "object",
                    "properties": {
                      "sizeMode": {
                        "type": "string",
                        "enum": ["screen", "fixed", "scale"],
                        "default": "screen"
                      },
                      "width": { "type": "integer", "minimum": 1 },
                      "height": { "type": "integer", "minimum": 1 },
                      "scale": { "type": "number", "minimum": 0.01, "maximum": 4.0 }
                    }
                  },
                  "pingPong": {
                    "type": "boolean",
                    "default": false,
                    "description": "Enable double-buffering for feedback effects"
                  },
                  "channels": {
                    "type": "array",
                    "maxItems": 4,
                    "items": {
                      "type": "object",
                      "required": ["index"],
                      "properties": {
                        "index": {
                          "type": "integer",
                          "minimum": 0,
                          "maximum": 3
                        },
                        "source": {
                          "type": "string",
                          "enum": ["none", "file", "buffer", "bufferPrev", "noise", "keyboard", "video", "audioFFT"],
                          "default": "none"
                        },
                        "ref": {
                          "type": "string",
                          "description": "Path to texture file or pass name (BufA, BufB, etc.)"
                        },
                        "samplerType": {
                          "type": "string",
                          "enum": ["2D", "Cube"],
                          "default": "2D"
                        },
                        "filter": {
                          "type": "string",
                          "enum": ["nearest", "linear", "mipmap"],
                          "default": "linear"
                        },
                        "wrap": {
                          "type": "string",
                          "enum": ["clamp", "repeat", "mirror"],
                          "default": "repeat"
                        },
                        "vflip": {
                          "type": "boolean",
                          "default": false
                        }
                      }
                    }
                  }
                }
              }
            },
            "global": {
              "type": "object",
              "properties": {
                "name": { "type": "string" },
                "author": { "type": "string" },
                "description": { "type": "string" },
                "tags": {
                  "type": "array",
                  "items": { "type": "string" }
                },
                "defaultFilter": {
                  "type": "string",
                  "enum": ["nearest", "linear", "mipmap"]
                },
                "defaultWrap": {
                  "type": "string",
                  "enum": ["clamp", "repeat", "mirror"]
                }
              }
            }
          }
        }
        """
    }
}

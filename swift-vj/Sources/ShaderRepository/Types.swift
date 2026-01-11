// Types.swift - Canonical shader types
// Single source of truth for all shader-related types

import Foundation

// MARK: - ShaderID

/// Type-safe shader identifier
public struct ShaderID: Hashable, Codable, RawRepresentable, Sendable, CustomStringConvertible {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(_ name: String) {
        self.rawValue = name
    }
    
    public var description: String { rawValue }
}

// MARK: - ShaderRating

/// Shader quality rating for filtering
public enum ShaderRating: Int, Sendable, Codable, Comparable, CaseIterable {
    case best = 1
    case good = 2
    case normal = 3
    case mask = 4
    case skip = 5
    
    public static func < (lhs: ShaderRating, rhs: ShaderRating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    public var displayName: String {
        switch self {
        case .best: return "Best"
        case .good: return "Good"
        case .normal: return "Normal"
        case .mask: return "Mask"
        case .skip: return "Skip"
        }
    }
}

// MARK: - Phase

/// DJ set phase for shader categorization
public enum Phase: String, Sendable, Codable, CaseIterable, Hashable {
    case disco
    case buildup
    case peak
    case release
    case feature
    
    /// Display name for UI
    public var displayName: String {
        switch self {
        case .disco: return "Disco/Jungle"
        case .buildup: return "Buildup"
        case .peak: return "Peak"
        case .release: return "Release"
        case .feature: return "Feature"
        }
    }

    /// Description for UI tooltips/help text
    public var description: String {
        switch self {
        case .disco:
            return "Slower songs, easy to get into, jungle style beats"
        case .buildup:
            return "Stronger songs, harder, bridge from starters"
        case .peak:
            return "Strong, fast, dark, loud, high energy"
        case .release:
            return "After peaks, let people breathe. Atmospheric"
        case .feature:
            return "Fun, special, erratic songs. Cool remixes"
        }
    }

    /// Suggested energy range (0.0-1.0)
    public var energyRange: ClosedRange<Double> {
        switch self {
        case .disco: return 0.2...0.5
        case .buildup: return 0.4...0.7
        case .peak: return 0.7...1.0
        case .release: return 0.4...0.6
        case .feature: return 0.3...0.9
        }
    }

    /// Icon for UI (SF Symbol name)
    public var iconName: String {
        switch self {
        case .disco: return "music.note.house"
        case .buildup: return "arrow.up.right"
        case .peak: return "bolt.fill"
        case .release: return "wind"
        case .feature: return "star.fill"
        }
    }
    
    /// Parse from string (case-insensitive)
    public static func from(_ string: String) -> Phase? {
        Phase(rawValue: string.lowercased())
    }
    
    /// Parse phase strings to set
    public static func fromStrings(_ strings: [String]) -> Set<Phase> {
        Set(strings.compactMap { Phase(rawValue: $0.lowercased()) })
    }
}

// MARK: - VisualMetadata

/// Visual metadata from analysis
public struct VisualMetadata: Sendable, Codable, Equatable {
    public let status: String?
    public let reason: String?
    public let contrast: String?
    public let saturation: String?
    public let motion: String?
    public let symmetry: String?
    
    public init(
        status: String? = nil,
        reason: String? = nil,
        contrast: String? = nil,
        saturation: String? = nil,
        motion: String? = nil,
        symmetry: String? = nil
    ) {
        self.status = status
        self.reason = reason
        self.contrast = contrast
        self.saturation = saturation
        self.motion = motion
        self.symmetry = symmetry
    }
    
    /// Check if shader renders black/broken
    public var isBlack: Bool {
        status == "black"
    }
}

// MARK: - ShaderAnalysis

/// Shader analysis result - matches existing .analysis.json schema
public struct ShaderAnalysis: Sendable, Codable, Equatable {
    public let title: String
    public let description: String
    public let mood: String
    public let energy: Double
    public let colors: [String]
    public let effects: [String]
    public let geometry: [String]
    public let objects: [String]
    public let complexity: String
    public let visualMetadata: VisualMetadata?
    public let djPhases: [String]?
    
    enum CodingKeys: String, CodingKey {
        case title, description, mood, energy, colors, effects, geometry, objects, complexity
        case visualMetadata = "visual_metadata"
        case djPhases = "dj_phases"
    }
    
    public init(
        title: String,
        description: String,
        mood: String,
        energy: Double,
        colors: [String],
        effects: [String],
        geometry: [String],
        objects: [String],
        complexity: String,
        visualMetadata: VisualMetadata? = nil,
        djPhases: [String]? = nil
    ) {
        self.title = title
        self.description = description
        self.mood = mood
        self.energy = energy
        self.colors = colors
        self.effects = effects
        self.geometry = geometry
        self.objects = objects
        self.complexity = complexity
        self.visualMetadata = visualMetadata
        self.djPhases = djPhases
    }
    
    /// Convert dj_phases strings to Phase enum set
    public var phases: Set<Phase> {
        Phase.fromStrings(djPhases ?? [])
    }
    
    /// Check if shader renders black
    public var isBlack: Bool {
        visualMetadata?.isBlack ?? false
    }
    
    /// Feature vector for matching [energy, moodValence, colorWarmth, motionSpeed]
    public var featureVector: [Double] {
        // Map mood to valence
        let valence: Double = switch mood.lowercased() {
        case "energetic", "bright", "happy": 0.7
        case "calm", "peaceful", "dreamy": 0.3
        case "dark", "aggressive": -0.5
        case "psychedelic", "hypnotic": 0.0
        default: 0.0
        }
        
        // Estimate motion from complexity
        let motion: Double = switch complexity.lowercased() {
        case "high": 0.8
        case "medium": 0.5
        case "low": 0.2
        default: 0.5
        }
        
        // Color warmth from colors
        let warmColors = ["red", "orange", "yellow", "warm", "fire", "gold"]
        let coolColors = ["blue", "cyan", "purple", "cool", "ice", "teal"]
        let warmCount = colors.filter { c in warmColors.contains(where: { c.lowercased().contains($0) }) }.count
        let coolCount = colors.filter { c in coolColors.contains(where: { c.lowercased().contains($0) }) }.count
        let warmth = warmCount > coolCount ? 0.7 : (coolCount > warmCount ? 0.3 : 0.5)
        
        return [energy, valence, warmth, motion]
    }
}

// MARK: - Shader

/// Complete shader entity - single source of truth
public struct Shader: Sendable, Equatable, Identifiable, Hashable {
    public let id: ShaderID
    public let name: String
    public let sourceURL: URL
    public let folder: String
    public let analysis: ShaderAnalysis?
    public let metalFunctionName: String?
    public let rating: ShaderRating
    
    public init(
        id: ShaderID,
        name: String,
        sourceURL: URL,
        folder: String,
        analysis: ShaderAnalysis? = nil,
        metalFunctionName: String? = nil,
        rating: ShaderRating = .normal
    ) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.folder = folder
        self.analysis = analysis
        self.metalFunctionName = metalFunctionName
        self.rating = rating
    }
    
    /// Convenience initializer from name
    public init(
        name: String,
        sourceURL: URL,
        folder: String = "glsl",
        analysis: ShaderAnalysis? = nil,
        metalFunctionName: String? = nil,
        rating: ShaderRating = .normal
    ) {
        self.id = ShaderID(name)
        self.name = name
        self.sourceURL = sourceURL
        self.folder = folder
        self.analysis = analysis
        self.metalFunctionName = metalFunctionName
        self.rating = rating
    }
    
    // MARK: - Computed Properties
    
    /// Screenshot URL (convention: same name with .png extension)
    public var screenshotURL: URL? {
        let pngURL = sourceURL.deletingPathExtension().appendingPathExtension("png")
        return FileManager.default.fileExists(atPath: pngURL.path) ? pngURL : nil
    }
    
    /// Analysis JSON URL (convention: same name with .analysis.json extension)
    public var analysisURL: URL {
        sourceURL.deletingPathExtension().appendingPathExtension("analysis.json")
    }
    
    /// Energy score (0.0 - 1.0)
    public var energyScore: Double {
        analysis?.energy ?? 0.5
    }
    
    /// Mood string
    public var mood: String {
        analysis?.mood ?? "unknown"
    }
    
    /// Colors array
    public var colors: [String] {
        analysis?.colors ?? []
    }
    
    /// Effects array
    public var effects: [String] {
        analysis?.effects ?? []
    }
    
    /// DJ set phases
    public var phases: Set<Phase> {
        analysis?.phases ?? []
    }
    
    /// Check if shader is black/broken
    public var isBlack: Bool {
        analysis?.isBlack ?? false
    }
    
    /// Check if shader has Metal function (is renderable)
    public var isRenderable: Bool {
        metalFunctionName != nil
    }
    
    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - ShaderMatchResult

/// Result from shader matching
public struct ShaderMatchResult: Sendable, Equatable {
    public let shader: Shader
    public let score: Double
    
    public init(shader: Shader, score: Double) {
        self.shader = shader
        self.score = score
    }
    
    /// Name for convenience
    public var name: String { shader.name }
}

// MARK: - LMStudioConfig

/// Configuration for LM Studio connection
public struct LMStudioConfig: Sendable, Equatable {
    public let baseURL: URL
    public let model: String
    public let timeout: TimeInterval
    public let maxTokens: Int
    public let temperature: Double
    
    public init(
        baseURL: URL = URL(string: "http://localhost:1234")!,
        model: String = "default",
        timeout: TimeInterval = 300,
        maxTokens: Int = 1200,
        temperature: Double = 0.7
    ) {
        self.baseURL = baseURL
        self.model = model
        self.timeout = timeout
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
    
    /// Default localhost configuration
    public static let localhost = LMStudioConfig()
}

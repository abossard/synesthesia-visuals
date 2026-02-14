// Domain Types - Immutable data structures
// Following Grokking Simplicity: pure data with no behavior

import Foundation

// MARK: - Lyrics

/// A single line of lyrics with timing information.
/// Immutable value type following functional core principles.
public struct LyricLine: Sendable, Equatable, Codable {
    public let timeSec: Double
    public let text: String
    public let isRefrain: Bool
    public let keywords: String

    public init(timeSec: Double, text: String, isRefrain: Bool = false, keywords: String = "") {
        self.timeSec = timeSec
        self.text = text
        self.isRefrain = isRefrain
        self.keywords = keywords
    }

    /// Create a new instance with updated refrain flag
    public func withRefrain(_ isRefrain: Bool) -> LyricLine {
        LyricLine(timeSec: timeSec, text: text, isRefrain: isRefrain, keywords: keywords)
    }

    /// Create a new instance with updated keywords
    public func withKeywords(_ keywords: String) -> LyricLine {
        LyricLine(timeSec: timeSec, text: text, isRefrain: isRefrain, keywords: keywords)
    }
}

// MARK: - Track

/// Song metadata. Immutable value type.
public struct Track: Sendable, Equatable, Codable {
    public let artist: String
    public let title: String
    public let album: String
    public let duration: Double
    public let bpm: Double
    public let musicalKey: String

    public init(
        artist: String,
        title: String,
        album: String = "",
        duration: Double = 0,
        bpm: Double = 0,
        musicalKey: String = ""
    ) {
        self.artist = artist
        self.title = title
        self.album = album
        self.duration = duration
        self.bpm = bpm
        self.musicalKey = musicalKey
    }

    /// Unique cache/lookup key
    public var key: String {
        "\(artist)::\(title)"
    }

    /// Human-readable display string
    public var displayName: String {
        "\(artist) - \(title)"
    }
}

// MARK: - Playback State

/// Current playback state. Immutable - create new instances for updates.
public struct PlaybackState: Sendable, Equatable {
    public let track: Track?
    public let position: Double
    public let isPlaying: Bool
    public let lastUpdate: Date
    public let source: String

    public init(
        track: Track? = nil,
        position: Double = 0,
        isPlaying: Bool = false,
        lastUpdate: Date = Date(),
        source: String = "unknown"
    ) {
        self.track = track
        self.position = position
        self.isPlaying = isPlaying
        self.lastUpdate = lastUpdate
        self.source = source
    }

    public var hasTrack: Bool { track != nil }

    /// Progress as percentage (0.0 - 1.0)
    public var progress: Double {
        guard let track = track, track.duration > 0 else { return 0 }
        return min(1.0, max(0.0, position / track.duration))
    }

    /// Create updated state with new position
    public func withPosition(_ position: Double) -> PlaybackState {
        PlaybackState(
            track: track,
            position: position,
            isPlaying: isPlaying,
            lastUpdate: Date(),
            source: source
        )
    }

    /// Create updated state with new track
    public func withTrack(_ track: Track?) -> PlaybackState {
        PlaybackState(
            track: track,
            position: 0,
            isPlaying: isPlaying,
            lastUpdate: Date(),
            source: source
        )
    }
}

// MARK: - Song Categories

/// Single category with score.
public struct SongCategory: Sendable, Equatable, Codable, Comparable {
    public let name: String
    public let score: Double

    public init(name: String, score: Double) {
        self.name = name
        self.score = score
    }

    /// Sort by score descending
    public static func < (lhs: SongCategory, rhs: SongCategory) -> Bool {
        lhs.score > rhs.score
    }
}

/// Collection of category scores for a song.
public struct SongCategories: Sendable, Equatable, Codable {
    public let scores: [String: Double]
    public let primaryMood: String

    public init(scores: [String: Double], primaryMood: String = "") {
        self.scores = scores
        self.primaryMood = primaryMood.isEmpty ? Self.computePrimaryMood(from: scores) : primaryMood
    }

    /// Get top N categories sorted by score
    public func getTop(_ n: Int = 5) -> [SongCategory] {
        scores
            .map { SongCategory(name: $0.key, score: $0.value) }
            .sorted()
            .prefix(n)
            .map { $0 }
    }

    /// Get score for specific category
    public func score(for category: String) -> Double {
        scores[category] ?? 0
    }
    
    /// Estimate energy from category scores (0.0 - 1.0)
    /// High energy categories: energetic, party, intense, upbeat
    /// Low energy categories: chill, calm, sad, melancholy
    public var estimatedEnergy: Double {
        let highEnergy = ["energetic", "party", "intense", "upbeat", "dance", "hype", "power", "driving"]
        let lowEnergy = ["chill", "calm", "sad", "melancholy", "ambient", "relaxed", "slow", "ballad"]
        
        var energy = 0.5  // default neutral
        for (category, score) in scores {
            let cat = category.lowercased()
            if highEnergy.contains(where: { cat.contains($0) }) {
                energy += score * 0.3
            }
            if lowEnergy.contains(where: { cat.contains($0) }) {
                energy -= score * 0.3
            }
        }
        return max(0.0, min(1.0, energy))
    }
    
    /// Estimate valence from category scores (-1.0 to 1.0)
    /// Positive valence: happy, joyful, uplifting
    /// Negative valence: sad, dark, angry
    public var estimatedValence: Double {
        let positive = ["happy", "joyful", "uplifting", "fun", "love", "romantic", "hopeful", "bright"]
        let negative = ["sad", "dark", "angry", "melancholy", "gloomy", "aggressive", "tense", "anxious"]
        
        var valence = 0.0  // default neutral
        for (category, score) in scores {
            let cat = category.lowercased()
            if positive.contains(where: { cat.contains($0) }) {
                valence += score * 0.5
            }
            if negative.contains(where: { cat.contains($0) }) {
                valence -= score * 0.5
            }
        }
        return max(-1.0, min(1.0, valence))
    }

    private static func computePrimaryMood(from scores: [String: Double]) -> String {
        scores.max(by: { $0.value < $1.value })?.key ?? ""
    }
}

// MARK: - Pipeline Result

/// Type-safe step completion status with rich data
public enum PipelineStepStatus: Sendable {
    case lyrics(lineCount: Int, refrainCount: Int, keywordCount: Int)
    case ai(mood: String, energy: Double, valence: Double, keywords: [String], themes: [String])
    case shaders(name: String, score: Double)
    case images(count: Int, folder: String, source: String, cached: Bool)
    case osc(sent: Bool)
    case skipped(reason: String)
    case error(message: String)
    
    /// Human-readable status string for UI
    public var displayText: String {
        switch self {
        case .lyrics(let lineCount, let refrainCount, let keywordCount):
            return "✓ \(lineCount) lines, \(refrainCount) refrain, \(keywordCount) kw"
        case .ai(let mood, let energy, let valence, let keywords, _):
            return "✓ \(mood) (E:\(String(format: "%.1f", energy)) V:\(String(format: "%.1f", valence))) [\(keywords.count) kw]"
        case .shaders(let name, let score):
            return "✓ \(name) (\(Int(score * 100))%)"
        case .images(let count, _, let source, let cached):
            let cacheStr = cached ? "cached" : source
            return "✓ \(count) images (\(cacheStr))"
        case .osc(let sent):
            return sent ? "✓ Sent" : "✗ Not sent"
        case .skipped(let reason):
            return "○ \(reason)"
        case .error(let message):
            return "✗ \(message)"
        }
    }
    
    /// Detailed log output
    public var logDetails: [String] {
        switch self {
        case .lyrics(let lineCount, let refrainCount, let keywordCount):
            return ["Lines: \(lineCount)", "Refrain: \(refrainCount)", "Keywords: \(keywordCount)"]
        case .ai(let mood, let energy, let valence, let keywords, let themes):
            var details = ["Mood: \(mood)", "Energy: \(String(format: "%.2f", energy))", "Valence: \(String(format: "%.2f", valence))"]
            if !keywords.isEmpty { details.append("Keywords: \(keywords.joined(separator: ", "))") }
            if !themes.isEmpty { details.append("Themes: \(themes.joined(separator: ", "))") }
            return details
        case .shaders(let name, let score):
            return ["Shader: \(name)", "Score: \(Int(score * 100))%"]
        case .images(let count, let folder, let source, let cached):
            return ["Count: \(count)", "Source: \(source)", "Cached: \(cached)", "Folder: \(folder)"]
        case .osc(let sent):
            return ["Sent: \(sent)"]
        case .skipped(let reason):
            return ["Reason: \(reason)"]
        case .error(let message):
            return ["Error: \(message)"]
        }
    }
}

/// Result from full pipeline processing.
public struct PipelineResult: Sendable, Equatable, Codable {
    public let artist: String
    public let title: String
    public let album: String
    public let success: Bool

    // Lyrics
    public let lyricsFound: Bool
    public let lyricsLineCount: Int
    public let lyricsLines: [LyricLine]
    public let refrainLines: [String]
    public let lyricsKeywords: [String]

    // Metadata (from LLM)
    public let metadataFound: Bool
    public let plainLyrics: String
    public let keywords: [String]
    public let themes: [String]
    public let visualAdjectives: [String]

    // AI Analysis
    public let aiAvailable: Bool
    public let mood: String
    public let energy: Double
    public let valence: Double
    public let categories: [String: Double]

    // Shader
    public let shaderMatched: Bool
    public let shaderName: String
    public let shaderScore: Double

    // Images
    public let imagesFound: Bool
    public let imagesFolder: String
    public let imagesCount: Int

    // Timing
    public let stepsCompleted: [String]
    public let totalTimeMs: Int

    public init(
        artist: String,
        title: String,
        album: String = "",
        success: Bool = false,
        lyricsFound: Bool = false,
        lyricsLineCount: Int = 0,
        lyricsLines: [LyricLine] = [],
        refrainLines: [String] = [],
        lyricsKeywords: [String] = [],
        metadataFound: Bool = false,
        plainLyrics: String = "",
        keywords: [String] = [],
        themes: [String] = [],
        visualAdjectives: [String] = [],
        aiAvailable: Bool = false,
        mood: String = "",
        energy: Double = 0.5,
        valence: Double = 0,
        categories: [String: Double] = [:],
        shaderMatched: Bool = false,
        shaderName: String = "",
        shaderScore: Double = 0,
        imagesFound: Bool = false,
        imagesFolder: String = "",
        imagesCount: Int = 0,
        stepsCompleted: [String] = [],
        totalTimeMs: Int = 0
    ) {
        self.artist = artist
        self.title = title
        self.album = album
        self.success = success
        self.lyricsFound = lyricsFound
        self.lyricsLineCount = lyricsLineCount
        self.lyricsLines = lyricsLines
        self.refrainLines = refrainLines
        self.lyricsKeywords = lyricsKeywords
        self.metadataFound = metadataFound
        self.plainLyrics = plainLyrics
        self.keywords = keywords
        self.themes = themes
        self.visualAdjectives = visualAdjectives
        self.aiAvailable = aiAvailable
        self.mood = mood
        self.energy = energy
        self.valence = valence
        self.categories = categories
        self.shaderMatched = shaderMatched
        self.shaderName = shaderName
        self.shaderScore = shaderScore
        self.imagesFound = imagesFound
        self.imagesFolder = imagesFolder
        self.imagesCount = imagesCount
        self.stepsCompleted = stepsCompleted
        self.totalTimeMs = totalTimeMs
    }
}

// MARK: - Shader Types

// ShaderRepository module types are available via @_exported import in SwiftVJCore.swift
// Re-export specific types for explicit imports
@_exported import enum ShaderRepository.ShaderRating
@_exported import struct ShaderRepository.Shader
@_exported import struct ShaderRepository.ShaderAnalysis
@_exported import enum ShaderRepository.Phase
// Note: ShaderMatchResult is defined locally below with expanded fields for backwards compat

/// Information about a shader - bridge type for UI/module compatibility
/// Wraps ShaderRepository.Shader with additional UI metadata
public struct ShaderInfo: Sendable, Equatable, Codable, Identifiable {
    public var id: String { path }  // Path is unique even when names are duplicated across folders
    public let name: String
    public let path: String
    public let folder: String  // Folder name (e.g. "glsl", "masks")
    public let energyScore: Double
    public let moodValence: Double
    public let colorWarmth: Double
    public let motionSpeed: Double
    public let mood: String
    public let colors: [String]
    public let effects: [String]
    public let rating: ShaderRating
    public let phases: Set<Phase>?  // DJ set phases this shader fits (optional)

    // Pre-compiled Metal support
    public let metalFunctionName: String?  // Function name in .metallib (nil = runtime compile)
    
    /// Whether this shader is a mask.
    /// Prefer explicit rating, then fall back to folder naming.
    public var isMask: Bool {
        rating == .mask || folder.caseInsensitiveCompare("masks") == .orderedSame
    }

    public init(
        name: String,
        path: String,
        folder: String = "glsl",
        energyScore: Double = 0.5,
        moodValence: Double = 0,
        colorWarmth: Double = 0.5,
        motionSpeed: Double = 0.5,
        mood: String = "",
        colors: [String] = [],
        effects: [String] = [],
        rating: ShaderRating = .normal,
        phases: Set<Phase>? = nil,
        metalFunctionName: String? = nil
    ) {
        self.name = name
        self.path = path
        self.folder = folder
        self.energyScore = energyScore
        self.moodValence = moodValence
        self.colorWarmth = colorWarmth
        self.motionSpeed = motionSpeed
        self.mood = mood
        self.colors = colors
        self.effects = effects
        self.rating = rating
        self.phases = phases
        self.metalFunctionName = metalFunctionName
    }
    
    /// Create from ShaderRepository.Shader
    public init(from shader: ShaderRepository.Shader) {
        self.name = shader.name
        self.path = shader.sourceURL.path
        self.folder = shader.folder
        self.energyScore = shader.analysis?.energy ?? 0.5
        // Map mood to valence using analysis feature vector
        self.moodValence = shader.analysis?.featureVector[1] ?? 0.0
        self.colorWarmth = shader.analysis?.featureVector[2] ?? 0.5
        self.motionSpeed = shader.analysis?.featureVector[3] ?? 0.5
        self.mood = shader.analysis?.mood ?? ""
        self.colors = shader.analysis?.colors ?? []
        self.effects = shader.analysis?.effects ?? []
        self.rating = shader.rating
        self.phases = shader.phases
        self.metalFunctionName = shader.metalFunctionName
    }
}

/// Result from shader matching (SwiftVJCore version with expanded fields)
/// Note: ShaderRepository.ShaderMatchResult has simpler signature (shader, score)
/// This version provides backwards compatibility with existing code
public struct ShaderMatchResult: Sendable, Equatable {
    public let name: String
    public let path: String
    public let score: Double
    public let energyScore: Double
    public let moodValence: Double
    public let mood: String

    public init(
        name: String,
        path: String,
        score: Double,
        energyScore: Double,
        moodValence: Double,
        mood: String
    ) {
        self.name = name
        self.path = path
        self.score = score
        self.energyScore = energyScore
        self.moodValence = moodValence
        self.mood = mood
    }
    
    /// Create from ShaderRepository.ShaderMatchResult
    public init(from result: ShaderRepository.ShaderMatchResult) {
        self.name = result.shader.name
        self.path = result.shader.sourceURL.path
        self.score = result.score
        self.energyScore = result.shader.energyScore
        self.moodValence = result.shader.analysis?.featureVector[1] ?? 0.0
        self.mood = result.shader.mood
    }
}

/// Decision payload for song-driven shader selection.
///
/// The shortlist contains the top candidates considered before the final pick.
public struct ShaderSelectionDecision: Sendable, Equatable {
    public let selected: ShaderMatchResult
    public let shortlist: [ShaderMatchResult]

    public init(selected: ShaderMatchResult, shortlist: [ShaderMatchResult]) {
        self.selected = selected
        self.shortlist = shortlist
    }
}

// MARK: - Pipeline Cache Serialization

/// Entry in the pipeline cache
public struct CacheEntry: Codable {
    public let key: String
    public let result: PipelineResult
    public let cachedAt: Date
    
    public init(key: String, result: PipelineResult, cachedAt: Date) {
        self.key = key
        self.result = result
        self.cachedAt = cachedAt
    }
}

/// Serializable pipeline cache data
public struct PipelineCacheData: Codable {
    public let entries: [CacheEntry]
    public let savedAt: Date
    
    public init(entries: [CacheEntry], savedAt: Date) {
        self.entries = entries
        self.savedAt = savedAt
    }
}

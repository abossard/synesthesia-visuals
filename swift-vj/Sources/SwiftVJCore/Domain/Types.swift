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

    private static func computePrimaryMood(from scores: [String: Double]) -> String {
        scores.max(by: { $0.value < $1.value })?.key ?? ""
    }
}

// MARK: - Pipeline Result

/// Result from full pipeline processing.
public struct PipelineResult: Sendable, Equatable {
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

/// Shader quality rating
public enum ShaderRating: Int, Sendable, Codable, Comparable {
    case best = 1
    case good = 2
    case normal = 3
    case mask = 4
    case skip = 5

    public static func < (lhs: ShaderRating, rhs: ShaderRating) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Information about a shader
public struct ShaderInfo: Sendable, Equatable, Codable {
    public let name: String
    public let path: String
    public let energyScore: Double
    public let moodValence: Double
    public let colorWarmth: Double
    public let motionSpeed: Double
    public let mood: String
    public let colors: [String]
    public let effects: [String]
    public let rating: ShaderRating

    public init(
        name: String,
        path: String,
        energyScore: Double = 0.5,
        moodValence: Double = 0,
        colorWarmth: Double = 0.5,
        motionSpeed: Double = 0.5,
        mood: String = "",
        colors: [String] = [],
        effects: [String] = [],
        rating: ShaderRating = .normal
    ) {
        self.name = name
        self.path = path
        self.energyScore = energyScore
        self.moodValence = moodValence
        self.colorWarmth = colorWarmth
        self.motionSpeed = motionSpeed
        self.mood = mood
        self.colors = colors
        self.effects = effects
        self.rating = rating
    }
}

/// Result from shader matching
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
}

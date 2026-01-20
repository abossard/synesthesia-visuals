// Types.swift - Canonical song types
// Single source of truth for all song-related types

import Foundation

// Re-export Phase from ShaderRepository for convenience
@_exported import enum ShaderRepository.Phase

// MARK: - SongID

/// Type-safe song identifier (uses "artist::title" format)
public struct SongID: Hashable, Codable, RawRepresentable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(artist: String, title: String) {
        self.rawValue = "\(artist)::\(title)"
    }

    public var description: String { rawValue }

    /// Extract artist from ID
    public var artist: String {
        let parts = rawValue.components(separatedBy: "::")
        return parts.first ?? ""
    }

    /// Extract title from ID
    public var title: String {
        let parts = rawValue.components(separatedBy: "::")
        return parts.count > 1 ? parts[1] : ""
    }
}

// MARK: - SongStatus

/// Status of song analysis and data completeness
public enum SongStatus: String, Sendable, Codable, CaseIterable {
    case complete         // Full pipeline data available
    case partial          // Some data missing (e.g., no lyrics)
    case needsReanalysis  // Marked for re-analysis
    case error            // Last analysis failed

    public var displayName: String {
        switch self {
        case .complete: return "Complete"
        case .partial: return "Partial"
        case .needsReanalysis: return "Needs Reanalysis"
        case .error: return "Error"
        }
    }

    public var iconName: String {
        switch self {
        case .complete: return "checkmark.circle.fill"
        case .partial: return "circle.lefthalf.filled"
        case .needsReanalysis: return "arrow.clockwise.circle"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - StoredSongAnalysis

/// Complete analysis result stored with song
public struct StoredSongAnalysis: Sendable, Codable, Equatable {
    public let keywords: [String]
    public let themes: [String]
    public let visualAdjectives: [String]
    public let mood: String
    public let energy: Double        // 0.0-1.0
    public let valence: Double       // -1.0 to 1.0
    public let categories: [String: Double]
    public let djPhase: Phase?
    public let analyzedAt: Date

    public init(
        keywords: [String],
        themes: [String],
        visualAdjectives: [String],
        mood: String,
        energy: Double,
        valence: Double,
        categories: [String: Double],
        djPhase: Phase?,
        analyzedAt: Date = Date()
    ) {
        self.keywords = keywords
        self.themes = themes
        self.visualAdjectives = visualAdjectives
        self.mood = mood
        self.energy = energy
        self.valence = valence
        self.categories = categories
        self.djPhase = djPhase
        self.analyzedAt = analyzedAt
    }

    enum CodingKeys: String, CodingKey {
        case keywords, themes, visualAdjectives, mood, energy, valence, categories
        case djPhase = "dj_phase"
        case analyzedAt = "analyzed_at"
    }
}

// MARK: - Song

/// Complete song entity - the main stored type
public struct Song: Sendable, Equatable, Identifiable, Hashable, Codable {
    public let id: SongID

    // Track metadata (from VDJ/Spotify)
    public let artist: String
    public let title: String
    public let album: String
    public let duration: Double
    public let bpm: Double
    public let musicalKey: String

    // Analysis data
    public let analysis: StoredSongAnalysis?
    public let status: SongStatus

    // Pipeline outputs
    public let selectedShader: String?
    public let imagesFolderPath: String?
    public let imagesCount: Int

    // Lyrics
    public let hasLyrics: Bool
    public let lyricsText: String?
    public let lyricsLineCount: Int
    public let refrainCount: Int

    // Timestamps
    public let createdAt: Date
    public let lastPlayedAt: Date?
    public let lastAnalyzedAt: Date?
    public let playCount: Int

    public init(
        id: SongID,
        artist: String,
        title: String,
        album: String = "",
        duration: Double = 0,
        bpm: Double = 0,
        musicalKey: String = "",
        analysis: StoredSongAnalysis? = nil,
        status: SongStatus = .partial,
        selectedShader: String? = nil,
        imagesFolderPath: String? = nil,
        imagesCount: Int = 0,
        hasLyrics: Bool = false,
        lyricsText: String? = nil,
        lyricsLineCount: Int = 0,
        refrainCount: Int = 0,
        createdAt: Date = Date(),
        lastPlayedAt: Date? = nil,
        lastAnalyzedAt: Date? = nil,
        playCount: Int = 0
    ) {
        self.id = id
        self.artist = artist
        self.title = title
        self.album = album
        self.duration = duration
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.analysis = analysis
        self.status = status
        self.selectedShader = selectedShader
        self.imagesFolderPath = imagesFolderPath
        self.imagesCount = imagesCount
        self.hasLyrics = hasLyrics
        self.lyricsText = lyricsText
        self.lyricsLineCount = lyricsLineCount
        self.refrainCount = refrainCount
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
        self.lastAnalyzedAt = lastAnalyzedAt
        self.playCount = playCount
    }

    // MARK: - Computed Properties

    /// Human-readable display string
    public var displayName: String {
        "\(artist) - \(title)"
    }

    /// Energy score (0.0 - 1.0)
    public var energyScore: Double {
        analysis?.energy ?? 0.5
    }

    /// Mood string
    public var mood: String {
        analysis?.mood ?? "unknown"
    }

    /// DJ set phase
    public var phase: Phase? {
        analysis?.djPhase
    }

    /// Keywords array
    public var keywords: [String] {
        analysis?.keywords ?? []
    }

    /// Themes array
    public var themes: [String] {
        analysis?.themes ?? []
    }

    /// Valence (-1.0 to 1.0)
    public var valenceScore: Double {
        analysis?.valence ?? 0.0
    }

    /// Feature vector for matching [energy, valence]
    public var featureVector: [Double] {
        [energyScore, valenceScore]
    }

    // MARK: - Update Methods (return new instance)

    /// Create a new song with updated analysis
    public func withAnalysis(_ analysis: StoredSongAnalysis) -> Song {
        Song(
            id: id,
            artist: artist,
            title: title,
            album: album,
            duration: duration,
            bpm: bpm,
            musicalKey: musicalKey,
            analysis: analysis,
            status: .complete,
            selectedShader: selectedShader,
            imagesFolderPath: imagesFolderPath,
            imagesCount: imagesCount,
            hasLyrics: hasLyrics,
            lyricsText: lyricsText,
            lyricsLineCount: lyricsLineCount,
            refrainCount: refrainCount,
            createdAt: createdAt,
            lastPlayedAt: lastPlayedAt,
            lastAnalyzedAt: Date(),
            playCount: playCount
        )
    }

    /// Create a new song with updated shader selection
    public func withShader(_ shader: String) -> Song {
        Song(
            id: id,
            artist: artist,
            title: title,
            album: album,
            duration: duration,
            bpm: bpm,
            musicalKey: musicalKey,
            analysis: analysis,
            status: status,
            selectedShader: shader,
            imagesFolderPath: imagesFolderPath,
            imagesCount: imagesCount,
            hasLyrics: hasLyrics,
            lyricsText: lyricsText,
            lyricsLineCount: lyricsLineCount,
            refrainCount: refrainCount,
            createdAt: createdAt,
            lastPlayedAt: lastPlayedAt,
            lastAnalyzedAt: lastAnalyzedAt,
            playCount: playCount
        )
    }

    /// Create a new song marked as played now
    public func withPlayedNow() -> Song {
        Song(
            id: id,
            artist: artist,
            title: title,
            album: album,
            duration: duration,
            bpm: bpm,
            musicalKey: musicalKey,
            analysis: analysis,
            status: status,
            selectedShader: selectedShader,
            imagesFolderPath: imagesFolderPath,
            imagesCount: imagesCount,
            hasLyrics: hasLyrics,
            lyricsText: lyricsText,
            lyricsLineCount: lyricsLineCount,
            refrainCount: refrainCount,
            createdAt: createdAt,
            lastPlayedAt: Date(),
            lastAnalyzedAt: lastAnalyzedAt,
            playCount: playCount + 1
        )
    }

    /// Create a new song marked for re-analysis
    public func markedForReanalysis() -> Song {
        Song(
            id: id,
            artist: artist,
            title: title,
            album: album,
            duration: duration,
            bpm: bpm,
            musicalKey: musicalKey,
            analysis: analysis,
            status: .needsReanalysis,
            selectedShader: selectedShader,
            imagesFolderPath: imagesFolderPath,
            imagesCount: imagesCount,
            hasLyrics: hasLyrics,
            lyricsText: lyricsText,
            lyricsLineCount: lyricsLineCount,
            refrainCount: refrainCount,
            createdAt: createdAt,
            lastPlayedAt: lastPlayedAt,
            lastAnalyzedAt: lastAnalyzedAt,
            playCount: playCount
        )
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SongFilter

/// Filter criteria for song queries
public struct SongFilter: Sendable, Equatable {
    public var moodFilter: String?
    public var phaseFilter: Phase?
    public var energyRange: ClosedRange<Double>?
    public var statusFilter: SongStatus?
    public var hasLyricsOnly: Bool
    public var hasImagesOnly: Bool
    public var searchQuery: String?

    public init(
        moodFilter: String? = nil,
        phaseFilter: Phase? = nil,
        energyRange: ClosedRange<Double>? = nil,
        statusFilter: SongStatus? = nil,
        hasLyricsOnly: Bool = false,
        hasImagesOnly: Bool = false,
        searchQuery: String? = nil
    ) {
        self.moodFilter = moodFilter
        self.phaseFilter = phaseFilter
        self.energyRange = energyRange
        self.statusFilter = statusFilter
        self.hasLyricsOnly = hasLyricsOnly
        self.hasImagesOnly = hasImagesOnly
        self.searchQuery = searchQuery
    }

    /// Default filter that shows all songs
    public static let all = SongFilter()

    /// Check if any filter is active
    public var isActive: Bool {
        moodFilter != nil ||
        phaseFilter != nil ||
        energyRange != nil ||
        statusFilter != nil ||
        hasLyricsOnly ||
        hasImagesOnly ||
        (searchQuery != nil && !searchQuery!.isEmpty)
    }
}

// MARK: - SongSortOrder

/// Sort order for song lists
public enum SongSortOrder: String, CaseIterable, Sendable {
    case recentlyPlayed = "Recently Played"
    case recentlyAdded = "Recently Added"
    case alphabetical = "Alphabetical"
    case energy = "Energy"
    case playCount = "Play Count"

    public var iconName: String {
        switch self {
        case .recentlyPlayed: return "clock.arrow.circlepath"
        case .recentlyAdded: return "plus.circle"
        case .alphabetical: return "textformat.abc"
        case .energy: return "bolt"
        case .playCount: return "play.circle"
        }
    }
}

// MARK: - SongStatistics

/// Statistics snapshot for song collection
public struct SongStatistics: Sendable, Equatable {
    public let totalCount: Int
    public let completeCount: Int
    public let withLyricsCount: Int
    public let withImagesCount: Int
    public let moodCounts: [String: Int]
    public let phaseCounts: [Phase: Int]

    public init(
        totalCount: Int = 0,
        completeCount: Int = 0,
        withLyricsCount: Int = 0,
        withImagesCount: Int = 0,
        moodCounts: [String: Int] = [:],
        phaseCounts: [Phase: Int] = [:]
    ) {
        self.totalCount = totalCount
        self.completeCount = completeCount
        self.withLyricsCount = withLyricsCount
        self.withImagesCount = withImagesCount
        self.moodCounts = moodCounts
        self.phaseCounts = phaseCounts
    }
}

// MARK: - SongDatabaseData

/// Serializable song database structure
public struct SongDatabaseData: Codable {
    public let version: Int
    public let songs: [Song]
    public let savedAt: Date

    public init(songs: [Song], savedAt: Date = Date()) {
        self.version = 1
        self.songs = songs
        self.savedAt = savedAt
    }
}

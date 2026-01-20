// SongRepository.swift - Pure functions for song loading, saving, search, and filtering
// Single source of truth for song management

import Foundation

// MARK: - Songs

/// Pure functions for song management
/// All functions are stateless - caller manages caching
/// Usage: `Songs.loadAll(...)`, `Songs.search(...)`, `Songs.filter(...)`
public enum Songs {

    // MARK: - Loading

    /// Load all songs from a JSON database file
    /// - Parameter url: URL to songs_database.json
    /// - Returns: Array of Song entities
    public static func loadAll(from url: URL) throws -> [Song] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let database = try decoder.decode(SongDatabaseData.self, from: data)
        return database.songs
    }

    /// Load a single song by ID
    /// - Parameters:
    ///   - id: Song ID
    ///   - url: URL to database file
    /// - Returns: Song if found
    public static func load(id: SongID, from url: URL) throws -> Song? {
        let songs = try loadAll(from: url)
        return songs.first { $0.id == id }
    }

    // MARK: - Saving

    /// Save all songs to JSON database (replaces entire file)
    /// - Parameters:
    ///   - songs: Array of songs to save
    ///   - url: URL to database file
    public static func saveAll(_ songs: [Song], to url: URL) throws {
        let database = SongDatabaseData(songs: songs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(database)

        // Ensure directory exists
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try data.write(to: url, options: .atomic)
    }

    /// Save/update a single song (merges with existing)
    /// - Parameters:
    ///   - song: Song to save
    ///   - url: URL to database file
    public static func save(_ song: Song, to url: URL) throws {
        var songs = (try? loadAll(from: url)) ?? []

        if let index = songs.firstIndex(where: { $0.id == song.id }) {
            songs[index] = song
        } else {
            songs.append(song)
        }

        try saveAll(songs, to: url)
    }

    /// Delete a song by ID
    /// - Parameters:
    ///   - id: Song ID to delete
    ///   - url: URL to database file
    public static func delete(id: SongID, from url: URL) throws {
        var songs = try loadAll(from: url)
        songs.removeAll { $0.id == id }
        try saveAll(songs, to: url)
    }

    // MARK: - Search

    /// Text search across artist, title, album, keywords, themes
    /// - Parameters:
    ///   - query: Search query
    ///   - songs: Array of songs to search
    /// - Returns: Matching songs sorted by relevance
    public static func search(query: String, in songs: [Song]) -> [Song] {
        let queryLower = query.lowercased()
        let queryWords = queryLower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        guard !queryWords.isEmpty else { return songs }

        var scored: [(Song, Double)] = []

        for song in songs {
            var score = 0.0

            // Build searchable text
            var searchableText = song.artist.lowercased()
            searchableText += " " + song.title.lowercased()
            searchableText += " " + song.album.lowercased()
            searchableText += " " + song.mood.lowercased()
            searchableText += " " + song.keywords.joined(separator: " ").lowercased()
            searchableText += " " + song.themes.joined(separator: " ").lowercased()

            for word in queryWords {
                if searchableText.contains(word) {
                    score += 1.0

                    // Bonus for artist/title match
                    if song.artist.lowercased().contains(word) {
                        score += 3.0
                    }
                    if song.title.lowercased().contains(word) {
                        score += 3.0
                    }

                    // Bonus for mood match
                    if song.mood.lowercased() == word {
                        score += 2.0
                    }
                }
            }

            if score > 0 {
                scored.append((song, score))
            }
        }

        // Sort by score descending
        scored.sort { $0.1 > $1.1 }
        return scored.map { $0.0 }
    }

    // MARK: - Filtering

    /// Filter songs by combined criteria
    /// - Parameters:
    ///   - filter: Filter criteria
    ///   - songs: Array of songs to filter
    /// - Returns: Filtered songs
    public static func filter(_ filter: SongFilter, in songs: [Song]) -> [Song] {
        var result = songs

        // Apply text search first
        if let query = filter.searchQuery, !query.isEmpty {
            result = search(query: query, in: result)
        }

        // Filter by mood
        if let mood = filter.moodFilter {
            result = self.filter(byMood: mood, in: result)
        }

        // Filter by phase
        if let phase = filter.phaseFilter {
            result = self.filter(byPhase: phase, in: result)
        }

        // Filter by energy range
        if let range = filter.energyRange {
            result = self.filter(byEnergy: range, in: result)
        }

        // Filter by status
        if let status = filter.statusFilter {
            result = self.filter(byStatus: status, in: result)
        }

        // Filter for lyrics
        if filter.hasLyricsOnly {
            result = filterWithLyrics(in: result)
        }

        // Filter for images
        if filter.hasImagesOnly {
            result = filterWithImages(in: result)
        }

        return result
    }

    /// Filter songs by mood
    public static func filter(byMood mood: String, in songs: [Song]) -> [Song] {
        let moodLower = mood.lowercased()
        return songs.filter { $0.mood.lowercased().contains(moodLower) }
    }

    /// Filter songs by phase
    public static func filter(byPhase phase: Phase, in songs: [Song]) -> [Song] {
        songs.filter { $0.phase == phase }
    }

    /// Filter songs by energy range
    public static func filter(byEnergy range: ClosedRange<Double>, in songs: [Song]) -> [Song] {
        songs.filter { range.contains($0.energyScore) }
    }

    /// Filter songs by status
    public static func filter(byStatus status: SongStatus, in songs: [Song]) -> [Song] {
        songs.filter { $0.status == status }
    }

    /// Filter to only songs with lyrics
    public static func filterWithLyrics(in songs: [Song]) -> [Song] {
        songs.filter { $0.hasLyrics }
    }

    /// Filter to only songs with images
    public static func filterWithImages(in songs: [Song]) -> [Song] {
        songs.filter { $0.imagesFolderPath != nil && $0.imagesCount > 0 }
    }

    // MARK: - Sorting

    /// Sort songs by specified order
    /// - Parameters:
    ///   - songs: Array of songs to sort
    ///   - order: Sort order
    /// - Returns: Sorted songs
    public static func sort(_ songs: [Song], by order: SongSortOrder) -> [Song] {
        switch order {
        case .recentlyPlayed:
            return songs.sorted {
                ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast)
            }
        case .recentlyAdded:
            return songs.sorted { $0.createdAt > $1.createdAt }
        case .alphabetical:
            return songs.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .energy:
            return songs.sorted { $0.energyScore > $1.energyScore }
        case .playCount:
            return songs.sorted { $0.playCount > $1.playCount }
        }
    }

    // MARK: - Matching

    /// Find songs similar to target (by analysis features)
    /// - Parameters:
    ///   - song: Reference song
    ///   - songs: Array to search
    ///   - topK: Number of results
    /// - Returns: Similar songs (excluding reference)
    public static func findSimilar(to song: Song, in songs: [Song], topK: Int = 5) -> [Song] {
        let query = song.featureVector
        let filtered = songs.filter { $0.id != song.id }

        var scored: [(Song, Double)] = []

        for s in filtered {
            let vector = s.featureVector
            let distance = euclideanDistance(query, vector)
            scored.append((s, distance))
        }

        scored.sort { $0.1 < $1.1 }
        return scored.prefix(topK).map { $0.0 }
    }

    /// Match songs to energy/valence (for playlist building)
    /// - Parameters:
    ///   - energy: Target energy 0.0-1.0
    ///   - valence: Target valence -1.0 to 1.0
    ///   - songs: Array to search
    ///   - topK: Number of results
    /// - Returns: Matching songs
    public static func match(
        energy: Double,
        valence: Double,
        in songs: [Song],
        topK: Int = 5
    ) -> [Song] {
        let target = [energy, valence]

        var scored: [(Song, Double)] = []

        for song in songs {
            let vector = song.featureVector
            let distance = euclideanDistance(target, vector)
            scored.append((song, distance))
        }

        scored.sort { $0.1 < $1.1 }
        return scored.prefix(topK).map { $0.0 }
    }

    // MARK: - Statistics

    /// Get unique moods in song list
    public static func moods(in songs: [Song]) -> [String] {
        Array(Set(songs.map { $0.mood }.filter { !$0.isEmpty && $0 != "unknown" })).sorted()
    }

    /// Get unique phases in song list
    public static func phases(in songs: [Song]) -> [Phase] {
        Array(Set(songs.compactMap { $0.phase })).sorted { $0.rawValue < $1.rawValue }
    }

    /// Count songs by mood
    public static func countByMood(in songs: [Song]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for song in songs {
            let mood = song.mood
            if !mood.isEmpty && mood != "unknown" {
                counts[mood, default: 0] += 1
            }
        }
        return counts
    }

    /// Count songs by phase
    public static func countByPhase(in songs: [Song]) -> [Phase: Int] {
        var counts: [Phase: Int] = [:]
        for song in songs {
            if let phase = song.phase {
                counts[phase, default: 0] += 1
            }
        }
        return counts
    }

    /// Count songs by status
    public static func countByStatus(in songs: [Song]) -> [SongStatus: Int] {
        var counts: [SongStatus: Int] = [:]
        for song in songs {
            counts[song.status, default: 0] += 1
        }
        return counts
    }

    /// Generate statistics for a song collection
    public static func statistics(for songs: [Song]) -> SongStatistics {
        SongStatistics(
            totalCount: songs.count,
            completeCount: songs.filter { $0.status == .complete }.count,
            withLyricsCount: songs.filter { $0.hasLyrics }.count,
            withImagesCount: songs.filter { $0.imagesFolderPath != nil }.count,
            moodCounts: countByMood(in: songs),
            phaseCounts: countByPhase(in: songs)
        )
    }
}

// MARK: - Private Helpers

extension Songs {

    private static func euclideanDistance(_ v1: [Double], _ v2: [Double]) -> Double {
        var total = 0.0
        for i in 0..<min(v1.count, v2.count) {
            let diff = v1[i] - v2[i]
            total += diff * diff
        }
        return sqrt(total)
    }
}

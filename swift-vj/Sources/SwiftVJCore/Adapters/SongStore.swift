// SongStore - Actor wrapper for song database state
// Uses SongRepository module for types and file operations
// Following A Philosophy of Software Design: deep module with simple interface

import Foundation
import SongRepository

// MARK: - Song Store

/// Actor that holds song state and provides async-safe access.
/// Uses `Songs` namespace from SongRepository module for loading/saving/filtering.
/// Manages persistence to JSON file with auto-save functionality.
public actor SongStore {

    // MARK: - State

    private var songs: [SongID: Song] = [:]
    private let databaseURL: URL
    private var isDirty: Bool = false
    private var autoSaveTask: Task<Void, Never>?

    // MARK: - Configuration

    private static let autoSaveInterval: TimeInterval = 30  // seconds

    // MARK: - Init

    public init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL ??
            Config.dataDirectory.appendingPathComponent("songs_database.json")
    }

    // MARK: - Lifecycle

    /// Load songs from disk
    /// - Returns: Number of songs loaded
    @discardableResult
    public func load() -> Int {
        do {
            let loaded = try Songs.loadAll(from: databaseURL)
            songs = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            startAutoSave()
            print("[SongStore] Loaded \(songs.count) songs from database")
            return songs.count
        } catch {
            print("[SongStore] Failed to load songs: \(error)")
            startAutoSave()
            return 0
        }
    }

    /// Save all songs to disk
    public func save() {
        guard isDirty else { return }
        do {
            try Songs.saveAll(Array(songs.values), to: databaseURL)
            isDirty = false
            print("[SongStore] Saved \(songs.count) songs to database")
        } catch {
            print("[SongStore] Save failed: \(error)")
        }
    }

    /// Force save regardless of dirty flag
    public func forceSave() {
        do {
            try Songs.saveAll(Array(songs.values), to: databaseURL)
            isDirty = false
            print("[SongStore] Force saved \(songs.count) songs to database")
        } catch {
            print("[SongStore] Force save failed: \(error)")
        }
    }

    /// Stop auto-save and perform final save
    public func shutdown() {
        autoSaveTask?.cancel()
        autoSaveTask = nil
        if isDirty {
            save()
        }
    }

    /// Clear all songs from database and disk
    public func clearAll() {
        songs.removeAll()
        isDirty = false
        try? FileManager.default.removeItem(at: databaseURL)
        print("[SongStore] Cleared all songs")
    }

    // MARK: - CRUD Operations

    /// Get all songs (sorted by display name)
    public var allSongs: [Song] {
        songs.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Get song by ID
    public func song(id: SongID) -> Song? {
        songs[id]
    }

    /// Get song by artist and title
    public func song(artist: String, title: String) -> Song? {
        songs[SongID(artist: artist, title: title)]
    }

    /// Check if song exists
    public func exists(id: SongID) -> Bool {
        songs[id] != nil
    }

    /// Check if song exists by artist/title
    public func exists(artist: String, title: String) -> Bool {
        exists(id: SongID(artist: artist, title: title))
    }

    /// Add or update a song
    public func upsert(_ song: Song) {
        let isNew = songs[song.id] == nil
        songs[song.id] = song
        markDirty()
        if isNew {
            print("[SongStore] Added new song: \(song.displayName)")
        }
    }

    /// Add or update from pipeline result and track
    public func upsertFromPipeline(
        artist: String,
        title: String,
        album: String,
        duration: Double,
        bpm: Double,
        musicalKey: String,
        mood: String,
        energy: Double,
        valence: Double,
        keywords: [String],
        themes: [String],
        visualAdjectives: [String],
        categories: [String: Double],
        djPhase: Phase?,
        shaderName: String?,
        imagesFolderPath: String?,
        imagesCount: Int,
        hasLyrics: Bool,
        lyricsText: String,
        lyricsLineCount: Int,
        refrainCount: Int,
        audioFilePath: String? = nil,
        incrementPlayCount: Bool = true
    ) {
        let songId = SongID(artist: artist, title: title)
        let existing = songs[songId]

        let analysis = StoredSongAnalysis(
            keywords: keywords,
            themes: themes,
            visualAdjectives: visualAdjectives,
            mood: mood,
            energy: energy,
            valence: valence,
            categories: categories,
            djPhase: djPhase
        )

        // Determine status - complete if AI analysis ran (has mood)
        // Images and lyrics are optional enrichments
        let status: SongStatus
        if !mood.isEmpty {
            status = .complete
        } else {
            status = .partial
        }

        let song = Song(
            id: songId,
            artist: artist,
            title: title,
            album: album,
            duration: duration,
            bpm: bpm,
            musicalKey: musicalKey,
            analysis: analysis,
            status: status,
            selectedShader: shaderName,
            imagesFolderPath: imagesFolderPath,
            imagesCount: imagesCount,
            hasLyrics: hasLyrics,
            lyricsText: lyricsText.isEmpty ? nil : lyricsText,
            lyricsLineCount: lyricsLineCount,
            refrainCount: refrainCount,
            audioFilePath: audioFilePath ?? existing?.audioFilePath,
            createdAt: existing?.createdAt ?? Date(),
            lastPlayedAt: incrementPlayCount ? Date() : (existing?.lastPlayedAt ?? Date()),
            lastAnalyzedAt: Date(),
            playCount: incrementPlayCount ? (existing?.playCount ?? 0) + 1 : (existing?.playCount ?? 0)
        )

        upsert(song)
    }

    /// Delete a song
    public func delete(id: SongID) {
        if let removed = songs.removeValue(forKey: id) {
            markDirty()
            print("[SongStore] Deleted song: \(removed.displayName)")
        }
    }

    /// Mark song for re-analysis
    public func markForReanalysis(id: SongID) {
        guard let song = songs[id] else { return }
        songs[id] = song.markedForReanalysis()
        markDirty()
    }

    /// Update shader for song
    public func setShader(_ shader: String, for id: SongID) {
        guard let song = songs[id] else { return }
        songs[id] = song.withShader(shader)
        markDirty()
    }

    /// Update image metadata for a song
    @discardableResult
    public func updateImages(for id: SongID, folderPath: String?, count: Int) -> Song? {
        guard let existing = songs[id] else { return nil }

        let analysis = existing.analysis
        let status: SongStatus = {
            if existing.hasLyrics && count > 0 && !(analysis?.mood ?? "").isEmpty {
                return .complete
            }
            return .partial
        }()

        let updated = Song(
            id: existing.id,
            artist: existing.artist,
            title: existing.title,
            album: existing.album,
            duration: existing.duration,
            bpm: existing.bpm,
            musicalKey: existing.musicalKey,
            analysis: analysis,
            status: status,
            selectedShader: existing.selectedShader,
            imagesFolderPath: count > 0 ? folderPath : nil,
            imagesCount: count,
            hasLyrics: existing.hasLyrics,
            lyricsText: existing.lyricsText,
            lyricsLineCount: existing.lyricsLineCount,
            refrainCount: existing.refrainCount,
            createdAt: existing.createdAt,
            lastPlayedAt: existing.lastPlayedAt,
            lastAnalyzedAt: existing.lastAnalyzedAt,
            playCount: existing.playCount
        )

        songs[id] = updated
        markDirty()
        return updated
    }

    /// Record song played (increments play count)
    public func recordPlay(id: SongID) {
        guard let song = songs[id] else { return }
        songs[id] = song.withPlayedNow()
        markDirty()
    }

    /// Total song count
    public var count: Int { songs.count }

    // MARK: - Queries (delegate to Songs namespace)

    /// Search songs by text
    public func search(query: String) -> [Song] {
        Songs.search(query: query, in: Array(songs.values))
    }

    /// Filter songs by criteria
    public func filter(_ filter: SongFilter) -> [Song] {
        Songs.filter(filter, in: Array(songs.values))
    }

    /// Sort songs by order
    public func sorted(by order: SongSortOrder) -> [Song] {
        Songs.sort(Array(songs.values), by: order)
    }

    /// Filter and sort
    public func query(filter: SongFilter, sortBy order: SongSortOrder) -> [Song] {
        let filtered = Songs.filter(filter, in: Array(songs.values))
        return Songs.sort(filtered, by: order)
    }

    /// Get songs for a specific phase
    public func songs(forPhase phase: Phase) -> [Song] {
        Songs.filter(byPhase: phase, in: Array(songs.values))
    }

    /// Get songs needing re-analysis
    public func songsNeedingReanalysis() -> [Song] {
        Songs.filter(byStatus: .needsReanalysis, in: Array(songs.values))
    }

    /// Get songs with lyrics
    public func songsWithLyrics() -> [Song] {
        Songs.filterWithLyrics(in: Array(songs.values))
    }

    /// Get songs with images
    public func songsWithImages() -> [Song] {
        Songs.filterWithImages(in: Array(songs.values))
    }

    /// Find similar songs
    public func findSimilar(to song: Song, topK: Int = 5) -> [Song] {
        Songs.findSimilar(to: song, in: Array(songs.values), topK: topK)
    }

    /// Match songs to energy/valence
    public func match(energy: Double, valence: Double, topK: Int = 5) -> [Song] {
        Songs.match(energy: energy, valence: valence, in: Array(songs.values), topK: topK)
    }

    // MARK: - Statistics

    /// Get available moods
    public var availableMoods: [String] {
        Songs.moods(in: Array(songs.values))
    }

    /// Get available phases
    public var availablePhases: [Phase] {
        Songs.phases(in: Array(songs.values))
    }

    /// Get statistics
    public var statistics: SongStatistics {
        Songs.statistics(for: Array(songs.values))
    }

    // MARK: - Private

    private func markDirty() {
        isDirty = true
    }

    private func startAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.autoSaveInterval))
                if isDirty && !Task.isCancelled {
                    save()
                }
            }
        }
    }

    // MARK: - Moodboard Data (connections, positions, phase edges)

    private var moodboardDataURL: URL {
        databaseURL.deletingLastPathComponent().appendingPathComponent("moodboard_data.json")
    }

    /// Persisted moodboard data (separate from songs to avoid coupling)
    private struct MoodboardData: Codable {
        var connections: [SongConnection]
        var canvasPositions: [CanvasPositionEntry]
        var phaseEdges: [PhaseFlowEdge]

        static let empty = MoodboardData(connections: [], canvasPositions: [], phaseEdges: [])
    }

    /// Load moodboard connections, positions, and phase edges
    public func loadMoodboardData() -> (connections: [SongConnection], positions: [CanvasPositionEntry], phaseEdges: [PhaseFlowEdge]) {
        guard FileManager.default.fileExists(atPath: moodboardDataURL.path) else {
            return ([], [], [])
        }
        do {
            let data = try Data(contentsOf: moodboardDataURL)
            let decoded = try JSONDecoder().decode(MoodboardData.self, from: data)
            return (decoded.connections, decoded.canvasPositions, decoded.phaseEdges)
        } catch {
            print("[SongStore] Failed to load moodboard data: \(error)")
            return ([], [], [])
        }
    }

    /// Save a song connection
    public func saveSongConnection(_ connection: SongConnection) {
        var moodboard = loadMoodboardDataInternal()
        moodboard.connections.removeAll {
            $0.sourceSongId == connection.sourceSongId && $0.targetSongId == connection.targetSongId
        }
        moodboard.connections.append(connection)
        saveMoodboardDataInternal(moodboard)
    }

    /// Remove a song connection
    public func removeSongConnection(source: SongID, target: SongID) {
        var moodboard = loadMoodboardDataInternal()
        moodboard.connections.removeAll {
            $0.sourceSongId == source && $0.targetSongId == target
        }
        saveMoodboardDataInternal(moodboard)
    }

    /// Save canvas positions
    public func saveCanvasPositions(_ positions: [CanvasPositionEntry]) {
        var moodboard = loadMoodboardDataInternal()
        moodboard.canvasPositions = positions
        saveMoodboardDataInternal(moodboard)
    }

    /// Save phase flow edges
    public func savePhaseEdges(_ edges: [PhaseFlowEdge]) {
        var moodboard = loadMoodboardDataInternal()
        moodboard.phaseEdges = edges
        saveMoodboardDataInternal(moodboard)
    }

    private func loadMoodboardDataInternal() -> MoodboardData {
        guard FileManager.default.fileExists(atPath: moodboardDataURL.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: moodboardDataURL)
            return try JSONDecoder().decode(MoodboardData.self, from: data)
        } catch {
            return .empty
        }
    }

    private func saveMoodboardDataInternal(_ moodboard: MoodboardData) {
        do {
            let data = try JSONEncoder().encode(moodboard)
            try data.write(to: moodboardDataURL, options: .atomic)
        } catch {
            print("[SongStore] Failed to save moodboard data: \(error)")
        }
    }
}

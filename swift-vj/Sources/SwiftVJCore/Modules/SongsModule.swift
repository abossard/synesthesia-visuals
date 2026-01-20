// SongsModule - Module wrapper for song management
// Following A Philosophy of Software Design: deep module hiding complexity

import Foundation
import SongRepository

/// Songs module - provides song management and history
///
/// Deep module interface:
/// - `start()` / `stop()` - lifecycle
/// - `recordSong(...)` - save pipeline result
/// - `search(query:)` - text search
/// - `getSong(artist:title:)` - lookup
/// - `markForReanalysis(id:)` - trigger re-analysis
///
/// Hides: Database loading, persistence, auto-save, indexing
public actor SongsModule: Module {

    // MARK: - State

    public private(set) var isStarted: Bool = false

    private let store: SongStore

    // For re-analysis requests
    private var reanalysisQueue: [SongID] = []

    // MARK: - Init

    public init(store: SongStore = SongStore()) {
        self.store = store
    }

    // MARK: - Module Protocol

    public func start() async throws {
        guard !isStarted else { throw ModuleError.alreadyStarted }

        let count = await store.load()
        print("[SongsModule] Started with \(count) songs")

        isStarted = true
    }

    public func stop() async {
        await store.shutdown()
        isStarted = false
        print("[SongsModule] Stopped")
    }

    /// Clear all songs from database
    public func clearAll() async {
        await store.clearAll()
    }

    public func getStatus() -> [String: Any] {
        [
            "started": isStarted,
            "reanalysis_queue": reanalysisQueue.count
        ]
    }

    // MARK: - Public API - Recording

    /// Record a song from pipeline result
    ///
    /// Called automatically when pipeline completes.
    /// Creates or updates the song in the database.
    public func recordSong(
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
        refrainCount: Int
    ) async {
        await store.upsertFromPipeline(
            artist: artist,
            title: title,
            album: album,
            duration: duration,
            bpm: bpm,
            musicalKey: musicalKey,
            mood: mood,
            energy: energy,
            valence: valence,
            keywords: keywords,
            themes: themes,
            visualAdjectives: visualAdjectives,
            categories: categories,
            djPhase: djPhase,
            shaderName: shaderName,
            imagesFolderPath: imagesFolderPath,
            imagesCount: imagesCount,
            hasLyrics: hasLyrics,
            lyricsText: lyricsText,
            lyricsLineCount: lyricsLineCount,
            refrainCount: refrainCount
        )
    }

    // MARK: - Public API - Queries

    /// Get a song by artist and title
    public func getSong(artist: String, title: String) async -> Song? {
        await store.song(artist: artist, title: title)
    }

    /// Get a song by ID
    public func getSong(id: SongID) async -> Song? {
        await store.song(id: id)
    }

    /// Check if a song exists
    public func songExists(artist: String, title: String) async -> Bool {
        await store.exists(artist: artist, title: title)
    }

    /// Get all songs
    public var allSongs: [Song] {
        get async { await store.allSongs }
    }

    /// Get song count
    public var songCount: Int {
        get async { await store.count }
    }

    /// Search songs by text
    public func search(query: String) async -> [Song] {
        await store.search(query: query)
    }

    /// Filter songs by criteria
    public func filter(_ filter: SongFilter) async -> [Song] {
        await store.filter(filter)
    }

    /// Query with filter and sort
    public func query(filter: SongFilter, sortBy order: SongSortOrder) async -> [Song] {
        await store.query(filter: filter, sortBy: order)
    }

    /// Get songs sorted by order
    public func sorted(by order: SongSortOrder) async -> [Song] {
        await store.sorted(by: order)
    }

    /// Get statistics
    public var statistics: SongStatistics {
        get async { await store.statistics }
    }

    /// Get available moods
    public var availableMoods: [String] {
        get async { await store.availableMoods }
    }

    /// Get available phases
    public var availablePhases: [Phase] {
        get async { await store.availablePhases }
    }

    // MARK: - Public API - Modifications

    /// Delete a song
    public func deleteSong(id: SongID) async {
        await store.delete(id: id)
    }

    /// Mark song for re-analysis
    public func markForReanalysis(id: SongID) async {
        await store.markForReanalysis(id: id)
        if !reanalysisQueue.contains(id) {
            reanalysisQueue.append(id)
        }
    }

    /// Update shader selection for song
    public func setShader(_ shader: String, for id: SongID) async {
        await store.setShader(shader, for: id)
    }

    /// Delete an image and update the song's image metadata.
    /// - Returns: Updated song (if it exists)
    public func deleteImage(id: SongID, imageURL: URL) async throws -> Song? {
        // Remove the file from disk if present
        if FileManager.default.fileExists(atPath: imageURL.path) {
            try FileManager.default.removeItem(at: imageURL)
        }

        guard let song = await store.song(id: id),
              let folderPath = song.imagesFolderPath else {
            return await store.song(id: id)
        }

        let newCount = Self.countImages(in: folderPath)
        return await store.updateImages(for: id, folderPath: folderPath, count: newCount)
    }

    private static func countImages(in folderPath: String) -> Int {
        let fm = FileManager.default
        let folderURL = URL(fileURLWithPath: folderPath)
        let allowed = Set(["png", "jpg", "jpeg", "gif", "heic", "tiff"])
        guard let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: nil) else { return 0 }
        return enumerator.reduce(0) { count, element in
            guard let url = element as? URL else { return count }
            return allowed.contains(url.pathExtension.lowercased()) ? count + 1 : count
        }
    }

    /// Record song was played (updates play count and timestamp)
    public func recordPlay(id: SongID) async {
        await store.recordPlay(id: id)
    }

    // MARK: - Public API - Re-analysis Queue

    /// Get next song needing re-analysis
    public func nextReanalysis() async -> Song? {
        guard let id = reanalysisQueue.first else { return nil }
        reanalysisQueue.removeFirst()
        return await store.song(id: id)
    }

    /// Get all songs needing re-analysis
    public func songsNeedingReanalysis() async -> [Song] {
        await store.songsNeedingReanalysis()
    }

    /// Get re-analysis queue count
    public var reanalysisQueueCount: Int {
        reanalysisQueue.count
    }

    // MARK: - Public API - Matching

    /// Find songs similar to a given song
    public func findSimilar(to song: Song, topK: Int = 5) async -> [Song] {
        await store.findSimilar(to: song, topK: topK)
    }

    /// Match songs to energy/valence (for playlist building)
    public func match(energy: Double, valence: Double, topK: Int = 5) async -> [Song] {
        await store.match(energy: energy, valence: valence, topK: topK)
    }

    // MARK: - Public API - Persistence

    /// Save database immediately
    public func saveNow() async {
        await store.forceSave()
    }
}

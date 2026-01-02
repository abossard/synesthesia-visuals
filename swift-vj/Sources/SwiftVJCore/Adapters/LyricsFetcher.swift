// LyricsFetcher - Adapter for LRCLIB API
// Following Grokking Simplicity: this is an action (side effects)

import Foundation

/// Error types for lyrics fetching
public enum LyricsFetcherError: Error, Equatable {
    case networkError(String)
    case notFound
    case invalidResponse
    case decodingError(String)
}

/// Response from LRCLIB API
public struct LRCLibResponse: Codable, Sendable {
    public let id: Int
    public let name: String?
    public let trackName: String?
    public let artistName: String?
    public let albumName: String?
    public let duration: Double?
    public let instrumental: Bool?
    public let plainLyrics: String?
    public let syncedLyrics: String?
}

/// Fetches lyrics from LRCLIB API with caching
public actor LyricsFetcher {
    public static let baseURL = "https://lrclib.net/api"
    public static let cacheTTL: TimeInterval = 86400 * 7  // 7 days

    private let cacheDirectory: URL
    private let session: URLSession

    public init(cacheDirectory: URL? = nil, session: URLSession = .shared) {
        self.cacheDirectory = cacheDirectory ?? Config.cacheDirectory.appendingPathComponent("lyrics")
        self.session = session

        // Ensure cache directory exists
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    /// Fetch synced lyrics for a song
    /// Returns LRC format text if found, nil if not found
    public func fetch(artist: String, title: String) async throws -> String? {
        // Check cache first
        if let cached = loadFromCache(artist: artist, title: title) {
            return cached.syncedLyrics
        }

        // Fetch from API
        let response = try await fetchFromAPI(artist: artist, title: title)

        // Cache the response
        saveToCache(artist: artist, title: title, response: response)

        return response.syncedLyrics
    }

    /// Fetch full response including plain lyrics and metadata
    public func fetchFull(artist: String, title: String) async throws -> LRCLibResponse {
        // Check cache first
        if let cached = loadFromCache(artist: artist, title: title) {
            return cached
        }

        // Fetch from API
        let response = try await fetchFromAPI(artist: artist, title: title)

        // Cache the response
        saveToCache(artist: artist, title: title, response: response)

        return response
    }

    /// Check if lyrics are cached for a song
    public func isCached(artist: String, title: String) -> Bool {
        let cacheFile = cacheFilePath(artist: artist, title: title)
        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            return false
        }

        // Check TTL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modified = attrs[.modificationDate] as? Date else {
            return false
        }

        return Date().timeIntervalSince(modified) < Self.cacheTTL
    }

    /// Clear cache for a specific song
    public func clearCache(artist: String, title: String) {
        let cacheFile = cacheFilePath(artist: artist, title: title)
        try? FileManager.default.removeItem(at: cacheFile)
    }

    /// Clear all cached lyrics
    public func clearAllCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Private

    private func fetchFromAPI(artist: String, title: String) async throws -> LRCLibResponse {
        guard var components = URLComponents(string: "\(Self.baseURL)/get") else {
            throw LyricsFetcherError.networkError("Invalid URL")
        }

        components.queryItems = [
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "track_name", value: title)
        ]

        guard let url = components.url else {
            throw LyricsFetcherError.networkError("Invalid URL")
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LyricsFetcherError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 404 {
            throw LyricsFetcherError.notFound
        }

        guard httpResponse.statusCode == 200 else {
            throw LyricsFetcherError.networkError("HTTP \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(LRCLibResponse.self, from: data)
        } catch {
            throw LyricsFetcherError.decodingError(error.localizedDescription)
        }
    }

    private func cacheFilePath(artist: String, title: String) -> URL {
        let filename = sanitizeCacheFilename(artist: artist, title: title)
        return cacheDirectory.appendingPathComponent("\(filename).json")
    }

    private func loadFromCache(artist: String, title: String) -> LRCLibResponse? {
        let cacheFile = cacheFilePath(artist: artist, title: title)

        guard FileManager.default.fileExists(atPath: cacheFile.path) else {
            return nil
        }

        // Check TTL
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < Self.cacheTTL else {
            return nil
        }

        guard let data = try? Data(contentsOf: cacheFile) else {
            return nil
        }

        return try? JSONDecoder().decode(LRCLibResponse.self, from: data)
    }

    private func saveToCache(artist: String, title: String, response: LRCLibResponse) {
        let cacheFile = cacheFilePath(artist: artist, title: title)

        guard let data = try? JSONEncoder().encode(response) else {
            return
        }

        try? data.write(to: cacheFile)
    }
}

// Lyrics E2E Tests - Integration tests using SwiftVJCore modules
// Tests actual network calls and real service behavior

import XCTest
@testable import SwiftVJCore

final class LyricsE2ETests: XCTestCase {

    var tempCacheDir: URL!
    var fetcher: LyricsFetcher!

    override func setUp() async throws {
        // Create isolated temp cache directory
        tempCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempCacheDir, withIntermediateDirectories: true)
        fetcher = LyricsFetcher(cacheDirectory: tempCacheDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempCacheDir)
    }

    // MARK: - LyricsFetcher Tests

    func test_lyricsFetcher_fetchesLyricsForKnownSong() async throws {
        // Prerequisite: Internet connection
        try require(.internetConnection)

        // Given: A well-known song with lyrics on LRCLIB
        // When: Fetching lyrics using LyricsFetcher
        let lrc = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody")

        // Then: LRC format is returned
        XCTAssertNotNil(lrc, "Should return lyrics for known song")
        XCTAssertTrue(lrc!.contains("["), "LRC should have timestamps")
        XCTAssertTrue(lrc!.lowercased().contains("real life"), "Should contain expected lyrics text")
    }

    func test_lyricsFetcher_returnsNilForUnknownSong() async throws {
        try require(.internetConnection)

        // Given: A song that doesn't exist
        // When: Fetching lyrics
        do {
            _ = try await fetcher.fetch(artist: "ZZZZ", title: "NonExistentSong12345")
            XCTFail("Should throw notFound error")
        } catch LyricsFetcherError.notFound {
            // Expected
        }
    }

    func test_lyricsFetcher_cachesResult() async throws {
        try require(.internetConnection)

        // Given: Fresh fetcher
        let notCachedBefore = await fetcher.isCached(artist: "Queen", title: "Bohemian Rhapsody")
        XCTAssertFalse(notCachedBefore)

        // When: Fetching lyrics
        _ = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody")

        // Then: Result is cached
        let isCached = await fetcher.isCached(artist: "Queen", title: "Bohemian Rhapsody")
        XCTAssertTrue(isCached)
    }

    func test_lyricsFetcher_fullResponseHasMetadata() async throws {
        try require(.internetConnection)

        // When: Fetching full response
        let response = try await fetcher.fetchFull(artist: "Queen", title: "Bohemian Rhapsody")

        // Then: Response has metadata
        XCTAssertEqual(response.artistName, "Queen")
        XCTAssertNotNil(response.syncedLyrics)
        XCTAssertNotNil(response.duration)
    }

    func test_lyricsFetcher_clearCache() async throws {
        try require(.internetConnection)

        // Given: Cached lyrics
        _ = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody")
        let cachedBefore = await fetcher.isCached(artist: "Queen", title: "Bohemian Rhapsody")
        XCTAssertTrue(cachedBefore)

        // When: Clearing cache
        await fetcher.clearCache(artist: "Queen", title: "Bohemian Rhapsody")

        // Then: No longer cached
        let cachedAfter = await fetcher.isCached(artist: "Queen", title: "Bohemian Rhapsody")
        XCTAssertFalse(cachedAfter)
    }

    // MARK: - LRC Parsing Integration

    func test_lyricsFetcher_parsedLyricsHaveValidTimings() async throws {
        try require(.internetConnection)

        // Given: Fetched LRC lyrics
        guard let lrc = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody") else {
            XCTFail("Should return lyrics")
            return
        }

        // When: Parsing with parseLRC
        let lines = parseLRC(lrc)

        // Then: Lines are parsed correctly
        XCTAssertGreaterThan(lines.count, 10, "Should have many lyric lines")
        XCTAssertTrue(lines.allSatisfy { $0.timeSec >= 0 }, "All times should be non-negative")
        XCTAssertTrue(lines.allSatisfy { !$0.text.isEmpty }, "All lines should have text")

        // Verify lines are sorted by time
        for i in 1..<lines.count {
            XCTAssertGreaterThanOrEqual(lines[i].timeSec, lines[i-1].timeSec)
        }
    }

    func test_lyricsFetcher_analyzedLyricsHaveRefrains() async throws {
        try require(.internetConnection)

        // Given: Fetched and parsed lyrics
        guard let lrc = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody") else {
            XCTFail("Should return lyrics")
            return
        }
        let lines = parseLRC(lrc)

        // When: Analyzing with analyzeLyrics
        let analyzed = analyzeLyrics(lines)

        // Then: Some lines are marked as refrain (chorus repeats)
        let refrainCount = analyzed.filter { $0.isRefrain }.count
        XCTAssertGreaterThan(refrainCount, 0, "Should have some refrain lines")

        // And keywords are extracted
        let linesWithKeywords = analyzed.filter { !$0.keywords.isEmpty }.count
        XCTAssertGreaterThan(linesWithKeywords, 0, "Should have keywords extracted")
    }

    // MARK: - LM Studio Tests (when available)

    func test_lmstudio_isAccessibleWhenRunning() async throws {
        try require(.lmStudioAvailable)

        // Given: LM Studio running on port 1234
        let url = URL(string: "http://localhost:1234/v1/models")!

        // When: Querying models endpoint
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        // Then: Valid response
        XCTAssertEqual(httpResponse.statusCode, 200)

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["data"], "Should have models data")
    }
}

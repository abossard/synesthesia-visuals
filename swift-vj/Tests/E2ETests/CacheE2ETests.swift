// CacheE2ETests - Basic cache tests

import XCTest
@testable import SwiftVJCore

final class CacheE2ETests: XCTestCase {

    var tempCacheDir: URL!
    var fetcher: LyricsFetcher!

    override func setUp() async throws {
        tempCacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempCacheDir, withIntermediateDirectories: true)
        fetcher = LyricsFetcher(cacheDirectory: tempCacheDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempCacheDir)
    }

    func test_lyricsCache_persistsAfterFetch() async throws {
        try require(.internetConnection)

        _ = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody")

        let isCached = await fetcher.isCached(artist: "Queen", title: "Bohemian Rhapsody")
        XCTAssertTrue(isCached)
    }

    func test_lyricsCache_clearSingleSong() async throws {
        try require(.internetConnection)

        _ = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody")

        await fetcher.clearCache(artist: "Queen", title: "Bohemian Rhapsody")

        let isCached = await fetcher.isCached(artist: "Queen", title: "Bohemian Rhapsody")
        XCTAssertFalse(isCached)
    }

    func test_lyricsCache_clearAll() async throws {
        try require(.internetConnection)

        _ = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody")

        await fetcher.clearAllCache()

        let isCached = await fetcher.isCached(artist: "Queen", title: "Bohemian Rhapsody")
        XCTAssertFalse(isCached)
    }
}

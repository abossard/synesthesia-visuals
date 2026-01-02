// Lyrics E2E Tests - Require external services
// Tests actual network calls and real service behavior

import XCTest
@testable import SwiftVJCore

final class LyricsE2ETests: XCTestCase {

    // MARK: - LRCLIB Fetch Tests

    func test_lrclib_fetchesLyricsForKnownSong() async throws {
        // Prerequisite: Internet connection
        try require(.internetConnection)

        // TODO: Implement LyricsFetcher
        // Given: A well-known song with lyrics on LRCLIB
        // let fetcher = LyricsFetcher()
        //
        // When: Fetching lyrics
        // let lrc = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody")
        //
        // Then: LRC format is returned
        // XCTAssertNotNil(lrc)
        // XCTAssertTrue(lrc!.contains("["))  // Has timestamps
        // XCTAssertTrue(lrc!.contains("real life"))

        // For now, just verify we can reach LRCLIB
        let url = URL(string: "https://lrclib.net/api/get?artist_name=Queen&track_name=Bohemian%20Rhapsody")!
        let (data, response) = try await URLSession.shared.data(from: url)

        let httpResponse = response as! HTTPURLResponse
        XCTAssertEqual(httpResponse.statusCode, 200)

        // Verify response has syncedLyrics
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["syncedLyrics"], "Should have synced lyrics")
    }

    func test_lrclib_returns404ForUnknownSong() async throws {
        try require(.internetConnection)

        // Given: A song that doesn't exist
        let url = URL(string: "https://lrclib.net/api/get?artist_name=ZZZZ&track_name=NonExistentSong12345")!

        // When: Fetching
        let (_, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        // Then: 404 response
        XCTAssertEqual(httpResponse.statusCode, 404)
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

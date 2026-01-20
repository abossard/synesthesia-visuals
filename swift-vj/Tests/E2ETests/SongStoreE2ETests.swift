// SongStoreE2ETests - Basic tests for song data management

import XCTest
@testable import SwiftVJCore
@testable import SongRepository

final class SongStoreE2ETests: XCTestCase {

    var tempDatabaseURL: URL!
    var store: SongStore!

    override func setUp() async throws {
        tempDatabaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("songs_database.json")
        try FileManager.default.createDirectory(
            at: tempDatabaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        store = SongStore(databaseURL: tempDatabaseURL)
    }

    override func tearDown() async throws {
        await store.shutdown()
        try? FileManager.default.removeItem(at: tempDatabaseURL.deletingLastPathComponent())
    }

    func test_songStore_upsertAndRetrieve() async throws {
        let song = Song(
            id: SongID(artist: "Test", title: "Song"),
            artist: "Test",
            title: "Song",
            album: "",
            duration: 180,
            bpm: 120,
            musicalKey: "",
            analysis: nil,
            status: .partial,
            selectedShader: nil,
            imagesFolderPath: nil,
            imagesCount: 0,
            hasLyrics: false,
            lyricsText: nil,
            lyricsLineCount: 0,
            refrainCount: 0,
            createdAt: Date(),
            lastPlayedAt: nil,
            lastAnalyzedAt: nil,
            playCount: 0
        )

        await store.upsert(song)

        let count = await store.count
        XCTAssertEqual(count, 1)

        let retrieved = await store.song(id: song.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.artist, "Test")
    }

    func test_songStore_persistence() async throws {
        let song = Song(
            id: SongID(artist: "Artist", title: "Title"),
            artist: "Artist",
            title: "Title",
            album: "",
            duration: 180,
            bpm: 120,
            musicalKey: "",
            analysis: nil,
            status: .partial,
            selectedShader: nil,
            imagesFolderPath: nil,
            imagesCount: 0,
            hasLyrics: false,
            lyricsText: nil,
            lyricsLineCount: 0,
            refrainCount: 0,
            createdAt: Date(),
            lastPlayedAt: nil,
            lastAnalyzedAt: nil,
            playCount: 0
        )

        await store.upsert(song)
        await store.forceSave()

        let newStore = SongStore(databaseURL: tempDatabaseURL)
        let loadedCount = await newStore.load()

        XCTAssertEqual(loadedCount, 1)
        await newStore.shutdown()
    }

    func test_songStore_search() async throws {
        let song1 = Song(
            id: SongID(artist: "Queen", title: "Bohemian"),
            artist: "Queen",
            title: "Bohemian",
            album: "",
            duration: 180,
            bpm: 120,
            musicalKey: "",
            analysis: nil,
            status: .partial,
            selectedShader: nil,
            imagesFolderPath: nil,
            imagesCount: 0,
            hasLyrics: false,
            lyricsText: nil,
            lyricsLineCount: 0,
            refrainCount: 0,
            createdAt: Date(),
            lastPlayedAt: nil,
            lastAnalyzedAt: nil,
            playCount: 0
        )

        let song2 = Song(
            id: SongID(artist: "Beatles", title: "Hey Jude"),
            artist: "Beatles",
            title: "Hey Jude",
            album: "",
            duration: 180,
            bpm: 120,
            musicalKey: "",
            analysis: nil,
            status: .partial,
            selectedShader: nil,
            imagesFolderPath: nil,
            imagesCount: 0,
            hasLyrics: false,
            lyricsText: nil,
            lyricsLineCount: 0,
            refrainCount: 0,
            createdAt: Date(),
            lastPlayedAt: nil,
            lastAnalyzedAt: nil,
            playCount: 0
        )

        await store.upsert(song1)
        await store.upsert(song2)

        let results = await store.search(query: "Queen")
        XCTAssertEqual(results.count, 1)
    }
}

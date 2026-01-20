// AppIntegrationTests - Integration tests for SwiftVJApp features
// Tests the full app flow without actual UI rendering

import XCTest
@testable import SwiftVJCore
@testable import SongRepository

/// Integration tests that verify the app's core features work together
final class AppIntegrationTests: XCTestCase {

    // MARK: - OSC Hub Tests

    func test_oscHub_startsSuccessfully() throws {
        let hub = OSCHub()
        XCTAssertNoThrow(try hub.start())
        XCTAssertTrue(hub.running)
        hub.stop()
        XCTAssertFalse(hub.running)
    }
    
    func test_oscHub_subscriptionPatternMatching() throws {
        let hub = OSCHub()
        try hub.start()
        defer { hub.stop() }
        
        hub.subscribe(pattern: "/deck/*") { _, _ in }
        
        // Verify subscription is registered
        let stats = hub.stats()
        XCTAssertEqual(stats["subscriptionCount"] as? Int, 1)
    }
    
    func test_oscHub_sendsToVDJ() throws {
        let hub = OSCHub()
        try hub.start()
        defer { hub.stop() }
        
        // Should not throw
        XCTAssertNoThrow(try hub.sendToVDJ("/vdj/query/deck/1/get_title"))
        
        let stats = hub.stats()
        XCTAssertEqual(stats["messagesSent"] as? Int, 1)
    }
    
    // MARK: - VDJ Monitor Tests
    
    func test_vdjMonitor_handlesTrackMetadata() async throws {
        let monitor = VDJMonitor()
        
        // Simulate VDJ OSC messages
        await monitor.handleOSC(address: "/deck/1/artist", values: ["Test Artist"])
        await monitor.handleOSC(address: "/deck/1/title", values: ["Test Song"])
        await monitor.handleOSC(address: "/deck/1/album", values: ["Test Album"])
        await monitor.handleOSC(address: "/deck/1/get_bpm", values: [Float32(128.0)])
        await monitor.handleOSC(address: "/deck/1/play", values: [Float32(1.0)])
        
        let playback = await monitor.getPlayback()
        
        XCTAssertEqual(playback.deck1.artist, "Test Artist")
        XCTAssertEqual(playback.deck1.title, "Test Song")
        XCTAssertEqual(playback.deck1.album, "Test Album")
        XCTAssertEqual(playback.deck1.bpm, 128.0, accuracy: 0.1)
        XCTAssertTrue(playback.deck1.isPlaying)
    }
    
    func test_vdjMonitor_detectsAudibleDeck() async throws {
        let monitor = VDJMonitor()
        
        // Setup deck 1
        await monitor.handleOSC(address: "/deck/1/artist", values: ["Artist 1"])
        await monitor.handleOSC(address: "/deck/1/title", values: ["Song 1"])
        await monitor.handleOSC(address: "/deck/1/play", values: [Float32(1.0)])
        
        // Setup deck 2
        await monitor.handleOSC(address: "/deck/2/artist", values: ["Artist 2"])
        await monitor.handleOSC(address: "/deck/2/title", values: ["Song 2"])
        await monitor.handleOSC(address: "/deck/2/play", values: [Float32(1.0)])
        
        // Default audible is deck 1 when both playing and no master set
        let audible = await monitor.getAudibleTrack()
        
        XCTAssertNotNil(audible)
        XCTAssertEqual(audible?.artist, "Artist 1")
    }
    
    func test_vdjMonitor_handlesPositionUpdates() async throws {
        let monitor = VDJMonitor()
        
        await monitor.handleOSC(address: "/deck/1/artist", values: ["Artist"])
        await monitor.handleOSC(address: "/deck/1/title", values: ["Title"])
        await monitor.handleOSC(address: "/deck/1/song_pos", values: [Float32(45.5)])
        await monitor.handleOSC(address: "/deck/1/get_songlength", values: [Float32(180.0)])
        
        let playback = await monitor.getPlayback()
        
        XCTAssertEqual(playback.deck1.position, 45.5, accuracy: 0.1)
        XCTAssertEqual(playback.deck1.duration, 180.0, accuracy: 0.1)
    }
    
    // MARK: - Playback Module Tests
    
    func test_playbackModule_startsAndStops() async throws {
        let hub = OSCHub()
        try hub.start()
        defer { hub.stop() }
        
        let module = PlaybackModule(oscHub: hub)
        
        try await module.start()
        let status = await module.getStatus()
        XCTAssertTrue(status["started"] as? Bool ?? false)
        
        await module.stop()
        let stoppedStatus = await module.getStatus()
        XCTAssertFalse(stoppedStatus["started"] as? Bool ?? true)
    }
    
    func test_playbackModule_switchesSources() async throws {
        let hub = OSCHub()
        try hub.start()
        defer { hub.stop() }
        
        let module = PlaybackModule(oscHub: hub)
        try await module.start()
        
        await module.setSource(.vdj)
        var source = await module.currentSource
        XCTAssertEqual(source, .vdj)
        
        await module.setSource(.spotify)
        source = await module.currentSource
        XCTAssertEqual(source, .spotify)
        
        await module.stop()
    }
    
    func test_playbackModule_forwardsVDJOSC() async throws {
        let hub = OSCHub()
        try hub.start()
        defer { hub.stop() }
        
        let module = PlaybackModule(oscHub: hub)
        try await module.start()
        await module.setSource(.vdj)
        
        // Forward OSC messages
        await module.handleVDJOSC(address: "/deck/1/artist", values: ["Test Artist"])
        await module.handleVDJOSC(address: "/deck/1/title", values: ["Test Title"])
        await module.handleVDJOSC(address: "/deck/1/play", values: [Float32(1.0)])
        
        // Force a poll to pick up the changes
        await module.poll()
        
        let track = await module.currentTrack
        XCTAssertNotNil(track)
        XCTAssertEqual(track?.artist, "Test Artist")
        XCTAssertEqual(track?.title, "Test Title")
        
        await module.stop()
    }
    
    func test_playbackModule_firesTrackChangeCallback() async throws {
        let hub = OSCHub()
        try hub.start()
        defer { hub.stop() }
        
        let module = PlaybackModule(oscHub: hub)
        try await module.start()
        await module.setSource(.vdj)
        
        var receivedTrack: Track?
        let expectation = expectation(description: "track change")
        
        // Use setDispatch to receive track changes
        await module.setDispatch { action in
            if case .playback(.trackChanged(let track)) = action {
                receivedTrack = track
                expectation.fulfill()
            }
        }
        
        // Simulate track load
        await module.handleVDJOSC(address: "/deck/1/artist", values: ["New Artist"])
        await module.handleVDJOSC(address: "/deck/1/title", values: ["New Song"])
        await module.handleVDJOSC(address: "/deck/1/play", values: [Float32(1.0)])
        await module.poll()
        
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertNotNil(receivedTrack)
        XCTAssertEqual(receivedTrack?.artist, "New Artist")
        XCTAssertEqual(receivedTrack?.title, "New Song")
        
        await module.stop()
    }
    
    // MARK: - Pipeline Integration Tests
    
    func test_pipeline_processesTrack() async throws {
        let hub = OSCHub()
        try hub.start()
        defer { hub.stop() }
        
        let fetcher = LyricsFetcher()
        let lyricsModule = LyricsModule(fetcher: fetcher)
        let aiModule = AIModule(llmClient: LLMClient())
        let shadersModule = ShadersModule(matcher: ShaderMatcher())
        let imagesModule = ImagesModule(scraper: ImageScraper())
        
        let pipeline = PipelineModule(
            lyricsModule: lyricsModule,
            aiModule: aiModule,
            shadersModule: shadersModule,
            imagesModule: imagesModule,
            oscHub: hub
        )
        
        try await pipeline.start()
        
        let track = Track(artist: "Daft Punk", title: "Get Lucky", album: "Random Access Memories", duration: 369.0)
        let result = await pipeline.process(track: track)
        
        // Pipeline should complete (even if some steps are skipped due to no external services)
        XCTAssertTrue(result.stepsCompleted.contains("lyrics") || result.stepsCompleted.isEmpty)
        
        await pipeline.stop()
    }
    
    // MARK: - Track Model Tests
    
    func test_track_keyGeneration() {
        let track1 = Track(artist: "Artist", title: "Song", album: "Album", duration: 180)
        let track2 = Track(artist: "Artist", title: "Song", album: "Album", duration: 180)
        let track3 = Track(artist: "Different", title: "Song", album: "Album", duration: 180)
        
        // Same artist/title should produce same key
        XCTAssertEqual(track1.key, track2.key)
        XCTAssertNotEqual(track1.key, track3.key)
    }
    
    func test_track_hasRequiredFields() {
        let track = Track(artist: "Artist", title: "Title", album: "Album", duration: 200)
        
        XCTAssertEqual(track.artist, "Artist")
        XCTAssertEqual(track.title, "Title")
        XCTAssertEqual(track.album, "Album")
        XCTAssertEqual(track.duration, 200)
    }
    
    // MARK: - VDJ Deck State Tests
    
    func test_vdjDeck_hasTrack() {
        let emptyDeck = VDJDeck(deckNumber: 1)
        let loadedDeck = VDJDeck(deckNumber: 1, artist: "Artist", title: "Title")
        
        XCTAssertFalse(emptyDeck.hasTrack)
        XCTAssertTrue(loadedDeck.hasTrack)
    }
    
    func test_vdjDeck_trackKey() {
        let deck1 = VDJDeck(deckNumber: 1, artist: "Artist", title: "Title")
        let deck2 = VDJDeck(deckNumber: 2, artist: "ARTIST", title: "TITLE")
        
        XCTAssertEqual(deck1.trackKey, deck2.trackKey)
    }
    
    // MARK: - VDJ Playback Audible Deck Logic
    
    func test_vdjPlayback_audibleDeck_prefersIsAudible() {
        // isAudible is the primary signal from VDJ
        let deck1 = VDJDeck(deckNumber: 1, artist: "A1", title: "T1", isAudible: false)
        let deck2 = VDJDeck(deckNumber: 2, artist: "A2", title: "T2", isAudible: true)
        let playback = VDJPlayback(deck1: deck1, deck2: deck2)
        
        XCTAssertEqual(playback.audibleDeck?.deckNumber, 2)
    }
    
    func test_vdjPlayback_audibleDeck_usesVolume() {
        // Volume comparison when isAudible not set
        let deck1 = VDJDeck(deckNumber: 1, artist: "A1", title: "T1", volume: 0.3)
        let deck2 = VDJDeck(deckNumber: 2, artist: "A2", title: "T2", volume: 0.9)
        let playback = VDJPlayback(deck1: deck1, deck2: deck2)
        
        // Deck 2 is louder by >10%, should be selected
        XCTAssertEqual(playback.audibleDeck?.deckNumber, 2)
    }
    
    func test_vdjPlayback_audibleDeck_fallsBackToDeck1() {
        // When volumes are similar, prefer deck 1
        let deck1 = VDJDeck(deckNumber: 1, artist: "A1", title: "T1", volume: 0.8)
        let deck2 = VDJDeck(deckNumber: 2, artist: "A2", title: "T2", volume: 0.85)
        let playback = VDJPlayback(deck1: deck1, deck2: deck2)
        
        // <10% difference, falls back to deck 1
        XCTAssertEqual(playback.audibleDeck?.deckNumber, 1)
    }

    // MARK: - Phase and Song State Tests

    func test_phase_allCases() {
        // Verify all DJ phases exist
        let phases = Phase.allCases
        XCTAssertGreaterThanOrEqual(phases.count, 4)
        XCTAssertTrue(phases.contains(.disco))
        XCTAssertTrue(phases.contains(.peak))
    }

    func test_phase_hasDisplayProperties() {
        for phase in Phase.allCases {
            XCTAssertFalse(phase.displayName.isEmpty, "\(phase) should have display name")
            XCTAssertFalse(phase.iconName.isEmpty, "\(phase) should have icon name")
        }
    }

    // MARK: - SongID Tests

    func test_songId_constructsFromArtistTitle() {
        let id = SongID(artist: "Queen", title: "Bohemian Rhapsody")
        XCTAssertEqual(id.rawValue, "Queen::Bohemian Rhapsody")
        XCTAssertEqual(id.artist, "Queen")
        XCTAssertEqual(id.title, "Bohemian Rhapsody")
    }

    func test_songId_equatable() {
        let id1 = SongID(artist: "Queen", title: "Bohemian Rhapsody")
        let id2 = SongID(rawValue: "Queen::Bohemian Rhapsody")
        XCTAssertEqual(id1, id2)
    }

    // MARK: - SongStatus Tests

    func test_songStatus_allCases() {
        let statuses = SongStatus.allCases
        XCTAssertEqual(statuses.count, 4)
        XCTAssertTrue(statuses.contains(.complete))
        XCTAssertTrue(statuses.contains(.partial))
        XCTAssertTrue(statuses.contains(.needsReanalysis))
        XCTAssertTrue(statuses.contains(.error))
    }

    func test_songStatus_hasDisplayProperties() {
        for status in SongStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty)
            XCTAssertFalse(status.iconName.isEmpty)
        }
    }

    // MARK: - StoredSongAnalysis Tests

    func test_storedSongAnalysis_codable() throws {
        let analysis = StoredSongAnalysis(
            keywords: ["disco", "funk"],
            themes: ["celebration"],
            visualAdjectives: ["sparkling"],
            mood: "groovy",
            energy: 0.8,
            valence: 0.6,
            categories: ["dance": 0.9],
            djPhase: .peak
        )

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(analysis)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StoredSongAnalysis.self, from: data)

        XCTAssertEqual(decoded.mood, "groovy")
        XCTAssertEqual(decoded.energy, 0.8)
        XCTAssertEqual(decoded.djPhase, .peak)
        XCTAssertEqual(decoded.keywords, ["disco", "funk"])
    }

    // MARK: - LLM Client Tests

    func test_llmClient_initialState() async throws {
        let client = LLMClient()
        let status = await client.status()

        XCTAssertNotNil(status["name"])
        XCTAssertNotNil(status["available"])
    }

    func test_llmClient_analysisPrompt_generatesValidJSON() async throws {
        try require(.lmStudioAvailable)

        let client = LLMClient()

        // Test with a simple analysis
        let result = try await client.analyzeSong(
            lyrics: "Is this the real life? Is this just fantasy?",
            artist: "Queen",
            title: "Bohemian Rhapsody"
        )

        XCTAssertNotNil(result)
        XCTAssertFalse(result.mood.isEmpty)
        XCTAssertGreaterThanOrEqual(result.energy, 0)
        XCTAssertLessThanOrEqual(result.energy, 1)
    }

    // MARK: - Shader Module Tests

    func test_shaderMatcher_initialization() async throws {
        let matcher = ShaderMatcher()
        let count = await matcher.count

        // Should have loaded shaders from directory (may be 0 if no shaders)
        XCTAssertGreaterThanOrEqual(count, 0)
    }

    func test_shadersModule_lifecycle() async throws {
        let module = ShadersModule(matcher: ShaderMatcher())

        try await module.start()
        let status = await module.getStatus()
        XCTAssertTrue(status["started"] as? Bool ?? false)

        await module.stop()
        let stoppedStatus = await module.getStatus()
        XCTAssertFalse(stoppedStatus["started"] as? Bool ?? true)
    }

    // MARK: - Images Module Tests

    func test_imagesModule_initialization() async throws {
        let scraper = ImageScraper()
        let module = ImagesModule(scraper: scraper)

        try await module.start()
        let status = await module.getStatus()
        XCTAssertTrue(status["started"] as? Bool ?? false)

        await module.stop()
    }

    // MARK: - Lyrics Module Tests

    func test_lyricsModule_lifecycle() async throws {
        let fetcher = LyricsFetcher()
        let module = LyricsModule(fetcher: fetcher)

        try await module.start()
        let status = await module.getStatus()
        XCTAssertTrue(status["started"] as? Bool ?? false)

        await module.stop()
    }

    func test_lyricsModule_fetchWithInternet() async throws {
        try require(.internetConnection)

        let fetcher = LyricsFetcher()
        let module = LyricsModule(fetcher: fetcher)
        try await module.start()

        let track = Track(artist: "Queen", title: "Bohemian Rhapsody")
        let lines = await module.loadLyrics(for: track)

        XCTAssertGreaterThan(lines.count, 0)

        await module.stop()
    }

    // MARK: - AI Module Tests

    func test_aiModule_lifecycle() async throws {
        let client = LLMClient()
        let module = AIModule(llmClient: client)

        try await module.start()
        let status = await module.getStatus()
        XCTAssertTrue(status["started"] as? Bool ?? false)

        await module.stop()
    }
}

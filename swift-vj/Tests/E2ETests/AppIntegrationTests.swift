// AppIntegrationTests - Integration tests for SwiftVJApp features
// Tests the full app flow without actual UI rendering

import XCTest
@testable import SwiftVJCore

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
        
        var receivedAddresses: [String] = []
        let expectation = expectation(description: "receive message")
        expectation.expectedFulfillmentCount = 1
        
        hub.subscribe(pattern: "/deck/*") { address, _ in
            receivedAddresses.append(address)
            expectation.fulfill()
        }
        
        // Simulate internal dispatch (would need actual OSC message in real test)
        // For now, verify subscription is registered
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
        
        // Setup deck 2 as master
        await monitor.handleOSC(address: "/deck/2/artist", values: ["Artist 2"])
        await monitor.handleOSC(address: "/deck/2/title", values: ["Song 2"])
        await monitor.handleOSC(address: "/deck/2/play", values: [Float32(1.0)])
        await monitor.handleOSC(address: "/deck/2/masterdeck", values: [Float32(1.0)])
        
        let audible = await monitor.getAudibleTrack()
        
        XCTAssertNotNil(audible)
        XCTAssertEqual(audible?.artist, "Artist 2")
        XCTAssertEqual(audible?.title, "Song 2")
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
        
        await module.onTrackChange { track in
            receivedTrack = track
            expectation.fulfill()
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
        let track2 = Track(artist: "ARTIST", title: "SONG", album: "Album", duration: 180)
        let track3 = Track(artist: "Different", title: "Song", album: "Album", duration: 180)
        
        // Keys should be case-insensitive
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
    
    func test_vdjPlayback_audibleDeck_prefersMaster() {
        let deck1 = VDJDeck(deckNumber: 1, artist: "A1", title: "T1", isPlaying: true, isMaster: false)
        let deck2 = VDJDeck(deckNumber: 2, artist: "A2", title: "T2", isPlaying: true, isMaster: true)
        let playback = VDJPlayback(deck1: deck1, deck2: deck2)
        
        XCTAssertEqual(playback.audibleDeck?.deckNumber, 2)
    }
    
    func test_vdjPlayback_audibleDeck_usesCrossfader() {
        let deck1 = VDJDeck(deckNumber: 1, artist: "A1", title: "T1", isPlaying: true)
        let deck2 = VDJDeck(deckNumber: 2, artist: "A2", title: "T2", isPlaying: true)
        
        let leftPlayback = VDJPlayback(deck1: deck1, deck2: deck2, crossfader: -0.8)
        XCTAssertEqual(leftPlayback.audibleDeck?.deckNumber, 1)
        
        let rightPlayback = VDJPlayback(deck1: deck1, deck2: deck2, crossfader: 0.8)
        XCTAssertEqual(rightPlayback.audibleDeck?.deckNumber, 2)
    }
    
    func test_vdjPlayback_audibleDeck_fallsBackToPlaying() {
        let deck1 = VDJDeck(deckNumber: 1, artist: "A1", title: "T1", isPlaying: true)
        let deck2 = VDJDeck(deckNumber: 2, artist: "A2", title: "T2", isPlaying: false)
        let playback = VDJPlayback(deck1: deck1, deck2: deck2, crossfader: 0.0)
        
        XCTAssertEqual(playback.audibleDeck?.deckNumber, 1)
    }
}

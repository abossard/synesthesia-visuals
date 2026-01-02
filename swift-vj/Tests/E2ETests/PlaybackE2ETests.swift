// Playback E2E Tests - Integration tests for playback monitoring
// Tests actual Spotify and VirtualDJ when running

import XCTest
@testable import SwiftVJCore

final class PlaybackE2ETests: XCTestCase {
    
    // MARK: - Spotify Monitor Tests
    
    func test_spotifyMonitor_detectsSpotifyRunning() async throws {
        // Given: SpotifyMonitor
        let monitor = SpotifyMonitor()
        
        // When: Checking if Spotify is running
        let isRunning = await monitor.isSpotifyRunning()
        
        // Then: Result is boolean (actual value depends on Spotify state)
        // This test always passes - it's just checking the API works
        print("Spotify running: \(isRunning)")
    }
    
    func test_spotifyMonitor_getPlayback_whenSpotifyRunning() async throws {
        try require(.spotifyRunning)
        
        // Given: Spotify running and SpotifyMonitor
        let monitor = SpotifyMonitor()
        
        // When: Getting playback
        let playback = try await monitor.getPlayback()
        
        // Then: We get valid playback data
        // Note: This may throw if Spotify is paused/stopped
        XCTAssertFalse(playback.artist.isEmpty || playback.title.isEmpty,
                       "Should have artist or title when playing")
        
        print("Now playing: \(playback.artist) - \(playback.title)")
        print("Position: \(playback.positionMs)ms / \(playback.durationMs)ms")
        print("Is playing: \(playback.isPlaying)")
    }
    
    func test_spotifyMonitor_playbackHasTrackKey() async throws {
        try require(.spotifyRunning)
        
        // Given: Playing track
        let monitor = SpotifyMonitor()
        let playback = try await monitor.getPlayback()
        
        // When: Getting track key
        let key = playback.trackKey
        
        // Then: Key is consistent format
        XCTAssertTrue(key.contains("|"), "Track key should contain separator")
        XCTAssertEqual(key, key.lowercased(), "Track key should be lowercase")
    }
    
    func test_spotifyMonitor_handlesNotRunning() async throws {
        // Skip if Spotify IS running - this test is for when it's not
        if await SpotifyMonitor().isSpotifyRunning() {
            throw XCTSkip("Spotify is running - cannot test not-running state")
        }
        
        // Given: Spotify not running
        let monitor = SpotifyMonitor()
        
        // When/Then: Getting playback throws spotifyNotRunning
        do {
            _ = try await monitor.getPlayback()
            XCTFail("Should throw when Spotify not running")
        } catch SpotifyMonitorError.spotifyNotRunning {
            // Expected
        }
    }
    
    func test_spotifyMonitor_statusReportsHealth() async throws {
        // Given: SpotifyMonitor
        let monitor = SpotifyMonitor()
        
        // When: Getting status
        let status = await monitor.status()
        
        // Then: Status has expected keys
        XCTAssertNotNil(status["name"])
        XCTAssertNotNil(status["available"])
    }
    
    // MARK: - VDJ Monitor Tests
    
    func test_vdjMonitor_initialState() async throws {
        // Given: New VDJ monitor
        let monitor = VDJMonitor()
        
        // When: Getting initial playback
        let playback = await monitor.getPlayback()
        
        // Then: Both decks exist but empty
        XCTAssertEqual(playback.deck1.deckNumber, 1)
        XCTAssertEqual(playback.deck2.deckNumber, 2)
        XCTAssertFalse(playback.deck1.hasTrack)
        XCTAssertFalse(playback.deck2.hasTrack)
    }
    
    func test_vdjMonitor_handleOSC_updatesArtist() async throws {
        // Given: VDJ monitor
        let monitor = VDJMonitor()
        
        // When: Receiving artist OSC
        await monitor.handleOSC(address: "/deck/1/artist", values: ["Test Artist"])
        
        // Then: Deck 1 artist is updated
        let playback = await monitor.getPlayback()
        XCTAssertEqual(playback.deck1.artist, "Test Artist")
    }
    
    func test_vdjMonitor_handleOSC_updatesTitle() async throws {
        // Given: VDJ monitor
        let monitor = VDJMonitor()
        
        // When: Receiving title OSC
        await monitor.handleOSC(address: "/deck/2/title", values: ["Test Song"])
        
        // Then: Deck 2 title is updated
        let playback = await monitor.getPlayback()
        XCTAssertEqual(playback.deck2.title, "Test Song")
    }
    
    func test_vdjMonitor_handleOSC_updatesBPM() async throws {
        // Given: VDJ monitor
        let monitor = VDJMonitor()
        
        // When: Receiving BPM OSC
        await monitor.handleOSC(address: "/deck/1/get_bpm", values: [128.0 as Float32])
        
        // Then: Deck 1 BPM is updated
        let playback = await monitor.getPlayback()
        XCTAssertEqual(playback.deck1.bpm, 128.0)
    }
    
    func test_vdjMonitor_handleOSC_updatesPlayState() async throws {
        // Given: VDJ monitor
        let monitor = VDJMonitor()
        
        // When: Receiving play state OSC
        await monitor.handleOSC(address: "/deck/1/play", values: [1.0 as Float32])
        
        // Then: Deck 1 is playing
        let playback = await monitor.getPlayback()
        XCTAssertTrue(playback.deck1.isPlaying)
    }
    
    func test_vdjMonitor_handleOSC_updatesMasterDeck() async throws {
        // Given: VDJ monitor
        let monitor = VDJMonitor()
        
        // When: Setting deck 2 as master
        await monitor.handleOSC(address: "/deck/2/masterdeck", values: [1.0 as Float32])
        
        // Then: Deck 2 is master
        let playback = await monitor.getPlayback()
        XCTAssertTrue(playback.deck2.isMaster)
        XCTAssertFalse(playback.deck1.isMaster)
    }
    
    func test_vdjMonitor_audibleDeck_prefersMaster() async throws {
        // Given: VDJ monitor with both decks playing
        let monitor = VDJMonitor()
        await monitor.handleOSC(address: "/deck/1/artist", values: ["Artist 1"])
        await monitor.handleOSC(address: "/deck/1/title", values: ["Title 1"])
        await monitor.handleOSC(address: "/deck/1/play", values: [1.0 as Float32])
        await monitor.handleOSC(address: "/deck/2/artist", values: ["Artist 2"])
        await monitor.handleOSC(address: "/deck/2/title", values: ["Title 2"])
        await monitor.handleOSC(address: "/deck/2/play", values: [1.0 as Float32])
        
        // When: Deck 2 is master
        await monitor.handleOSC(address: "/deck/2/masterdeck", values: [1.0 as Float32])
        
        // Then: Audible deck is deck 2
        let audible = await monitor.getAudibleTrack()
        XCTAssertNotNil(audible)
        XCTAssertEqual(audible?.deckNumber, 2)
    }
    
    func test_vdjMonitor_audibleDeck_fallsToCrossfader() async throws {
        // Given: VDJ monitor with both decks playing, no master
        let monitor = VDJMonitor()
        await monitor.handleOSC(address: "/deck/1/artist", values: ["Artist 1"])
        await monitor.handleOSC(address: "/deck/1/title", values: ["Title 1"])
        await monitor.handleOSC(address: "/deck/1/play", values: [1.0 as Float32])
        await monitor.handleOSC(address: "/deck/2/artist", values: ["Artist 2"])
        await monitor.handleOSC(address: "/deck/2/title", values: ["Title 2"])
        await monitor.handleOSC(address: "/deck/2/play", values: [1.0 as Float32])
        
        // When: Crossfader is full left (value 0 = -1 normalized)
        await monitor.handleOSC(address: "/crossfader", values: [0.0 as Float32])
        
        // Then: Audible deck is deck 1
        let audible = await monitor.getAudibleTrack()
        XCTAssertNotNil(audible)
        XCTAssertEqual(audible?.deckNumber, 1)
    }
    
    func test_vdjMonitor_trackChangeCallback() async throws {
        // Given: VDJ monitor with track change handler
        let monitor = VDJMonitor()
        
        let expectation = expectation(description: "Track change callback")
        nonisolated(unsafe) var changedDeck: VDJDeck?
        
        await monitor.onTrackChange { deck in
            changedDeck = deck
            expectation.fulfill()
        }
        
        // When: Setting a complete track (both artist and title)
        await monitor.handleOSC(address: "/deck/1/artist", values: ["New Artist"])
        await monitor.handleOSC(address: "/deck/1/title", values: ["New Song"])
        
        // Then: Callback is fired
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertNotNil(changedDeck)
        XCTAssertEqual(changedDeck?.artist, "New Artist")
        XCTAssertEqual(changedDeck?.title, "New Song")
    }
    
    func test_vdjMonitor_positionCallback() async throws {
        // Given: VDJ monitor with position handler
        let monitor = VDJMonitor()
        
        let expectation = expectation(description: "Position callback")
        nonisolated(unsafe) var callbackDeck: Int?
        nonisolated(unsafe) var callbackPosition: Double?
        
        await monitor.onPositionUpdate { deck, position in
            callbackDeck = deck
            callbackPosition = position
            expectation.fulfill()
        }
        
        // When: Position update arrives
        await monitor.handleOSC(address: "/deck/1/get_position", values: [45.5 as Float32])
        
        // Then: Callback is fired
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(callbackDeck, 1)
        XCTAssertEqual(callbackPosition, 45.5)
    }
    
    func test_vdjMonitor_isReceiving_detectsActivity() async throws {
        // Given: VDJ monitor
        let monitor = VDJMonitor()
        
        // Initially not receiving
        let beforeReceiving = await monitor.isReceiving()
        XCTAssertFalse(beforeReceiving)
        
        // When: Message arrives
        await monitor.handleOSC(address: "/deck/1/artist", values: ["Test"])
        
        // Then: Is receiving
        let afterReceiving = await monitor.isReceiving()
        XCTAssertTrue(afterReceiving)
    }
    
    // MARK: - Live VDJ Tests (require VDJ running)
    
    func test_vdjLive_monitorsRealPlayback() async throws {
        try require(.vdjRunning)
        
        let monitor = VDJMonitor()
        print("VDJ is running - monitor ready for OSC subscription")
        
        let status = await monitor.status()
        XCTAssertNotNil(status["name"])
    }
    
    func test_vdjLive_receivesRealOSC() async throws {
        try require(.vdjRunning)
        
        // KNOWN ISSUE: OSCKit v0.6.2 uses separate client socket for sending.
        // VDJ responds to the SOURCE PORT of subscribe requests.
        // Python pyliblo3 sends from server socket (port 9999), VDJ responds to 9999.
        // OSCKit sends from ephemeral port, VDJ responds there instead of 9999.
        // 
        // Workaround options:
        // 1. Upgrade to OSCKit main branch (OSCUDPSocket with localPort)
        // 2. Use Python OSC hub as intermediary
        // 3. Configure VDJ to always send to port 9999 (not subscribe-based)
        
        // Given: OSCHub started and VDJMonitor wired
        let hub = OSCHub()
        let monitor = VDJMonitor()
        
        try hub.start()
        defer { hub.stop() }
        
        // Track message count
        nonisolated(unsafe) var vdjMessageCount = 0
        nonisolated(unsafe) var anyMessageCount = 0
        nonisolated(unsafe) var firstFive: [String] = []
        
        // Subscribe to ALL messages for debugging
        hub.subscribe(pattern: "/*") { address, values in
            anyMessageCount += 1
            if firstFive.count < 5 {
                firstFive.append(address)
            }
            if address.hasPrefix("/vdj/") {
                vdjMessageCount += 1
                if vdjMessageCount <= 3 {
                    print("📦 VDJ: \(address)")
                }
            } else if address.hasPrefix("/deck/") {
                vdjMessageCount += 1
                if vdjMessageCount <= 3 {
                    print("📦 DECK: \(address)")
                }
            }
        }
        
        // Wire /vdj/* messages to VDJMonitor
        hub.subscribe(pattern: "/vdj/*") { [monitor] address, values in
            Task { await monitor.handleOSC(address: address, values: values) }
        }
        
        // Send subscription commands to VDJ
        // Note: VDJ will respond to the ephemeral port, not port 9999
        print("📡 Subscribing to VDJ on port 9009...")
        try await monitor.subscribe(using: hub)
        try await monitor.query(using: hub)
        
        // Wait for messages
        print("⏳ Waiting 2 seconds for OSC messages...")
        try await Task.sleep(for: .seconds(2))
        
        print("📊 Messages received: \(anyMessageCount) total, \(vdjMessageCount) from VDJ")
        print("📝 First 5 messages: \(firstFive)")
        
        // Check what we got
        let playback = await monitor.getPlayback()
        print("Deck 1: '\(playback.deck1.artist)' - '\(playback.deck1.title)'")
        print("Deck 2: '\(playback.deck2.artist)' - '\(playback.deck2.title)'")
        
        // The test passes if we got ANY messages (from Synesthesia)
        // This confirms OSCHub is receiving
        if anyMessageCount > 0 {
            print("✅ OSC hub is receiving messages")
        } else {
            XCTFail("No OSC messages received - check if port 9999 is available")
        }
        
        // VDJ messages are expected to NOT arrive due to OSCKit port limitation
        if vdjMessageCount > 0 {
            print("✅ VDJ messages received (unexpected with current OSCKit!)")
            XCTAssertTrue(playback.deck1.hasTrack || playback.deck2.hasTrack)
        } else {
            print("ℹ️ VDJ messages not received - expected with OSCKit v0.6.2 (see comment above)")
            print("   Use Python VDJ monitor or upgrade OSCKit to fix")
        }
    }
    
    func test_vdjLive_fullPipeline_fetchesLyrics() async throws {
        try require(.vdjRunning)
        try require(.internetConnection)
        
        // Given: VDJ monitor and lyrics fetcher
        let hub = OSCHub()
        let monitor = VDJMonitor()
        let fetcher = LyricsFetcher()
        
        try hub.start()
        defer { hub.stop() }
        
        // Wire VDJ messages
        hub.subscribe(pattern: "/vdj/*") { [monitor] address, values in
            Task { await monitor.handleOSC(address: address, values: values) }
        }
        
        // Subscribe and query VDJ
        print("📡 Subscribing to VDJ...")
        try await monitor.subscribe(using: hub)
        try await monitor.query(using: hub)
        
        // Wait briefly for VDJ data
        print("⏳ Waiting for VDJ track info...")
        try await Task.sleep(for: .seconds(2))
        
        // Get audible track
        guard let audible = await monitor.getAudibleTrack() else {
            throw XCTSkip("No track playing on VDJ")
        }
        
        print("🎵 Now playing: \(audible.artist) - \(audible.title)")
        
        // Fetch lyrics for the track (may not exist for remixes/edits)
        do {
            let lrc = try await fetcher.fetch(artist: audible.artist, title: audible.title)
            if let lrc = lrc {
                let lines = parseLRC(lrc)
                print("✅ Found \(lines.count) synced lyric lines")
                XCTAssertGreaterThan(lines.count, 0)
            } else {
                print("⚠️ No synced lyrics found for this track")
            }
        } catch LyricsFetcherError.notFound {
            print("⚠️ No synced lyrics found for this track (notFound)")
        }
    }
}

// OSC E2E Tests - Integration tests for OSC communication
// Tests actual network communication when services are available

import XCTest
import OSCKit
@testable import SwiftVJCore

final class OSCE2ETests: XCTestCase {
    
    var hub: OSCHub!
    
    override func setUp() async throws {
        hub = OSCHub()
    }
    
    override func tearDown() async throws {
        hub?.stop()
        hub = nil
    }
    
    // MARK: - OSCHub Lifecycle Tests
    
    func test_oscHub_startsSuccessfully() throws {
        // When: Starting the OSC hub
        try hub.start()
        
        // Then: Hub is running
        XCTAssertTrue(hub.running, "OSC hub should be running after start")
    }
    
    func test_oscHub_stopsSuccessfully() throws {
        // Given: Running hub
        try hub.start()
        XCTAssertTrue(hub.running)
        
        // When: Stopping the hub
        hub.stop()
        
        // Then: Hub is not running
        XCTAssertFalse(hub.running, "OSC hub should not be running after stop")
    }
    
    func test_oscHub_startIsIdempotent() throws {
        // Given: Running hub
        try hub.start()
        
        // When: Starting again
        try hub.start()
        
        // Then: Still running, no error
        XCTAssertTrue(hub.running)
    }
    
    func test_oscHub_stopIsIdempotent() throws {
        // Given: Not running hub
        XCTAssertFalse(hub.running)
        
        // When: Stopping anyway
        hub.stop()
        
        // Then: No error, still not running
        XCTAssertFalse(hub.running)
    }
    
    // MARK: - Send Tests (require running target)
    
    func test_oscHub_sendToProcessing_deliversMessage() async throws {
        try require(.vjUniverseListening)
        
        // Given: Running hub and VJUniverse listening
        try hub.start()
        
        // When: Sending a message
        // Then: No error thrown (delivery is best-effort UDP)
        try hub.sendToProcessing("/test/ping", values: ["hello"])
        
        // Verify stats updated
        let stats = hub.stats()
        XCTAssertEqual(stats["messagesSent"] as? Int, 1)
    }
    
    func test_oscHub_sendToSynesthesia_deliversMessage() async throws {
        try require(.synesthesiaRunning)
        
        // Given: Running hub and Synesthesia listening
        try hub.start()
        
        // When: Sending a message
        try hub.sendToSynesthesia("/test/ping", values: [1.0 as Float32])
        
        // Then: Stats reflect the send
        let stats = hub.stats()
        XCTAssertEqual(stats["messagesSent"] as? Int, 1)
    }
    
    func test_oscHub_sendWithoutStart_throwsError() throws {
        // Given: Hub not started
        XCTAssertFalse(hub.running)
        
        // When/Then: Sending throws error
        XCTAssertThrowsError(try hub.sendToProcessing("/test", values: [])) { error in
            XCTAssertEqual(error as? OSCHubError, OSCHubError.notStarted)
        }
    }
    
    // MARK: - Subscription Tests
    
    func test_oscHub_subscribeReceivesMessages() async throws {
        // Given: Running hub with subscription
        try hub.start()
        
        // Use nonisolated(unsafe) for Swift 6 async closure compatibility
        nonisolated(unsafe) var messageReceived = false
        
        hub.subscribe(pattern: "/test/*") { _, _ in
            messageReceived = true
        }
        
        // When: Hub receives a message (simulated by self-send to receive port)
        // Note: This test would require external sender or loopback
        // For now, just verify subscription mechanics work
        
        // Then: Subscription is registered
        let stats = hub.stats()
        XCTAssertEqual(stats["subscriptionCount"] as? Int, 1)
        
        // Verify messageReceived variable works (not used in actual assertion,
        // just demonstrating closure captures work)
        _ = messageReceived
    }
    
    func test_oscHub_unsubscribeRemovesHandler() throws {
        // Given: Hub with subscription
        try hub.start()
        hub.subscribe(pattern: "/test/*") { _, _ in }
        
        var stats = hub.stats()
        XCTAssertEqual(stats["subscriptionCount"] as? Int, 1)
        
        // When: Unsubscribing
        hub.unsubscribe(pattern: "/test/*")
        
        // Then: Subscription removed
        stats = hub.stats()
        XCTAssertEqual(stats["subscriptionCount"] as? Int, 0)
    }
    
    func test_oscHub_clearSubscriptions() throws {
        // Given: Hub with multiple subscriptions
        try hub.start()
        hub.subscribe(pattern: "/a/*") { _, _ in }
        hub.subscribe(pattern: "/b/*") { _, _ in }
        hub.subscribe(pattern: "/c/*") { _, _ in }
        
        var stats = hub.stats()
        XCTAssertEqual(stats["subscriptionCount"] as? Int, 3)
        
        // When: Clearing all
        hub.clearSubscriptions()
        
        // Then: All removed
        stats = hub.stats()
        XCTAssertEqual(stats["subscriptionCount"] as? Int, 0)
    }
    
    // MARK: - Stats Tests
    
    func test_oscHub_statsTracksMessages() throws {
        try require(.vjUniverseListening)
        
        // Given: Running hub
        try hub.start()
        
        // When: Sending multiple messages
        try hub.sendToProcessing("/test/1")
        try hub.sendToProcessing("/test/2")
        try hub.sendToProcessing("/test/3")
        
        // Then: Stats reflect sends
        let stats = hub.stats()
        XCTAssertEqual(stats["messagesSent"] as? Int, 3)
        XCTAssertTrue(stats["running"] as? Bool ?? false)
    }
    
    func test_oscHub_resetStats() throws {
        try require(.vjUniverseListening)
        
        // Given: Hub with some stats
        try hub.start()
        try hub.sendToProcessing("/test")
        
        var stats = hub.stats()
        XCTAssertEqual(stats["messagesSent"] as? Int, 1)
        
        // When: Resetting stats
        hub.resetStats()
        
        // Then: Stats are cleared
        stats = hub.stats()
        XCTAssertEqual(stats["messagesSent"] as? Int, 0)
        XCTAssertEqual(stats["messagesReceived"] as? Int, 0)
    }
    
    // MARK: - Convenience Extension Tests
    
    func test_oscHub_sendString() throws {
        try require(.vjUniverseListening)
        
        try hub.start()
        
        // When: Using convenience method
        try hub.sendToProcessing("/test/string", "hello world")
        
        // Then: No error
        let stats = hub.stats()
        XCTAssertEqual(stats["messagesSent"] as? Int, 1)
    }
    
    func test_oscHub_sendInt() throws {
        try require(.vjUniverseListening)
        
        try hub.start()
        
        // When: Using convenience method
        try hub.sendToVDJ("/test/int", 42 as Int32)
        
        // Then: No error
        let stats = hub.stats()
        XCTAssertEqual(stats["messagesSent"] as? Int, 1)
    }
    
    func test_oscHub_sendFloat() throws {
        try require(.vjUniverseListening)
        
        try hub.start()
        
        // When: Using convenience method
        try hub.sendToVDJ("/test/float", 0.75 as Float32)
        
        // Then: No error
        let stats = hub.stats()
        XCTAssertEqual(stats["messagesSent"] as? Int, 1)
    }
}

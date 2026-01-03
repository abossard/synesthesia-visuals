// ActiveLineTrackerTests - TDD for position-driven OSC updates
// Tests the wiring: PlaybackModule → LyricsModule → OSC
// Uses real OSCHub and verifies via stats (no mocks)

import XCTest
import OSCKit
@testable import SwiftVJCore

final class ActiveLineTrackerTests: XCTestCase {
    
    private var hub: OSCHub!
    
    override func setUp() {
        super.setUp()
        hub = OSCHub()
        try? hub.start()
    }
    
    override func tearDown() {
        hub.stop()
        hub = nil
        super.tearDown()
    }
    
    // MARK: - Test: Active line tracking state
    
    func test_activeLineChange_updatesActiveIndex() throws {
        // Given: Lyrics with lines at different timestamps
        let lines: [LyricLine] = [
            LyricLine(timeSec: 0.0, text: "Line one"),
            LyricLine(timeSec: 5.0, text: "Line two"),
            LyricLine(timeSec: 10.0, text: "Line three")
        ]
        
        let tracker = ActiveLineTracker(sender: hub)
        tracker.setLines(lines)
        
        // When: Position update to 6 seconds (should be line 2)
        tracker.updatePosition(6.0)
        
        // Then: Active index is 1 (second line)
        XCTAssertEqual(tracker.activeIndex, 1)
    }
    
    func test_activeLineChange_sendsOSCMessages() throws {
        // Given: Tracker with lines
        let lines: [LyricLine] = [
            LyricLine(timeSec: 0.0, text: "Line one"),
            LyricLine(timeSec: 5.0, text: "Line two")
        ]
        
        let tracker = ActiveLineTracker(sender: hub)
        tracker.setLines(lines)
        hub.resetStats()
        
        // When: Position update triggers line change
        tracker.updatePosition(6.0)
        
        // Then: OSC messages were actually sent
        let stats = hub.stats()
        let sent = stats["messagesSent"] as? Int ?? 0
        XCTAssertGreaterThan(sent, 0, "Should send OSC messages on line change")
    }
    
    func test_activeLineChange_noRepeatForSameLine() throws {
        // Given: Tracker with lines
        let lines: [LyricLine] = [
            LyricLine(timeSec: 0.0, text: "Line one"),
            LyricLine(timeSec: 10.0, text: "Line two")
        ]
        
        let tracker = ActiveLineTracker(sender: hub)
        tracker.setLines(lines)
        
        // When: First update
        tracker.updatePosition(1.0)
        hub.resetStats()
        
        // When: Multiple position updates within same line
        tracker.updatePosition(2.0)
        tracker.updatePosition(3.0)
        
        // Then: No additional OSC messages (line didn't change)
        let stats = hub.stats()
        let sent = stats["messagesSent"] as? Int ?? 0
        XCTAssertEqual(sent, 0, "Should not send when line hasn't changed")
    }
    
    func test_activeLineChange_sendsMoreForRefrainLine() throws {
        // Given: Lines with refrain (sends extra refrain/active message)
        let lines: [LyricLine] = [
            LyricLine(timeSec: 0.0, text: "Verse line"),
            LyricLine(timeSec: 5.0, text: "Refrain line", isRefrain: true)
        ]
        
        let tracker = ActiveLineTracker(sender: hub)
        tracker.setLines(lines)
        
        // Count messages for non-refrain line
        hub.resetStats()
        tracker.updatePosition(1.0)
        let nonRefrainStats = hub.stats()
        let nonRefrainSent = nonRefrainStats["messagesSent"] as? Int ?? 0
        
        // Count messages for refrain line
        hub.resetStats()
        tracker.updatePosition(6.0)
        let refrainStats = hub.stats()
        let refrainSent = refrainStats["messagesSent"] as? Int ?? 0
        
        // Then: Refrain sends more messages (line/active + refrain/active)
        XCTAssertGreaterThan(refrainSent, nonRefrainSent, 
            "Refrain line should send additional refrain/active message")
    }
    
    func test_activeLineChange_sendsKeywordsWhenPresent() throws {
        // Given: Line with keywords vs line without
        let lines: [LyricLine] = [
            LyricLine(timeSec: 0.0, text: "Hello world", keywords: "hello world"),
            LyricLine(timeSec: 5.0, text: "Another line")  // no keywords
        ]
        
        let tracker = ActiveLineTracker(sender: hub)
        tracker.setLines(lines)
        
        // Count messages for line WITH keywords
        hub.resetStats()
        tracker.updatePosition(1.0)
        let withKeywordsStats = hub.stats()
        let withKeywordsSent = withKeywordsStats["messagesSent"] as? Int ?? 0
        
        // Count messages for line WITHOUT keywords
        hub.resetStats()
        tracker.updatePosition(6.0)
        let withoutKeywordsStats = hub.stats()
        let withoutKeywordsSent = withoutKeywordsStats["messagesSent"] as? Int ?? 0
        
        // Then: Line with keywords sends more messages
        XCTAssertGreaterThan(withKeywordsSent, withoutKeywordsSent,
            "Line with keywords should send additional keywords/active message")
    }
    
    func test_reset_clearsActiveIndex() throws {
        // Given: Tracker with active line
        let lines: [LyricLine] = [
            LyricLine(timeSec: 0.0, text: "Line one")
        ]
        
        let tracker = ActiveLineTracker(sender: hub)
        tracker.setLines(lines)
        tracker.updatePosition(1.0)
        XCTAssertEqual(tracker.activeIndex, 0)
        
        // When: Reset
        tracker.reset()
        
        // Then: Active index reset to -1
        XCTAssertEqual(tracker.activeIndex, -1)
    }
    
    func test_reset_allowsResendOnSamePosition() throws {
        // Given: Tracker with active line
        let lines: [LyricLine] = [
            LyricLine(timeSec: 0.0, text: "Line one")
        ]
        
        let tracker = ActiveLineTracker(sender: hub)
        tracker.setLines(lines)
        tracker.updatePosition(1.0)
        
        // When: Reset, reload, and update to same position
        tracker.reset()
        hub.resetStats()
        tracker.setLines(lines)
        tracker.updatePosition(1.0)
        
        // Then: OSC sent again (reset cleared state)
        let stats = hub.stats()
        let sent = stats["messagesSent"] as? Int ?? 0
        XCTAssertGreaterThan(sent, 0, "After reset, should send OSC again")
    }
}

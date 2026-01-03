// TextlerOrchestratorTests - TDD for the main orchestrator
// Uses real OSCHub and verifies via stats (no mocks)

import XCTest
import OSCKit
@testable import SwiftVJCore

final class TextlerOrchestratorTests: XCTestCase {
    
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
    
    // MARK: - Test: Orchestrator lifecycle
    
    func test_orchestrator_startAndStop() async throws {
        // Given: Orchestrator with real OSC hub
        let orchestrator = TextlerOrchestrator(oscHub: hub)
        
        // When: Start
        try await orchestrator.start()
        
        // Then: Started
        XCTAssertTrue(orchestrator.isStarted)
        
        // When: Stop
        await orchestrator.stop()
        
        // Then: Stopped
        XCTAssertFalse(orchestrator.isStarted)
    }
    
    func test_orchestrator_positionUpdate_sendsOSC() async throws {
        // Given: Orchestrator with lines loaded
        let orchestrator = TextlerOrchestrator(oscHub: hub)
        try await orchestrator.start()
        
        let lines = [
            LyricLine(timeSec: 0.0, text: "First line"),
            LyricLine(timeSec: 5.0, text: "Second line"),
            LyricLine(timeSec: 10.0, text: "Third line")
        ]
        orchestrator.setLines(lines)
        hub.resetStats()
        
        // When: Position update
        orchestrator.handlePositionUpdate(position: 6.0, isPlaying: true)
        
        // Then: OSC messages sent
        let stats = hub.stats()
        let sent = stats["messagesSent"] as? Int ?? 0
        XCTAssertGreaterThan(sent, 0, "Should send OSC on position update")
        
        await orchestrator.stop()
    }
    
    func test_orchestrator_trackChange_resetsState() async throws {
        // Given: Orchestrator with active position
        let orchestrator = TextlerOrchestrator(oscHub: hub)
        try await orchestrator.start()
        
        let lines = [LyricLine(timeSec: 0.0, text: "Old line")]
        orchestrator.setLines(lines)
        orchestrator.handlePositionUpdate(position: 1.0, isPlaying: true)
        XCTAssertEqual(orchestrator.activeLineIndex, 0)
        
        // When: Track change (reset)
        orchestrator.handleTrackChange()
        
        // Then: Active index reset
        XCTAssertEqual(orchestrator.activeLineIndex, -1)
        
        await orchestrator.stop()
    }
    
    func test_orchestrator_positionUpdate_ignoredWhenNotPlaying() async throws {
        // Given: Orchestrator with lines
        let orchestrator = TextlerOrchestrator(oscHub: hub)
        try await orchestrator.start()
        
        let lines = [LyricLine(timeSec: 0.0, text: "Line")]
        orchestrator.setLines(lines)
        hub.resetStats()
        
        // When: Position update with isPlaying=false
        orchestrator.handlePositionUpdate(position: 1.0, isPlaying: false)
        
        // Then: No OSC sent
        let stats = hub.stats()
        let sent = stats["messagesSent"] as? Int ?? 0
        XCTAssertEqual(sent, 0, "Should not send OSC when not playing")
        
        await orchestrator.stop()
    }
}

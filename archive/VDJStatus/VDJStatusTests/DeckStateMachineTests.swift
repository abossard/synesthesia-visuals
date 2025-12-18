import XCTest
@testable import VDJStatus

final class DeckStateMachineTests: XCTestCase {
    
    let config = FSMConfig.default
    
    // MARK: - Initial State Tests
    
    func testInitialStateIsUnknown() {
        let state = MasterState.initial
        XCTAssertEqual(state.deck1.playState, .unknown)
        XCTAssertEqual(state.deck2.playState, .unknown)
        XCTAssertNil(state.master)
    }
    
    // MARK: - Elapsed Reading Transitions
    
    func testFirstElapsedReadingStartsPlaying() {
        // Given: Initial state (unknown)
        var state = MasterState.initial
        
        // When: First elapsed reading
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        
        // Then: Deck 1 is playing
        XCTAssertEqual(state.deck1.playState, .playing)
        XCTAssertEqual(state.deck1.lastElapsed, 10.0)
        XCTAssertEqual(state.deck1.stableCount, 0)
    }
    
    func testElapsedChangingMeansPlaying() {
        // Given: Deck 1 at elapsed 10.0
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        
        // When: Elapsed increases
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 12.0))
        
        // Then: Still playing with new elapsed
        XCTAssertEqual(state.deck1.playState, .playing)
        XCTAssertEqual(state.deck1.lastElapsed, 12.0)
        XCTAssertEqual(state.deck1.stableCount, 0)
    }
    
    func testElapsedUnchangedIncrementsStableCount() {
        // Given: Deck 1 playing at 10.0
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        XCTAssertEqual(state.deck1.stableCount, 0)
        
        // When: Same elapsed
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        
        // Then: Stable count increases
        XCTAssertEqual(state.deck1.stableCount, 1)
        XCTAssertEqual(state.deck1.playState, .playing)  // Not stopped yet
    }
    
    func testElapsedUnchangedHitsThresholdBecomeStopped() {
        // Given: Deck 1 playing
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0), config: config)
        
        // When: Same elapsed hits stableThreshold times
        for i in 1...config.stableThreshold {
            state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0), config: config)
            XCTAssertEqual(state.deck1.stableCount, i)
        }
        
        // Then: Now stopped
        XCTAssertEqual(state.deck1.playState, .stopped)
    }
    
    func testStoppedDeckRestartsOnElapsedChange() {
        // Given: Deck 1 stopped at 10.0
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0), config: config)
        for _ in 0..<config.stableThreshold {
            state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0), config: config)
        }
        XCTAssertEqual(state.deck1.playState, .stopped)
        
        // When: Elapsed changes
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 11.0 + config.elapsedEpsilon), config: config)
        
        // Then: Playing again
        XCTAssertEqual(state.deck1.playState, .playing)
        XCTAssertEqual(state.deck1.stableCount, 0)
    }
    
    func testUndefinedElapsedDoesNotChangeState() {
        // Given: Deck 1 playing at 10.0
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        let beforeState = state.deck1
        
        // When: Undefined elapsed (nil)
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: nil))
        
        // Then: State unchanged
        XCTAssertEqual(state.deck1, beforeState)
    }
    
    // MARK: - Fader Reading Transitions
    
    func testFaderReadingUpdatesPosition() {
        // Given: Initial state
        var state = MasterState.initial
        
        // When: Fader reading
        state = transition(state, event: .faderReading(deck: 1, position: 0.25))
        
        // Then: Fader position set
        XCTAssertEqual(state.deck1.faderPosition, 0.25)
    }
    
    func testFaderPercentCalculation() {
        var state = MasterState.initial
        
        // Fader at top (position 0) = 100%
        state = transition(state, event: .faderReading(deck: 1, position: 0.0))
        XCTAssertEqual(state.deck1.faderPercent, 100)
        
        // Fader at bottom (position 1) = 0%
        state = transition(state, event: .faderReading(deck: 1, position: 1.0))
        XCTAssertEqual(state.deck1.faderPercent, 0)
        
        // Fader at middle
        state = transition(state, event: .faderReading(deck: 1, position: 0.5))
        XCTAssertEqual(state.deck1.faderPercent, 50)
    }
    
    func testNilFaderReadingKeepsPreviousPosition() {
        // Given: Fader at 0.25
        var state = MasterState.initial
        state = transition(state, event: .faderReading(deck: 1, position: 0.25))
        
        // When: Nil reading
        state = transition(state, event: .faderReading(deck: 1, position: nil))
        
        // Then: Previous position kept
        XCTAssertEqual(state.deck1.faderPosition, 0.25)
    }
    
    // MARK: - Master Detection Tests
    
    func testOnlyDeck1PlayingMakesDeck1Master() {
        // Given: Both unknown
        var state = MasterState.initial
        
        // When: Only deck 1 starts playing
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        
        // Then: Deck 1 is master
        XCTAssertEqual(state.master, 1)
    }
    
    func testOnlyDeck2PlayingMakesDeck2Master() {
        // Given: Both unknown
        var state = MasterState.initial
        
        // When: Only deck 2 starts playing
        state = transition(state, event: .elapsedReading(deck: 2, elapsed: 10.0))
        
        // Then: Deck 2 is master
        XCTAssertEqual(state.master, 2)
    }
    
    func testBothPlayingHigherFaderWins() {
        // Given: Both decks playing
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        state = transition(state, event: .elapsedReading(deck: 2, elapsed: 20.0))
        
        // When: Deck 1 fader higher (lower position value)
        state = transition(state, event: .faderReading(deck: 1, position: 0.2))
        state = transition(state, event: .faderReading(deck: 2, position: 0.8))
        
        // Then: Deck 1 is master
        XCTAssertEqual(state.master, 1)
    }
    
    func testBothPlayingDeck2HigherFader() {
        // Given: Both decks playing
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        state = transition(state, event: .elapsedReading(deck: 2, elapsed: 20.0))
        
        // When: Deck 2 fader higher (lower position value)
        state = transition(state, event: .faderReading(deck: 1, position: 0.9))
        state = transition(state, event: .faderReading(deck: 2, position: 0.1))
        
        // Then: Deck 2 is master
        XCTAssertEqual(state.master, 2)
    }
    
    func testEqualFadersKeepCurrentMaster() {
        // Given: Both playing, deck 1 master via higher fader
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        state = transition(state, event: .elapsedReading(deck: 2, elapsed: 20.0))
        state = transition(state, event: .faderReading(deck: 1, position: 0.2))
        state = transition(state, event: .faderReading(deck: 2, position: 0.8))
        XCTAssertEqual(state.master, 1)
        
        // When: Faders become equal (within threshold)
        state = transition(state, event: .faderReading(deck: 2, position: 0.21))
        
        // Then: Master unchanged
        XCTAssertEqual(state.master, 1)
    }
    
    func testFaderCatchUpChangesMaster() {
        // Given: Both playing, deck 1 master
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0))
        state = transition(state, event: .elapsedReading(deck: 2, elapsed: 20.0))
        state = transition(state, event: .faderReading(deck: 1, position: 0.2))
        state = transition(state, event: .faderReading(deck: 2, position: 0.8))
        XCTAssertEqual(state.master, 1)
        
        // When: Deck 2 fader goes higher than deck 1
        state = transition(state, event: .faderReading(deck: 2, position: 0.1))
        
        // Then: Deck 2 becomes master
        XCTAssertEqual(state.master, 2)
    }
    
    func testPlayingDeckStopsMasterTransfersToOther() {
        // Given: Both playing, deck 1 master
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0), config: config)
        state = transition(state, event: .elapsedReading(deck: 2, elapsed: 20.0), config: config)
        state = transition(state, event: .faderReading(deck: 1, position: 0.2), config: config)
        state = transition(state, event: .faderReading(deck: 2, position: 0.8), config: config)
        XCTAssertEqual(state.master, 1)
        
        // When: Deck 1 stops (elapsed unchanged stableThreshold times)
        for _ in 0..<config.stableThreshold {
            state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0), config: config)
        }
        
        // Then: Deck 2 becomes master (only one playing)
        XCTAssertEqual(state.deck1.playState, .stopped)
        XCTAssertEqual(state.deck2.playState, .playing)
        XCTAssertEqual(state.master, 2)
    }
    
    func testBothStoppedNoMaster() {
        // Given: Both playing
        var state = MasterState.initial
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0), config: config)
        state = transition(state, event: .elapsedReading(deck: 2, elapsed: 20.0), config: config)
        
        // When: Both stop (unchanged stableThreshold times)
        for _ in 0..<config.stableThreshold {
            state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0), config: config)
            state = transition(state, event: .elapsedReading(deck: 2, elapsed: 20.0), config: config)
        }
        
        // Then: No master
        XCTAssertEqual(state.deck1.playState, .stopped)
        XCTAssertEqual(state.deck2.playState, .stopped)
        XCTAssertNil(state.master)
    }
    
    // MARK: - Deck 2 Specific Tests (symmetry)
    
    func testDeck2ElapsedTransitionsWork() {
        var state = MasterState.initial
        
        // Deck 2 starts playing
        state = transition(state, event: .elapsedReading(deck: 2, elapsed: 5.0), config: config)
        XCTAssertEqual(state.deck2.playState, .playing)
        XCTAssertEqual(state.deck2.lastElapsed, 5.0)
        
        // Deck 2 stops (unchanged stableThreshold times)
        for _ in 0..<config.stableThreshold {
            state = transition(state, event: .elapsedReading(deck: 2, elapsed: 5.0), config: config)
        }
        XCTAssertEqual(state.deck2.playState, .stopped)
    }
    
    func testDeck2FaderUpdates() {
        var state = MasterState.initial
        state = transition(state, event: .faderReading(deck: 2, position: 0.75))
        XCTAssertEqual(state.deck2.faderPosition, 0.75)
        XCTAssertEqual(state.deck2.faderPercent, 25)
    }
    
    // MARK: - Epsilon Threshold Tests
    
    func testElapsedWithinEpsilonCountsAsUnchanged() {
        // Custom config with larger epsilon to test jitter tolerance
        let customConfig = FSMConfig(
            pollInterval: 1.0,
            stableThreshold: 3,
            elapsedEpsilon: 1.0,  // Large epsilon for testing
            faderEqualThreshold: 0.02
        )
        
        var state = MasterState.initial
        
        // Initial reading
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.0), config: customConfig)
        XCTAssertEqual(state.deck1.stableCount, 0)
        
        // Within epsilon (10.4 is NOT > 10.0 + 1.0)
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 10.4), config: customConfig)
        XCTAssertEqual(state.deck1.stableCount, 1)  // Counts as unchanged
        
        // Outside epsilon (12.0 > 10.4 + 1.0)
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 12.0), config: customConfig)
        XCTAssertEqual(state.deck1.stableCount, 0)  // Reset, playing
    }
    
    // MARK: - Complex Scenario Tests
    
    func testFullDJTransitionScenario() {
        var state = MasterState.initial
        
        // 1. DJ loads track on deck 1 (not playing yet)
        state = transition(state, event: .faderReading(deck: 1, position: 0.5))
        XCTAssertNil(state.master)
        
        // 2. DJ starts playing deck 1
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 0.5))
        XCTAssertEqual(state.master, 1)
        XCTAssertEqual(state.deck1.playState, .playing)
        
        // 3. Deck 1 continues playing
        state = transition(state, event: .elapsedReading(deck: 1, elapsed: 30.0))
        XCTAssertEqual(state.master, 1)
        
        // 4. DJ cues deck 2 (fader down, starts playing)
        state = transition(state, event: .faderReading(deck: 2, position: 1.0))
        state = transition(state, event: .elapsedReading(deck: 2, elapsed: 0.0))
        // Both playing, deck 1 fader higher → deck 1 still master
        XCTAssertEqual(state.master, 1)
        
        // 5. DJ brings deck 2 fader up past deck 1
        state = transition(state, event: .faderReading(deck: 2, position: 0.3))
        XCTAssertEqual(state.master, 2)  // Deck 2 now master
        
        // 6. DJ fades out deck 1
        state = transition(state, event: .faderReading(deck: 1, position: 0.9))
        XCTAssertEqual(state.master, 2)
        
        // 7. DJ stops deck 1 (unchanged stableThreshold times)
        for _ in 0..<config.stableThreshold {
            state = transition(state, event: .elapsedReading(deck: 1, elapsed: 30.0), config: config)
        }
        XCTAssertEqual(state.deck1.playState, .stopped)
        XCTAssertEqual(state.master, 2)  // Only deck 2 playing
    }
    
    // MARK: - DeckStateManager Tests
    
    @MainActor
    func testDeckStateManagerIntegration() async {
        let manager = DeckStateManager()
        
        // Create mock detection result
        var deck1 = DeckDetection()
        deck1.artist = "Artist 1"
        deck1.title = "Track 1"
        deck1.elapsedSeconds = 90.0  // 1:30
        deck1.faderKnobPos = 0.2
        deck1.faderConfidence = 0.9
        
        var deck2 = DeckDetection()
        deck2.artist = "Artist 2"
        deck2.title = "Track 2"
        deck2.elapsedSeconds = 45.0  // 0:45
        deck2.faderKnobPos = 0.8
        deck2.faderConfidence = 0.9
        
        let detection = DetectionResult(deck1: deck1, deck2: deck2, masterDeck: nil)
        
        // Process detection
        manager.process(detection)
        
        // Both should be playing
        XCTAssertEqual(manager.deck1PlayState, .playing)
        XCTAssertEqual(manager.deck2PlayState, .playing)
        
        // Deck 1 has higher fader → master
        XCTAssertEqual(manager.master, 1)
    }
}

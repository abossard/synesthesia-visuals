import Foundation

// MARK: - State Types

enum DeckPlayState: Equatable, CustomStringConvertible {
    case playing
    case stopped
    case unknown  // Can't determine (elapsed undefined)
    
    var description: String {
        switch self {
        case .playing: return "▶️ Playing"
        case .stopped: return "⏹ Stopped"
        case .unknown: return "❓ Unknown"
        }
    }
}

struct DeckState: Equatable {
    let playState: DeckPlayState
    let lastElapsed: Double?      // Last known elapsed time
    let faderPosition: Double?    // 0 = top (loud), 1 = bottom (quiet)
    let stableCount: Int          // How many consecutive same-elapsed readings
    
    static let initial = DeckState(playState: .unknown, lastElapsed: nil, faderPosition: nil, stableCount: 0)
    
    /// Fader as percentage (0-100, where 100 = fully up)
    var faderPercent: Int? {
        guard let pos = faderPosition else { return nil }
        return Int((1.0 - pos) * 100)
    }
}

struct MasterState: Equatable {
    let deck1: DeckState
    let deck2: DeckState
    let master: Int?  // 1, 2, or nil
    
    static let initial = MasterState(deck1: .initial, deck2: .initial, master: nil)
}

// MARK: - Events

enum DeckEvent: Equatable {
    case elapsedReading(deck: Int, elapsed: Double?)
    case faderReading(deck: Int, position: Double?)
}

// MARK: - Configuration

struct FSMConfig {
    /// Threshold for considering elapsed time "unchanged" (seconds)
    let elapsedEpsilon: Double
    /// Readings before considered stopped
    let stableThreshold: Int
    /// Fader difference threshold for "equal" faders
    let faderEqualThreshold: Double
    
    static let `default` = FSMConfig(
        elapsedEpsilon: 0.5,
        stableThreshold: 3,
        faderEqualThreshold: 0.02
    )
}

// MARK: - Pure Transition Functions

/// Update a single deck's play state based on new elapsed reading
func transitionDeck(_ state: DeckState, elapsed: Double?, config: FSMConfig = .default) -> DeckState {
    guard let newElapsed = elapsed else {
        // Undefined reading → state unchanged
        return state
    }
    
    guard let lastElapsed = state.lastElapsed else {
        // First reading → assume playing (we have data now)
        return DeckState(
            playState: .playing,
            lastElapsed: newElapsed,
            faderPosition: state.faderPosition,
            stableCount: 0
        )
    }
    
    let delta = abs(newElapsed - lastElapsed)
    
    if delta > config.elapsedEpsilon {
        // Time changed → playing
        return DeckState(
            playState: .playing,
            lastElapsed: newElapsed,
            faderPosition: state.faderPosition,
            stableCount: 0
        )
    } else {
        // Time unchanged → increment stable count
        let newCount = state.stableCount + 1
        let newPlayState: DeckPlayState = newCount >= config.stableThreshold ? .stopped : state.playState
        return DeckState(
            playState: newPlayState,
            lastElapsed: newElapsed,
            faderPosition: state.faderPosition,
            stableCount: newCount
        )
    }
}

/// Update deck's fader position
func transitionDeckFader(_ state: DeckState, position: Double?) -> DeckState {
    DeckState(
        playState: state.playState,
        lastElapsed: state.lastElapsed,
        faderPosition: position ?? state.faderPosition,
        stableCount: state.stableCount
    )
}

/// Determine master based on play states and fader positions
func determineMaster(deck1: DeckState, deck2: DeckState, currentMaster: Int?, config: FSMConfig = .default) -> Int? {
    let d1Playing = deck1.playState == .playing
    let d2Playing = deck2.playState == .playing
    
    // Rule 1: Only one deck playing → that's master
    if d1Playing && !d2Playing { return 1 }
    if d2Playing && !d1Playing { return 2 }
    
    // Rule 2: Both playing → higher fader wins
    if d1Playing && d2Playing {
        if let f1 = deck1.faderPosition, let f2 = deck2.faderPosition {
            let diff = f1 - f2
            
            // If faders within threshold, check if one caught up to become master
            if abs(diff) < config.faderEqualThreshold {
                // Faders equal → keep current master
                return currentMaster
            }
            
            // Lower Y = higher fader = master
            return f1 < f2 ? 1 : 2
        }
        // Can't determine faders → keep current
        return currentMaster
    }
    
    // Both stopped → no master
    if deck1.playState == .stopped && deck2.playState == .stopped {
        return nil
    }
    
    // Unknown states → keep current
    return currentMaster
}

/// Main FSM transition: (State, Event) -> State
func transition(_ state: MasterState, event: DeckEvent, config: FSMConfig = .default) -> MasterState {
    var deck1 = state.deck1
    var deck2 = state.deck2
    
    switch event {
    case .elapsedReading(let deck, let elapsed):
        if deck == 1 {
            deck1 = transitionDeck(deck1, elapsed: elapsed, config: config)
        } else {
            deck2 = transitionDeck(deck2, elapsed: elapsed, config: config)
        }
        
    case .faderReading(let deck, let position):
        if deck == 1 {
            deck1 = transitionDeckFader(deck1, position: position)
        } else {
            deck2 = transitionDeckFader(deck2, position: position)
        }
    }
    
    let newMaster = determineMaster(deck1: deck1, deck2: deck2, currentMaster: state.master, config: config)
    
    return MasterState(deck1: deck1, deck2: deck2, master: newMaster)
}

// MARK: - Convenience: Batch update from detection result

func transitionFromDetection(_ state: MasterState, detection: DetectionResult, config: FSMConfig = .default) -> MasterState {
    // Feed all events from a single detection
    let events: [DeckEvent] = [
        .elapsedReading(deck: 1, elapsed: detection.deck1.elapsedSeconds),
        .elapsedReading(deck: 2, elapsed: detection.deck2.elapsedSeconds),
        .faderReading(deck: 1, position: detection.deck1.faderKnobPos),
        .faderReading(deck: 2, position: detection.deck2.faderKnobPos),
    ]
    
    return events.reduce(state) { transition($0, event: $1, config: config) }
}

// MARK: - Formatting Helpers

extension DeckState {
    /// Format elapsed time as MM:SS
    var elapsedFormatted: String {
        guard let secs = lastElapsed else { return "--:--" }
        let mins = Int(secs) / 60
        let s = Int(secs) % 60
        return String(format: "%d:%02d", mins, s)
    }
}

// MARK: - Stateful Wrapper (for AppState integration)

@MainActor
final class DeckStateManager: ObservableObject {
    @Published private(set) var state: MasterState = .initial
    
    let config: FSMConfig
    
    init(config: FSMConfig = .default) {
        self.config = config
    }
    
    /// Process a detection result and update state
    func process(_ detection: DetectionResult) {
        state = transitionFromDetection(state, detection: detection, config: config)
    }
    
    /// Reset to initial state
    func reset() {
        state = .initial
    }
    
    // Convenience accessors
    var master: Int? { state.master }
    var deck1PlayState: DeckPlayState { state.deck1.playState }
    var deck2PlayState: DeckPlayState { state.deck2.playState }
}

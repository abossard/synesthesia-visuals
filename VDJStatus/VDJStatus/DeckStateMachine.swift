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
    /// Poll interval in seconds (only affects how often we sample)
    let pollInterval: TimeInterval
    
    /// Readings with unchanged elapsed before deck is considered stopped
    let stableThreshold: Int
    
    /// Tolerance for OCR jitter when comparing elapsed times (fixed, not related to poll rate)
    let elapsedEpsilon: Double
    
    /// Fader difference threshold for "equal" faders
    let faderEqualThreshold: Double
    
    /// Default config
    static let `default` = FSMConfig(
        pollInterval: 1.0,
        stableThreshold: 3,        // 3 unchanged readings → stopped
        elapsedEpsilon: 0.1,       // 100ms tolerance for OCR jitter
        faderEqualThreshold: 0.02  // 2% fader difference threshold
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
    
    // Simple: if elapsed went up (beyond jitter tolerance), it's playing
    let isProgressing = newElapsed > lastElapsed + config.elapsedEpsilon
    
    if isProgressing {
        return DeckState(
            playState: .playing,
            lastElapsed: newElapsed,
            faderPosition: state.faderPosition,
            stableCount: 0
        )
    } else {
        // Time not progressing → increment stable count
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
    
    // Only one playing → that's master
    if d1Playing && !d2Playing { return 1 }
    if d2Playing && !d1Playing { return 2 }
    
    // Both playing → higher fader wins (lower position value = higher fader)
    if d1Playing && d2Playing {
        guard let f1 = deck1.faderPosition, let f2 = deck2.faderPosition else {
            return currentMaster  // No fader data → keep current
        }
        if abs(f1 - f2) < config.faderEqualThreshold {
            return currentMaster  // Faders equal → keep current
        }
        return f1 < f2 ? 1 : 2
    }
    
    // Neither playing → no master
    return nil
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

/// Result of a batch transition with change detection
struct TransitionResult {
    let newState: MasterState
    let changes: [String]  // Human-readable change descriptions
}

func transitionFromDetection(_ state: MasterState, detection: DetectionResult, config: FSMConfig = .default) -> MasterState {
    let result = transitionFromDetectionWithLog(state, detection: detection, config: config)
    return result.newState
}

/// Batch transition with logging of changes
func transitionFromDetectionWithLog(_ state: MasterState, detection: DetectionResult, config: FSMConfig = .default) -> TransitionResult {
    let events: [DeckEvent] = [
        .elapsedReading(deck: 1, elapsed: detection.deck1.elapsedSeconds),
        .elapsedReading(deck: 2, elapsed: detection.deck2.elapsedSeconds),
        .faderReading(deck: 1, position: detection.deck1.faderKnobPos),
        .faderReading(deck: 2, position: detection.deck2.faderKnobPos),
    ]
    
    let newState = events.reduce(state) { transition($0, event: $1, config: config) }
    var changes: [String] = []
    
    // Detect play state changes
    if state.deck1.playState != newState.deck1.playState {
        changes.append("D1: \(state.deck1.playState) → \(newState.deck1.playState)")
    }
    if state.deck2.playState != newState.deck2.playState {
        changes.append("D2: \(state.deck2.playState) → \(newState.deck2.playState)")
    }
    
    // Detect master changes
    if state.master != newState.master {
        let oldMaster = state.master.map { "D\($0)" } ?? "None"
        let newMasterStr = newState.master.map { "D\($0)" } ?? "None"
        changes.append("Master: \(oldMaster) → \(newMasterStr)")
    }
    
    return TransitionResult(newState: newState, changes: changes)
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

// MARK: - Transition Log Entry

struct FSMLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

// MARK: - Stateful Wrapper (for AppState integration)

@MainActor
final class DeckStateManager: ObservableObject {
    @Published private(set) var state: MasterState = .initial
    @Published private(set) var transitionLog: [FSMLogEntry] = []
    
    let config: FSMConfig
    private let maxLogEntries = 50
    private let dateFormatter: DateFormatter
    
    init(config: FSMConfig = .default) {
        self.config = config
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }
    
    private func timestamp() -> String {
        dateFormatter.string(from: Date())
    }
    
    private func formatElapsed(_ elapsed: Double?) -> String {
        guard let e = elapsed else { return "nil" }
        return String(format: "%.1f", e)
    }
    
    /// Process a detection result and update state, logging changes
    func process(_ detection: DetectionResult) {
        let oldState = state
        let result = transitionFromDetectionWithLog(state, detection: detection, config: config)
        state = result.newState
        
        // Debug: always log elapsed readings with timestamps
        let e1 = formatElapsed(detection.deck1.elapsedSeconds)
        let e2 = formatElapsed(detection.deck2.elapsedSeconds)
        let oldE1 = formatElapsed(oldState.deck1.lastElapsed)
        let oldE2 = formatElapsed(oldState.deck2.lastElapsed)
        
        // Calculate deltas
        let delta1: String
        if let new = detection.deck1.elapsedSeconds, let old = oldState.deck1.lastElapsed {
            delta1 = String(format: "Δ%.1f", abs(new - old))
        } else {
            delta1 = "Δ?"
        }
        
        let delta2: String
        if let new = detection.deck2.elapsedSeconds, let old = oldState.deck2.lastElapsed {
            delta2 = String(format: "Δ%.1f", abs(new - old))
        } else {
            delta2 = "Δ?"
        }
        
        print("[\(timestamp())] D1: \(oldE1)→\(e1) (\(delta1)) stable:\(state.deck1.stableCount)/\(config.stableThreshold) | D2: \(oldE2)→\(e2) (\(delta2)) stable:\(state.deck2.stableCount)/\(config.stableThreshold)")
        
        // Log state changes to console and history
        for change in result.changes {
            print("[\(timestamp())] [FSM] \(change)")
            transitionLog.insert(FSMLogEntry(timestamp: Date(), message: change), at: 0)
        }
        
        // Trim log
        if transitionLog.count > maxLogEntries {
            transitionLog = Array(transitionLog.prefix(maxLogEntries))
        }
    }
    
    /// Reset to initial state
    func reset() {
        state = .initial
        transitionLog.removeAll()
        print("[FSM] Reset to initial state")
    }
    
    // Convenience accessors
    var master: Int? { state.master }
    var deck1PlayState: DeckPlayState { state.deck1.playState }
    var deck2PlayState: DeckPlayState { state.deck2.playState }
}

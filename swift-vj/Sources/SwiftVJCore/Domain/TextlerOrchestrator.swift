// TextlerOrchestrator - Wires modules for realtime lyrics sync
// Following A Philosophy of Software Design: coordinator pattern

import Foundation
import OSCKit

/// Orchestrates realtime lyrics sync with OSC output
///
/// Wires together:
/// - Playback position updates → Active line tracking → OSC output
///
/// This matches Python's TextlerEngine behavior for position-driven OSC:
/// - /textler/line/active [index]
/// - /textler/refrain/active [index, text]
/// - /textler/keywords/active [index, keywords]
///
/// Usage:
/// ```swift
/// let orchestrator = TextlerOrchestrator(oscSender: oscHub)
/// try await orchestrator.start()
///
/// // When pipeline loads lyrics:
/// orchestrator.setLines(lyrics.lines)
///
/// // Wire to playback position updates:
/// playbackModule.onPositionUpdate { position, isPlaying in
///     orchestrator.handlePositionUpdate(position: position, isPlaying: isPlaying)
/// }
/// ```
public class TextlerOrchestrator {
    
    // MARK: - State
    
    private var _isStarted = false
    private let activeLineTracker: ActiveLineTracker
    
    // MARK: - Init
    
    public init(oscSender: OSCSending) {
        self.activeLineTracker = ActiveLineTracker(sender: oscSender)
    }
    
    /// Convenience init with OSCHub
    public convenience init(oscHub: OSCHub) {
        self.init(oscSender: oscHub)
    }
    
    // MARK: - Lifecycle
    
    public var isStarted: Bool { _isStarted }
    
    public func start() async throws {
        guard !_isStarted else { return }
        _isStarted = true
        print("[Textler] Started")
    }
    
    public func stop() async {
        _isStarted = false
        activeLineTracker.reset()
        print("[Textler] Stopped")
    }
    
    // MARK: - Public API
    
    /// Set lyrics lines (call when pipeline loads lyrics)
    public func setLines(_ lines: [LyricLine]) {
        activeLineTracker.setLines(lines)
    }
    
    /// Handle playback position update
    /// Call this from PlaybackModule.onPositionUpdate callback
    public func handlePositionUpdate(position: Double, isPlaying: Bool) {
        guard _isStarted && isPlaying else { return }
        activeLineTracker.updatePosition(position)
    }
    
    /// Handle track change (reset active line state)
    public func handleTrackChange() {
        activeLineTracker.reset()
    }
    
    /// Current active line index
    public var activeLineIndex: Int {
        activeLineTracker.activeIndex
    }
}

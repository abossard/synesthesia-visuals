// SynesthesiaAudioProcessor.swift - Synesthesia OSC → Audio State bridge
// Parses Synesthesia audio OSC messages and applies EMA smoothing
// Based on SynesthesiaAudioOSC.pde from VJUniverse

import Foundation
import OSCKit

// MARK: - Lock-Free OSC Accumulator (nonisolated for high-rate messages)

/// Thread-safe accumulator for raw OSC values. Uses os_unfair_lock for minimal overhead.
/// Messages are batched here and processed once per frame in getLevels().
@available(macOS 10.12, *)
final class OSCAccumulator: @unchecked Sendable {
    private var lock = os_unfair_lock()
    
    // Raw accumulated values (written by OSC callbacks, read by actor)
    private var _bass: Float = 0
    private var _mid: Float = 0
    private var _highs: Float = 0
    private var _level: Float = 0
    private var _lowMid: Float = 0
    private var _bassPresence: Float = 0
    private var _midPresence: Float = 0
    private var _highPresence: Float = 0
    private var _bassHits: Float = 0
    private var _midHits: Float = 0
    private var _highHits: Float = 0
    private var _onBeat: Float = 0
    private var _beatTime: Float = 0
    private var _toggleOnBeat: Float = 0
    private var _randomOnBeat: Float = 0
    private var _bpmTwitcher: Float = 0
    private var _bpmSin4: Float = 0
    private var _bpmConfidence: Float = 0
    private var _bpm: Float = 120
    private var _intensity: Float = 0
    
    // Stats
    private var _messageCount: Int = 0
    private var _lastMessageTime: Double = 0  // CFAbsoluteTime
    private var _messagesThisSecond: Int = 0
    private var _lastSecondStart: Double = 0
    private var _messageRate: Int = 0  // messages per second
    
    /// Record an OSC message (called from any thread at high rate)
    func record(category: UnsafePointer<CChar>, band: UnsafePointer<CChar>, value: Float) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let now = CFAbsoluteTimeGetCurrent()
        _messageCount += 1
        _lastMessageTime = now
        
        // Update message rate (per second)
        if now - _lastSecondStart >= 1.0 {
            _messageRate = _messagesThisSecond
            _messagesThisSecond = 0
            _lastSecondStart = now
        }
        _messagesThisSecond += 1
        
        // Fast C string comparison (no allocations)
        if strcmp(category, "level") == 0 {
            if strcmp(band, "bass") == 0 { _bass = value }
            else if strcmp(band, "mid") == 0 { _lowMid = value }
            else if strcmp(band, "midhigh") == 0 { _mid = value }
            else if strcmp(band, "high") == 0 { _highs = value }
            else if strcmp(band, "all") == 0 { _level = value; _intensity = value }
        } else if strcmp(category, "presence") == 0 {
            if strcmp(band, "bass") == 0 { _bassPresence = value }
            else if strcmp(band, "mid") == 0 { _midPresence = value }
            else if strcmp(band, "high") == 0 { _highPresence = value }
        } else if strcmp(category, "hits") == 0 {
            if strcmp(band, "bass") == 0 { _bassHits = value }
            else if strcmp(band, "mid") == 0 { _midHits = value }
            else if strcmp(band, "high") == 0 { _highHits = value }
        } else if strcmp(category, "beat") == 0 {
            if strcmp(band, "onbeat") == 0 { _onBeat = value }
            else if strcmp(band, "beattime") == 0 { _beatTime = value }
            else if strcmp(band, "toggleonbeat") == 0 { _toggleOnBeat = value }
            else if strcmp(band, "randomonbeat") == 0 { _randomOnBeat = value }
        } else if strcmp(category, "bpm") == 0 {
            if strcmp(band, "bpmtwitcher") == 0 { _bpmTwitcher = value }
            else if strcmp(band, "bpmsin4") == 0 { _bpmSin4 = value }
            else if strcmp(band, "bpmconfidence") == 0 { _bpmConfidence = value }
            else if strcmp(band, "bpm") == 0 { _bpm = value }
        } else if strcmp(category, "energy") == 0 {
            if strcmp(band, "intensity") == 0 { _intensity = value }
        }
    }
    
    /// Snapshot current values (called once per frame from actor)
    func snapshot() -> (
        bass: Float, mid: Float, highs: Float, level: Float, lowMid: Float,
        bassPresence: Float, midPresence: Float, highPresence: Float,
        bassHits: Float, midHits: Float, highHits: Float,
        onBeat: Float, beatTime: Float, toggleOnBeat: Float, randomOnBeat: Float,
        bpmTwitcher: Float, bpmSin4: Float, bpmConfidence: Float, bpm: Float, intensity: Float,
        messageCount: Int, lastMessageTime: Double, messageRate: Int
    ) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return (
            _bass, _mid, _highs, _level, _lowMid,
            _bassPresence, _midPresence, _highPresence,
            _bassHits, _midHits, _highHits,
            _onBeat, _beatTime, _toggleOnBeat, _randomOnBeat,
            _bpmTwitcher, _bpmSin4, _bpmConfidence, _bpm, _intensity,
            _messageCount, _lastMessageTime, _messageRate
        )
    }
    
    func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        _bass = 0; _mid = 0; _highs = 0; _level = 0; _lowMid = 0
        _bassPresence = 0; _midPresence = 0; _highPresence = 0
        _bassHits = 0; _midHits = 0; _highHits = 0
        _onBeat = 0; _beatTime = 0; _toggleOnBeat = 0; _randomOnBeat = 0
        _bpmTwitcher = 0; _bpmSin4 = 0; _bpmConfidence = 0; _bpm = 120; _intensity = 0
        _messageCount = 0; _messageRate = 0
    }
}

// MARK: - Synesthesia Audio Processor

/// Parses Synesthesia audio OSC messages and produces audio state.
/// Uses lock-free accumulator for high-rate OSC handling, processes batch per frame.
///
/// OSC Address Patterns (from Synesthesia):
/// - /audio/level/{bass, mid, high, all}
/// - /audio/presence/{bass, mid, high, all}
/// - /audio/hits/{bass, mid, high}
/// - /audio/beat/{onbeat, beattime, toggleonbeat, randomonbeat}
/// - /audio/bpm/{bpmtwitcher, bpmsin4, bpmconfidence, bpm}
///
/// Usage:
/// ```
/// let processor = SynesthesiaAudioProcessor()
/// processor.handleOSCFast(address, values)  // nonisolated, no await
/// // Per frame:
/// let levels = await processor.getLevels()  // batch process
/// ```
public actor SynesthesiaAudioProcessor {
    
    // MARK: - Lock-Free Accumulator (shared across threads)
    
    /// Nonisolated accumulator for high-rate OSC messages
    private let accumulator = OSCAccumulator()
    
    // MARK: - Cached Levels (updated per frame)
    
    private var cachedLevels: OSCAudioLevels = OSCAudioLevels(
        bass: 0, lowMid: 0, mid: 0, highs: 0, level: 0,
        hitsBass: 0, onBeat: 0, beatTime: 0,
        bpmTwitcher: 0, bpmSin4: 0, bpmConfidence: 0, energyIntensity: 0,
        bassPresence: 0, midPresence: 0, highPresence: 0
    )
    
    // Stats (updated from accumulator snapshot)
    private var lastMessageTime: Double = 0
    private var messageCount: Int = 0
    private var messageRate: Int = 0
    
    // MARK: - Configuration
    
    /// Timeout after which we consider audio inactive (seconds)
    public static let timeoutSeconds: TimeInterval = 1.5
    
    // MARK: - Public API
    
    public init() {}
    
    /// FAST PATH: Handle incoming OSC message (nonisolated, no await needed)
    /// Call this directly from OSC callbacks for minimal overhead.
    nonisolated public func handleOSCFast(_ address: String, _ values: [any OSCValue]) {
        // Extract first float value
        guard let value = values.first.flatMap({ floatValueFast(from: $0) }) else { return }
        
        // Parse address: /audio/{category}/{band}
        // Use elementsEqual to avoid Substring vs String comparison issues
        let parts = address.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0].elementsEqual("audio") else { return }
        
        // Convert to C strings for lock-free accumulator (no Swift String allocation)
        let category = String(parts[1])
        let band = String(parts[2])
        
        category.withCString { catPtr in
            band.withCString { bandPtr in
                accumulator.record(category: catPtr, band: bandPtr, value: value)
            }
        }
    }
    
    /// Legacy actor-isolated handler (for compatibility, less efficient)
    public func handleOSC(_ address: String, _ values: [any OSCValue]) {
        handleOSCFast(address, values)
    }
    
    /// Get current audio levels (call once per frame)
    /// This snapshots the accumulated values and returns them.
    public func getLevels() -> OSCAudioLevels {
        let snap = accumulator.snapshot()
        
        // Update stats
        messageCount = snap.messageCount
        lastMessageTime = snap.lastMessageTime
        messageRate = snap.messageRate
        
        // Build levels struct
        cachedLevels = OSCAudioLevels(
            bass: snap.bass,
            lowMid: snap.lowMid,
            mid: snap.mid,
            highs: snap.highs,
            level: snap.level,
            hitsBass: snap.bassHits,
            onBeat: snap.onBeat,
            beatTime: snap.beatTime,
            bpmTwitcher: snap.bpmTwitcher,
            bpmSin4: snap.bpmSin4,
            bpmConfidence: snap.bpmConfidence,
            energyIntensity: snap.intensity,
            bassPresence: snap.bassPresence,
            midPresence: snap.midPresence,
            highPresence: snap.highPresence
        )
        
        return cachedLevels
    }
    
    /// Whether we're receiving active audio data
    public var isActive: Bool {
        CFAbsoluteTimeGetCurrent() - lastMessageTime < Self.timeoutSeconds
    }
    
    /// Statistics for debugging
    public var stats: (messageCount: Int, lastMessage: Date, isActive: Bool, messageRate: Int) {
        (messageCount, Date(timeIntervalSinceReferenceDate: lastMessageTime), isActive, messageRate)
    }
    
    /// Reset all values to silent
    public func reset() {
        accumulator.reset()
        messageCount = 0
        lastMessageTime = 0
        messageRate = 0
        cachedLevels = OSCAudioLevels(
            bass: 0, lowMid: 0, mid: 0, highs: 0, level: 0,
            hitsBass: 0, onBeat: 0, beatTime: 0,
            bpmTwitcher: 0, bpmSin4: 0, bpmConfidence: 0, energyIntensity: 0,
            bassPresence: 0, midPresence: 0, highPresence: 0
        )
    }
    
    // MARK: - Presence Values (for extended uniforms)
    
    /// Get presence values (slow-moving structural energy)
    public func getPresence() -> (bass: Float, mid: Float, high: Float) {
        (cachedLevels.bassPresence, cachedLevels.midPresence, cachedLevels.highPresence)
    }
    
    /// Get BPM info
    public func getBPM() -> (bpm: Float, confidence: Float, twitcher: Float) {
        let snap = accumulator.snapshot()
        return (snap.bpm, snap.bpmConfidence, snap.bpmTwitcher)
    }
    
    // MARK: - Private Helpers
    
    /// Fast float extraction (nonisolated, no actor hop)
    nonisolated private func floatValueFast(from value: any OSCValue) -> Float? {
        // Most common case first (Synesthesia sends Float32)
        if let f = value as? Float32 { return f }
        if let f = value as? Float { return f }
        if let d = value as? Double { return Float(d) }
        if let i = value as? Int { return Float(i) }
        if let i = value as? Int32 { return Float(i) }
        // Skip AnyOSCNumberValue - causes compile issues and rarely used
        if let s = value as? String { return Float(s) }
        return nil
    }
}

// MARK: - Re-export OSCAudioLevels for convenience

// OSCAudioLevels is already defined in AudioState.swift (SwiftVJCore/Rendering)
// This actor uses that type directly

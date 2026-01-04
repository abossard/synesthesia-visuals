// SynesthesiaAudioProcessor.swift - Synesthesia OSC → Audio State bridge
// Parses Synesthesia audio OSC messages and applies EMA smoothing
// Based on SynesthesiaAudioOSC.pde from VJUniverse

import Foundation
import OSCKit

// MARK: - Synesthesia Audio Processor

/// Parses Synesthesia audio OSC messages and produces smoothed audio state.
/// Thread-safe actor that accumulates raw values and applies per-frame smoothing.
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
/// oscHub.subscribe(pattern: "/audio/*") { address, values in
///     await processor.handleOSC(address, values)
/// }
/// // Per frame:
/// let rawLevels = await processor.getRawLevels()
/// ```
public actor SynesthesiaAudioProcessor {
    
    // MARK: - Raw OSC Values (accumulator)
    
    // Levels (0.0 - 1.0)
    private var rawBass: Float = 0
    private var rawMid: Float = 0
    private var rawHighs: Float = 0
    private var rawLevel: Float = 0
    
    // Low-mid (interpolated from bass/mid)
    private var rawLowMid: Float = 0
    
    // Presence (slow-moving structural energy)
    private var rawBassPresence: Float = 0
    private var rawMidPresence: Float = 0
    private var rawHighPresence: Float = 0
    
    // Hits (transients)
    private var rawBassHits: Float = 0
    private var rawMidHits: Float = 0
    private var rawHighHits: Float = 0
    
    // Beat detection
    private var rawOnBeat: Float = 0
    private var rawBeatTime: Float = 0
    private var rawToggleOnBeat: Float = 0
    private var rawRandomOnBeat: Float = 0
    
    // BPM LFOs
    private var rawBpmTwitcher: Float = 0
    private var rawBpmSin4: Float = 0
    private var rawBpmConfidence: Float = 0
    private var rawBpm: Float = 120
    
    // Intensity (overall energy)
    private var rawIntensity: Float = 0
    
    // Tracking
    private var lastMessageTime: Date = .distantPast
    private var messageCount: Int = 0
    
    // MARK: - Configuration
    
    /// Timeout after which we consider audio inactive (seconds)
    public static let timeoutSeconds: TimeInterval = 1.5
    
    // MARK: - Public API
    
    public init() {}
    
    /// Handle incoming Synesthesia OSC message
    public func handleOSC(_ address: String, _ values: [any OSCValue]) {
        lastMessageTime = Date()
        messageCount += 1
        
        // Extract first float value
        guard let value = values.first.flatMap({ floatValue(from: $0) }) else { return }
        
        // Parse address and store value
        // Pattern: /audio/{category}/{band}
        let parts = address.lowercased().split(separator: "/")
        guard parts.count >= 3, parts[0] == "audio" else { return }
        
        let category = String(parts[1])
        let band = String(parts[2])
        
        switch category {
        case "level":
            // VJUniverse.pde mapping:
            // /audio/level/bass -> smoothAudioBass
            // /audio/level/mid -> smoothAudioLowMid (low-mid frequency)
            // /audio/level/midhigh -> smoothAudioMid (mid frequency)
            // /audio/level/high -> smoothAudioHighs
            // /audio/level/all -> smoothAudioLevel
            switch band {
            case "bass": rawBass = value
            case "mid": rawLowMid = value  // Note: 'mid' OSC = lowMid in VJUniverse
            case "midhigh": rawMid = value  // Note: 'midhigh' OSC = mid in VJUniverse
            case "high": rawHighs = value
            case "all": rawLevel = value
            default: break
            }
            // Compute intensity from overall level
            rawIntensity = rawLevel
            
        case "presence":
            switch band {
            case "bass": rawBassPresence = value
            case "mid": rawMidPresence = value
            case "high": rawHighPresence = value
            case "all": break // Not used directly
            default: break
            }
            
        case "hits":
            switch band {
            case "bass": rawBassHits = value
            case "mid": rawMidHits = value
            case "high": rawHighHits = value
            default: break
            }
            
        case "beat":
            switch band {
            case "onbeat": rawOnBeat = value
            case "beattime": rawBeatTime = value
            case "toggleonbeat": rawToggleOnBeat = value
            case "randomonbeat": rawRandomOnBeat = value
            default: break
            }
            
        case "bpm":
            switch band {
            case "bpmtwitcher": rawBpmTwitcher = value
            case "bpmsin4": rawBpmSin4 = value
            case "bpmconfidence": rawBpmConfidence = value
            case "bpm": rawBpm = value
            default: break
            }
            
        case "energy":
            // /audio/energy/intensity - use as rawIntensity
            if band == "intensity" {
                rawIntensity = value
            }
            
        default:
            break
        }
    }
    
    /// Get current raw levels for processing
    /// Call this once per frame, then pass to AudioProcessor for smoothing
    public func getRawLevels() -> RawAudioLevels {
        RawAudioLevels(
            bass: rawBass,
            lowMid: rawLowMid,
            mid: rawMid,
            highs: rawHighs,
            level: rawLevel,
            hitsBass: rawBassHits,
            onBeat: rawOnBeat,
            beatTime: rawBeatTime,
            bpmTwitcher: rawBpmTwitcher,
            bpmSin4: rawBpmSin4,
            bpmConfidence: rawBpmConfidence,
            energyIntensity: rawIntensity,
            bassPresence: rawBassPresence,
            midPresence: rawMidPresence,
            highPresence: rawHighPresence
        )
    }
    
    /// Whether we're receiving active audio data
    public var isActive: Bool {
        Date().timeIntervalSince(lastMessageTime) < Self.timeoutSeconds
    }
    
    /// Statistics for debugging
    public var stats: (messageCount: Int, lastMessage: Date, isActive: Bool) {
        (messageCount, lastMessageTime, isActive)
    }
    
    /// Reset all values to silent
    public func reset() {
        rawBass = 0
        rawMid = 0
        rawHighs = 0
        rawLevel = 0
        rawLowMid = 0
        rawBassPresence = 0
        rawMidPresence = 0
        rawHighPresence = 0
        rawBassHits = 0
        rawMidHits = 0
        rawHighHits = 0
        rawOnBeat = 0
        rawBeatTime = 0
        rawToggleOnBeat = 0
        rawRandomOnBeat = 0
        rawBpmTwitcher = 0
        rawBpmSin4 = 0
        rawBpmConfidence = 0
        rawBpm = 120
        rawIntensity = 0
        messageCount = 0
        lastMessageTime = .distantPast
    }
    
    // MARK: - Presence Values (for extended uniforms)
    
    /// Get presence values (slow-moving structural energy)
    public func getPresence() -> (bass: Float, mid: Float, high: Float) {
        (rawBassPresence, rawMidPresence, rawHighPresence)
    }
    
    /// Get BPM info
    public func getBPM() -> (bpm: Float, confidence: Float, twitcher: Float) {
        (rawBpm, rawBpmConfidence, rawBpmTwitcher)
    }
    
    // MARK: - Private Helpers
    
    private func floatValue(from value: any OSCValue) -> Float? {
        if let f = value as? Float { return f }
        if let f = value as? Float32 { return f }
        if let d = value as? Double { return Float(d) }
        if let i = value as? Int { return Float(i) }
        if let i = value as? Int32 { return Float(i) }
        if let s = value as? String { return Float(s) }
        return nil
    }
}

// MARK: - Re-export RawAudioLevels for convenience

// RawAudioLevels is already defined in AudioState.swift (SwiftVJCore/Rendering)
// This actor uses that type directly

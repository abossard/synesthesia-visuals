// SynesthesiaAudioProcessor.swift - Synesthesia OSC → Audio State bridge
// Parses Synesthesia audio OSC messages and applies EMA smoothing
// Based on SynesthesiaAudioOSC.pde from VJUniverse

import Foundation
import OSCKit

// MARK: - Synesthesia Audio Processor

/// Parses Synesthesia audio OSC messages and produces audio state.
/// Thread-safe actor that accumulates OSC values.
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
/// let levels = await processor.getLevels()
/// ```
public actor SynesthesiaAudioProcessor {
    
    // MARK: - OSC Values (accumulator)
    
    // Levels (0.0 - 1.0, normalized by Synesthesia)
    private var oscBass: Float = 0
    private var oscMid: Float = 0
    private var oscHighs: Float = 0
    private var oscLevel: Float = 0
    
    // Low-mid (interpolated from bass/mid)
    private var oscLowMid: Float = 0
    
    // Presence (slow-moving structural energy)
    private var oscBassPresence: Float = 0
    private var oscMidPresence: Float = 0
    private var oscHighPresence: Float = 0
    
    // Hits (transients)
    private var oscBassHits: Float = 0
    private var oscMidHits: Float = 0
    private var oscHighHits: Float = 0
    
    // Beat detection
    private var oscOnBeat: Float = 0
    private var oscBeatTime: Float = 0
    private var oscToggleOnBeat: Float = 0
    private var oscRandomOnBeat: Float = 0
    
    // BPM LFOs
    private var oscBpmTwitcher: Float = 0
    private var oscBpmSin4: Float = 0
    private var oscBpmConfidence: Float = 0
    private var oscBpm: Float = 120
    
    // Intensity (overall energy)
    private var oscIntensity: Float = 0
    
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
            case "bass": oscBass = value
            case "mid": oscLowMid = value  // Note: 'mid' OSC = lowMid in VJUniverse
            case "midhigh": oscMid = value  // Note: 'midhigh' OSC = mid in VJUniverse
            case "high": oscHighs = value
            case "all": oscLevel = value
            default: break
            }
            // Compute intensity from overall level
            oscIntensity = oscLevel
            
        case "presence":
            switch band {
            case "bass": oscBassPresence = value
            case "mid": oscMidPresence = value
            case "high": oscHighPresence = value
            case "all": break // Not used directly
            default: break
            }
            
        case "hits":
            switch band {
            case "bass": oscBassHits = value
            case "mid": oscMidHits = value
            case "high": oscHighHits = value
            default: break
            }
            
        case "beat":
            switch band {
            case "onbeat": oscOnBeat = value
            case "beattime": oscBeatTime = value
            case "toggleonbeat": oscToggleOnBeat = value
            case "randomonbeat": oscRandomOnBeat = value
            default: break
            }
            
        case "bpm":
            switch band {
            case "bpmtwitcher": oscBpmTwitcher = value
            case "bpmsin4": oscBpmSin4 = value
            case "bpmconfidence": oscBpmConfidence = value
            case "bpm": oscBpm = value
            default: break
            }
            
        case "energy":
            if band == "intensity" {
                oscIntensity = value
            }
            
        default:
            break
        }
    }
    
    /// Get current audio levels for processing
    public func getLevels() -> OSCAudioLevels {
        OSCAudioLevels(
            bass: oscBass,
            lowMid: oscLowMid,
            mid: oscMid,
            highs: oscHighs,
            level: oscLevel,
            hitsBass: oscBassHits,
            onBeat: oscOnBeat,
            beatTime: oscBeatTime,
            bpmTwitcher: oscBpmTwitcher,
            bpmSin4: oscBpmSin4,
            bpmConfidence: oscBpmConfidence,
            energyIntensity: oscIntensity,
            bassPresence: oscBassPresence,
            midPresence: oscMidPresence,
            highPresence: oscHighPresence
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
        oscBass = 0
        oscMid = 0
        oscHighs = 0
        oscLevel = 0
        oscLowMid = 0
        oscBassPresence = 0
        oscMidPresence = 0
        oscHighPresence = 0
        oscBassHits = 0
        oscMidHits = 0
        oscHighHits = 0
        oscOnBeat = 0
        oscBeatTime = 0
        oscToggleOnBeat = 0
        oscRandomOnBeat = 0
        oscBpmTwitcher = 0
        oscBpmSin4 = 0
        oscBpmConfidence = 0
        oscBpm = 120
        oscIntensity = 0
        messageCount = 0
        lastMessageTime = .distantPast
    }
    
    // MARK: - Presence Values (for extended uniforms)
    
    /// Get presence values (slow-moving structural energy)
    public func getPresence() -> (bass: Float, mid: Float, high: Float) {
        (oscBassPresence, oscMidPresence, oscHighPresence)
    }
    
    /// Get BPM info
    public func getBPM() -> (bpm: Float, confidence: Float, twitcher: Float) {
        (oscBpm, oscBpmConfidence, oscBpmTwitcher)
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

// MARK: - Re-export OSCAudioLevels for convenience

// OSCAudioLevels is already defined in AudioState.swift (SwiftVJCore/Rendering)
// This actor uses that type directly

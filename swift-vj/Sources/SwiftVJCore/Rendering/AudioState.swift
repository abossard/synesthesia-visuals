// Audio State - Immutable audio analysis snapshot
// Used by rendering tiles for audio-reactive visuals

import Foundation
import simd

// MARK: - Audio State

/// Immutable audio analysis state snapshot
/// Updated by AudioProcessor, consumed by rendering tiles
public struct AudioState: Sendable, Equatable {

    // MARK: - Band Levels (0.0 - 1.0)

    /// Low frequency energy (bass drum, bass guitar)
    public let bass: Float

    /// Low-mid frequency energy
    public let lowMid: Float

    /// Mid frequency energy (vocals, guitars)
    public let mid: Float

    /// High frequency energy (cymbals, hi-hats)
    public let highs: Float

    /// Overall loudness level
    public let level: Float

    // MARK: - Energy Envelopes

    /// Fast-responding energy envelope (for reactive effects)
    public let energyFast: Float

    /// Slow-responding energy envelope (for sustained effects)
    public let energySlow: Float

    // MARK: - Beat/Kick Detection

    /// Kick/bass hit envelope (0-1)
    public let kickEnv: Float

    /// True on kick hit frame (with cooldown)
    public let kickPulse: Bool

    /// Beat phase (1.0 on beat, decays to 0)
    public let beatPhase: Float

    // MARK: - Tempo Sync

    /// Beat counter (0-3, increments on beat)
    public let beat4: Int

    /// Sawtooth LFO synced to tempo
    public let bpmTwitcher: Float

    /// 4-beat sine wave LFO
    public let bpmSin4: Float

    /// Tempo detection confidence (0-1)
    public let bpmConfidence: Float

    // MARK: - Audio-Reactive Speed

    /// Audio-reactive time scaling (0.02 - 1.20)
    /// Near-standstill in silence, accelerates with energy
    public let speed: Float

    // MARK: - Timestamp

    /// When this state was captured
    public let timestamp: Date

    // MARK: - Computed Properties

    /// Whether audio is currently active (above noise floor)
    public var isActive: Bool {
        level > 0.01
    }

    /// Average of all band levels
    public var averageLevel: Float {
        (bass + lowMid + mid + highs) / 4.0
    }

    // MARK: - Initialization

    public init(
        bass: Float = 0,
        lowMid: Float = 0,
        mid: Float = 0,
        highs: Float = 0,
        level: Float = 0,
        energyFast: Float = 0,
        energySlow: Float = 0,
        kickEnv: Float = 0,
        kickPulse: Bool = false,
        beatPhase: Float = 0,
        beat4: Int = 0,
        bpmTwitcher: Float = 0,
        bpmSin4: Float = 0,
        bpmConfidence: Float = 0,
        speed: Float = 0.02,
        timestamp: Date = Date()
    ) {
        self.bass = bass
        self.lowMid = lowMid
        self.mid = mid
        self.highs = highs
        self.level = level
        self.energyFast = energyFast
        self.energySlow = energySlow
        self.kickEnv = kickEnv
        self.kickPulse = kickPulse
        self.beatPhase = beatPhase
        self.beat4 = beat4
        self.bpmTwitcher = bpmTwitcher
        self.bpmSin4 = bpmSin4
        self.bpmConfidence = bpmConfidence
        self.speed = speed
        self.timestamp = timestamp
    }

    /// Create silent state
    public static var silent: AudioState {
        AudioState()
    }
}

// MARK: - Raw Audio Levels (Input)

/// Raw audio levels before smoothing
public struct RawAudioLevels: Sendable {
    public let bass: Float
    public let lowMid: Float
    public let mid: Float
    public let highs: Float
    public let level: Float
    public let hitsBass: Float
    public let onBeat: Float
    public let beatTime: Float
    public let bpmTwitcher: Float
    public let bpmSin4: Float
    public let bpmConfidence: Float
    public let energyIntensity: Float

    public init(
        bass: Float = 0,
        lowMid: Float = 0,
        mid: Float = 0,
        highs: Float = 0,
        level: Float = 0,
        hitsBass: Float = 0,
        onBeat: Float = 0,
        beatTime: Float = 0,
        bpmTwitcher: Float = 0,
        bpmSin4: Float = 0,
        bpmConfidence: Float = 0,
        energyIntensity: Float = 0
    ) {
        self.bass = bass
        self.lowMid = lowMid
        self.mid = mid
        self.highs = highs
        self.level = level
        self.hitsBass = hitsBass
        self.onBeat = onBeat
        self.beatTime = beatTime
        self.bpmTwitcher = bpmTwitcher
        self.bpmSin4 = bpmSin4
        self.bpmConfidence = bpmConfidence
        self.energyIntensity = energyIntensity
    }
}

// MARK: - Audio Processing Constants

/// Constants for audio processing (from VJUniverse)
public enum AudioConstants {
    // Smoothing factors (0-1, higher = smoother)
    public static let audioSmoothing: Float = 0.80
    public static let energyFastSmoothing: Float = 0.60
    public static let energySlowSmoothing: Float = 0.92
    public static let kickEnvSmoothing: Float = 0.55
    public static let presenceSmoothing: Float = 0.92
    public static let bpmLFOSmoothing: Float = 0.85

    // Kick detection
    public static let kickPulseThreshold: Float = 0.65
    public static let kickCooldownMs: Int = 140
    public static let beatOnThreshold: Float = 0.75
    public static let beatPhaseDecay: Float = 0.87

    // Timeout (decay when no audio)
    public static let timeoutMs: Int = 1500
    public static let timeoutDecay: Float = 0.90

    // Speed ramping (Magic-style)
    public static let baseSpeedFloor: Float = 0.02
    public static let audioSpeedMax: Float = 1.20
    public static let speedRampUp: Float = 0.008
    public static let speedRampDown: Float = 0.025
    public static let bassBoostWeight: Float = 0.35
    public static let beatBoostAmount: Float = 0.15
    public static let beatBoostDecay: Float = 0.92
}

// MARK: - Pure Functions for Audio Processing

/// Linear interpolation. Pure function.
public func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    a + (b - a) * t
}

/// Clamp value to range. Pure function.
public func clamp(_ value: Float, _ min: Float, _ max: Float) -> Float {
    Swift.min(Swift.max(value, min), max)
}

/// Synthetic mouse rotation speed (matches VJUniverse synthMouseSpeed)
private let synthMouseSpeed: Float = 0.3

/// Calculate synthetic mouse position (Lissajous curve modulated by audio).
/// Pure function - matches Processing's calcSynthMousePosition exactly.
///
/// - Parameters:
///   - time: Audio-synced time accumulator
///   - energySlow: Slow energy envelope (0-1) - controls overall amplitude
///   - bass: Bass level (0-1) - widens horizontal motion
///   - mid: Mid presence (0-1) - affects vertical breathing
///   - beatPhase: Beat phase (0-1, decays after beat) - phase offset on beat
/// - Returns: Normalized position [x, y] centered at 0.5
public func calcSyntheticMouse(
    time: Float,
    energySlow: Float,
    bass: Float,
    mid: Float,
    beatPhase: Float
) -> SIMD2<Float> {
    // Base rotation with configurable speed (matches Processing)
    var t = time * synthMouseSpeed
    
    // Phase shift on beat for rhythmic variation
    let phaseOffset = beatPhase * 0.4
    t += phaseOffset
    
    // Figure-8 Lissajous curve: x = sin(t), y = sin(2t)
    let fig8X = sin(t)
    let fig8Y = sin(t * 2.0)
    
    // Audio-modulated amplitude (smooth, avoids jitter)
    let baseRadius: Float = 0.12 + energySlow * 0.18  // 0.12-0.30 range
    let radiusX = baseRadius + bass * 0.12            // Bass widens X
    let radiusY = baseRadius + mid * 0.08             // Mids affect Y
    
    // Final position (centered at 0.5, clamped to valid range)
    let x = clamp(0.5 + fig8X * radiusX, 0.05, 0.95)
    let y = clamp(0.5 + fig8Y * radiusY, 0.05, 0.95)
    
    return SIMD2<Float>(x, y)
}

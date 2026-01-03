// AudioProcessor.swift - Audio analysis and smoothing for VJ rendering
// Port of SynesthesiaAudioOSC.pde to Swift

import Foundation

/// Raw audio levels from external source (Synesthesia, VDJ, etc.)
struct RawAudioLevels: Sendable {
    let bass: Float
    let lowMid: Float
    let mid: Float
    let highs: Float
    let level: Float

    // Beat/kick detection
    let hitsBass: Float
    let onBeat: Float
    let beatTime: Float

    // Energy
    let intensity: Float

    // BPM LFOs
    let bpmTwitcher: Float
    let bpmSin4: Float
    let bpmConfidence: Float

    static let silent = RawAudioLevels(
        bass: 0, lowMid: 0, mid: 0, highs: 0, level: 0,
        hitsBass: 0, onBeat: 0, beatTime: 0,
        intensity: 0,
        bpmTwitcher: 0, bpmSin4: 0, bpmConfidence: 0
    )
}

/// Processes audio input and produces smoothed analysis state
/// Port of SynesthesiaAudioOSC.pde update logic
actor AudioProcessor {
    // MARK: - Smoothed State

    private var smoothBass: Float = 0
    private var smoothLowMid: Float = 0
    private var smoothMid: Float = 0
    private var smoothHighs: Float = 0
    private var smoothLevel: Float = 0

    private var energyFast: Float = 0
    private var energySlow: Float = 0

    private var kickEnv: Float = 0
    private var kickPulse: Bool = false
    private var beatPhase: Float = 0
    private var beat4: Int = 0

    private var bpmTwitcher: Float = 0
    private var bpmSin4: Float = 0
    private var bpmConfidence: Float = 0

    // Ramp state for Magic-style speed buildup
    private var rampedSpeed: Float = 0.02
    private var beatBoostAccum: Float = 0.0

    // Kick detection
    private var lastKickPulseTime: Date = .distantPast
    private var lastOnBeatValue: Float = 0

    // Timeout tracking
    private var lastMessageTime: Date = .distantPast

    // MARK: - Constants (from SynesthesiaAudioOSC.pde)

    private let audioSmoothing: Float = 0.80
    private let energyFastSmoothing: Float = 0.60
    private let energySlowSmoothing: Float = 0.92
    private let kickEnvSmoothing: Float = 0.55
    private let kickPulseThreshold: Float = 0.65
    private let kickCooldownSec: TimeInterval = 0.140
    private let beatPhaseDecay: Float = 0.87
    private let beatOnThreshold: Float = 0.75
    private let timeoutDecay: Float = 0.90
    private let bpmLfoSmoothing: Float = 0.85
    private let timeoutDurationSec: TimeInterval = 1.5

    // Speed ramp constants (Magic-style smooth -> scale -> ramp)
    private let baseSpeedFloor: Float = 0.02
    private let audioSpeedMax: Float = 1.20
    private let speedRampUp: Float = 0.008
    private let speedRampDown: Float = 0.025
    private let bassBoostWeight: Float = 0.35
    private let beatBoostAmount: Float = 0.15
    private let beatBoostDecay: Float = 0.92

    // MARK: - Public Interface

    /// Current audio state (computed from smoothed values)
    var currentState: AudioState {
        AudioState(
            bass: smoothBass,
            lowMid: smoothLowMid,
            mid: smoothMid,
            highs: smoothHighs,
            level: smoothLevel,
            energyFast: energyFast,
            energySlow: energySlow,
            kickEnv: kickEnv,
            kickPulse: kickPulse,
            beatPhase: beatPhase,
            beat4: beat4,
            bpmTwitcher: bpmTwitcher,
            bpmSin4: bpmSin4,
            bpmConfidence: bpmConfidence,
            speed: computeAudioReactiveSpeed(),
            timestamp: Date()
        )
    }

    /// Update from raw audio levels
    /// Call this when receiving audio data from OSC or other source
    func update(rawLevels: RawAudioLevels) -> AudioState {
        lastMessageTime = Date()

        // Apply exponential smoothing to band levels
        smoothBass = lerp(smoothBass, rawLevels.bass, 1 - audioSmoothing)
        smoothLowMid = lerp(smoothLowMid, rawLevels.lowMid, 1 - audioSmoothing)
        smoothMid = lerp(smoothMid, rawLevels.mid, 1 - audioSmoothing)
        smoothHighs = lerp(smoothHighs, rawLevels.highs, 1 - audioSmoothing)
        smoothLevel = lerp(smoothLevel, rawLevels.level, 1 - audioSmoothing)

        // Energy envelopes
        energyFast = lerp(energyFast, rawLevels.intensity, 1 - energyFastSmoothing)
        energySlow = lerp(energySlow, energyFast, 1 - energySlowSmoothing)

        // Kick detection with cooldown
        kickEnv = lerp(kickEnv, rawLevels.hitsBass, 1 - kickEnvSmoothing)
        kickPulse = false
        let now = Date()
        if rawLevels.hitsBass > kickPulseThreshold &&
           now.timeIntervalSince(lastKickPulseTime) > kickCooldownSec {
            kickPulse = true
            lastKickPulseTime = now
        }

        // Beat phase
        if rawLevels.onBeat >= beatOnThreshold && lastOnBeatValue < beatOnThreshold {
            beatPhase = 1.0
        } else {
            beatPhase *= beatPhaseDecay
        }
        lastOnBeatValue = rawLevels.onBeat

        // Beat counter
        let wrappedBeatTime = rawLevels.beatTime.truncatingRemainder(dividingBy: 4.0)
        let adjustedBeatTime = wrappedBeatTime < 0 ? wrappedBeatTime + 4.0 : wrappedBeatTime
        let beatCycle = Int(round(rawLevels.beatTime)).remainderReportingOverflow(dividingBy: 8).partialValue
        beat4 = abs(beatCycle % 4)

        // BPM LFOs
        bpmTwitcher = lerp(bpmTwitcher, rawLevels.bpmTwitcher, 1 - bpmLfoSmoothing)
        bpmSin4 = lerp(bpmSin4, rawLevels.bpmSin4, 1 - bpmLfoSmoothing)
        bpmConfidence = lerp(bpmConfidence, rawLevels.bpmConfidence, 1 - bpmLfoSmoothing)

        return currentState
    }

    /// Update with timeout decay (when no audio received)
    /// Call this periodically to decay values during silence
    func updateWithTimeoutDecay() -> AudioState {
        guard !isActive else { return currentState }

        // Apply timeout decay to all values
        smoothBass *= timeoutDecay
        smoothLowMid *= timeoutDecay
        smoothMid *= timeoutDecay
        smoothHighs *= timeoutDecay
        smoothLevel *= timeoutDecay
        energyFast *= timeoutDecay
        energySlow *= timeoutDecay
        kickEnv *= timeoutDecay
        beatPhase *= timeoutDecay
        bpmTwitcher *= timeoutDecay
        bpmSin4 *= timeoutDecay
        bpmConfidence *= timeoutDecay

        // Decay speed toward floor
        rampedSpeed = lerp(rampedSpeed, baseSpeedFloor, speedRampDown)
        beatBoostAccum *= beatBoostDecay

        return currentState
    }

    /// Check if audio is actively receiving
    var isActive: Bool {
        Date().timeIntervalSince(lastMessageTime) < timeoutDurationSec
    }

    /// Reset all state to silent
    func reset() {
        smoothBass = 0
        smoothLowMid = 0
        smoothMid = 0
        smoothHighs = 0
        smoothLevel = 0
        energyFast = 0
        energySlow = 0
        kickEnv = 0
        kickPulse = false
        beatPhase = 0
        beat4 = 0
        bpmTwitcher = 0
        bpmSin4 = 0
        bpmConfidence = 0
        rampedSpeed = baseSpeedFloor
        beatBoostAccum = 0
        lastMessageTime = .distantPast
    }

    // MARK: - Private

    /// Compute audio-reactive speed using Magic-style pipeline
    /// From SynesthesiaAudioOSC.pde:454-504
    private func computeAudioReactiveSpeed() -> Float {
        // No audio -> decay to floor
        guard isActive else {
            rampedSpeed = lerp(rampedSpeed, baseSpeedFloor, speedRampDown)
            beatBoostAccum *= beatBoostDecay
            return min(max(rampedSpeed + beatBoostAccum, baseSpeedFloor), audioSpeedMax)
        }

        // 1. SMOOTH (already done in update)
        // 2. SCALE: Map volume -> target speed
        let volumeDriver = smoothLevel * (1.0 - bassBoostWeight) + smoothBass * bassBoostWeight
        let clampedDriver = min(max(volumeDriver, 0), 1)
        let targetSpeed = baseSpeedFloor + clampedDriver * (audioSpeedMax - baseSpeedFloor)

        // 3. RAMP: Gradual buildup / faster decay
        if targetSpeed > rampedSpeed {
            rampedSpeed = lerp(rampedSpeed, targetSpeed, speedRampUp)
        } else {
            rampedSpeed = lerp(rampedSpeed, targetSpeed, speedRampDown)
        }

        // 4. BEAT BOOST: Transient punch on kicks/beats
        let beatTrigger = max(kickEnv, beatPhase) * beatBoostAmount
        beatBoostAccum = max(beatBoostAccum * beatBoostDecay, beatTrigger)

        // Final speed = ramped base + beat transient
        let finalSpeed = rampedSpeed + beatBoostAccum
        return min(max(finalSpeed, baseSpeedFloor), audioSpeedMax)
    }
}

// MARK: - Audio State Manager

/// Observable wrapper for AudioProcessor state
/// Use this in SwiftUI views
@MainActor
final class AudioStateManager: ObservableObject {
    @Published private(set) var state: AudioState = .silent

    private let processor = AudioProcessor()
    private var updateTimer: Timer?

    init() {}

    func start() {
        // Start periodic update for timeout decay
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performDecayUpdate()
            }
        }
    }

    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    /// Update from raw audio levels (call when receiving OSC/audio data)
    func update(rawLevels: RawAudioLevels) async {
        state = await processor.update(rawLevels: rawLevels)
    }

    /// Update from simplified levels (convenience)
    func update(bass: Float, mid: Float, highs: Float, level: Float) async {
        let raw = RawAudioLevels(
            bass: bass,
            lowMid: (bass + mid) / 2,
            mid: mid,
            highs: highs,
            level: level,
            hitsBass: bass * 1.2,  // Estimate hits from level
            onBeat: 0,
            beatTime: 0,
            intensity: level,
            bpmTwitcher: 0,
            bpmSin4: 0,
            bpmConfidence: 0
        )
        state = await processor.update(rawLevels: raw)
    }

    private func performDecayUpdate() async {
        state = await processor.updateWithTimeoutDecay()
    }
}

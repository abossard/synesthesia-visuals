// AudioProcessor.swift - Audio analysis and smoothing for VJ rendering
// Port of SynesthesiaAudioOSC.pde to Swift

import Foundation
import SwiftVJCore

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

    // Presence (slow-moving structural energy)
    private var bassPresence: Float = 0
    private var midPresence: Float = 0
    private var highPresence: Float = 0

    // Kick detection
    private var lastKickPulseTime: Date = .distantPast
    private var lastOnBeatValue: Float = 0

    // Timeout tracking
    private var lastMessageTime: Date = .distantPast
    private var lastUpdateTime: Date = Date()

    // MARK: - Constants (from SynesthesiaAudioOSC.pde)

    private let audioSmoothing: Float = 0.80
    private let energyFastSmoothing: Float = 0.60
    private let energySlowSmoothing: Float = 0.92
    private let kickEnvSmoothing: Float = 0.55
    private let presenceSmoothing: Float = 0.92
    private let kickPulseThreshold: Float = 0.65
    private let kickCooldownSec: TimeInterval = 0.140
    private let beatPhaseDecay: Float = 0.87
    private let beatOnThreshold: Float = 0.75
    private let timeoutDecay: Float = 0.90
    private let bpmLfoSmoothing: Float = 0.85
    private let timeoutDurationSec: TimeInterval = 1.5

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
            bassPresence: bassPresence,
            midPresence: midPresence,
            highPresence: highPresence,
            timestamp: Date()
        )
    }

    /// Update from OSC audio levels
    /// Call this when receiving audio data from Synesthesia OSC
    func update(oscLevels: OSCAudioLevels) -> AudioState {
        let now = Date()
        lastUpdateTime = now
        lastMessageTime = now

        // Apply exponential smoothing to band levels
        smoothBass = lerp(smoothBass, oscLevels.bass, 1 - audioSmoothing)
        smoothLowMid = lerp(smoothLowMid, oscLevels.lowMid, 1 - audioSmoothing)
        smoothMid = lerp(smoothMid, oscLevels.mid, 1 - audioSmoothing)
        smoothHighs = lerp(smoothHighs, oscLevels.highs, 1 - audioSmoothing)
        smoothLevel = lerp(smoothLevel, oscLevels.level, 1 - audioSmoothing)

        // Energy envelopes
        energyFast = lerp(energyFast, oscLevels.energyIntensity, 1 - energyFastSmoothing)
        energySlow = lerp(energySlow, energyFast, 1 - energySlowSmoothing)

        // Presence smoothing (very slow, structural energy)
        bassPresence = lerp(bassPresence, oscLevels.bassPresence, 1 - presenceSmoothing)
        midPresence = lerp(midPresence, oscLevels.midPresence, 1 - presenceSmoothing)
        highPresence = lerp(highPresence, oscLevels.highPresence, 1 - presenceSmoothing)

        // Kick detection with cooldown
        kickEnv = lerp(kickEnv, oscLevels.hitsBass, 1 - kickEnvSmoothing)
        kickPulse = false
        if oscLevels.hitsBass > kickPulseThreshold &&
           now.timeIntervalSince(lastKickPulseTime) > kickCooldownSec {
            kickPulse = true
            lastKickPulseTime = now
        }

        // Beat phase
        if oscLevels.onBeat >= beatOnThreshold && lastOnBeatValue < beatOnThreshold {
            beatPhase = 1.0
        } else {
            beatPhase *= beatPhaseDecay
        }
        lastOnBeatValue = oscLevels.onBeat

        // Beat counter
        let beatCycle = Int(round(oscLevels.beatTime)).remainderReportingOverflow(dividingBy: 8).partialValue
        beat4 = abs(beatCycle % 4)

        // BPM LFOs
        bpmTwitcher = lerp(bpmTwitcher, oscLevels.bpmTwitcher, 1 - bpmLfoSmoothing)
        bpmSin4 = lerp(bpmSin4, oscLevels.bpmSin4, 1 - bpmLfoSmoothing)
        bpmConfidence = lerp(bpmConfidence, oscLevels.bpmConfidence, 1 - bpmLfoSmoothing)

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
        bassPresence *= timeoutDecay
        midPresence *= timeoutDecay
        highPresence *= timeoutDecay

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
        bassPresence = 0
        midPresence = 0
        highPresence = 0
        lastMessageTime = .distantPast
        lastUpdateTime = Date()
    }
}

// MARK: - Audio State Manager

/// Observable wrapper for AudioProcessor state
/// Use this in SwiftUI views
@MainActor
final class AudioStateManager: ObservableObject {
    @Published private(set) var state: AudioState = .silent

    // OSC stats for UI display
    @Published private(set) var oscMessageRate: Int = 0
    @Published private(set) var oscMessageCount: Int = 0
    @Published private(set) var oscIsActive: Bool = false

    private let processor = AudioProcessor()
    private var decayTask: Task<Void, Never>?

    init() {}

    func start() {
        // Start periodic decay update on background thread
        decayTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))  // ~60 FPS
                guard let self = self else { break }

                // Perform decay on the processor (off main thread)
                let newState = await self.processor.updateWithTimeoutDecay()

                // Only hop to main thread to update published state
                await MainActor.run {
                    self.state = newState
                }
            }
        }
    }

    func stop() {
        decayTask?.cancel()
        decayTask = nil
    }

    /// Update from raw audio levels (call when receiving OSC/audio data)
    func update(oscLevels: OSCAudioLevels) async {
        let newState = await processor.update(oscLevels: oscLevels)
        state = newState
    }

    /// Process audio levels off-MainActor, returning new state
    /// Call this from render loop, then set state in single MainActor hop
    nonisolated func processAudioOffMain(oscLevels: OSCAudioLevels) async -> AudioState {
        await processor.update(oscLevels: oscLevels)
    }

    /// Set state directly (call from MainActor context)
    func setStateDirectly(_ newState: AudioState) {
        state = newState
    }
    
    /// Update OSC stats from processor
    func updateStats(messageRate: Int, messageCount: Int, isActive: Bool) {
        oscMessageRate = messageRate
        oscMessageCount = messageCount
        oscIsActive = isActive
    }

    /// Update from simplified levels (convenience)
    func update(bass: Float, mid: Float, highs: Float, level: Float) async {
        let osc = OSCAudioLevels(
            bass: bass,
            lowMid: (bass + mid) / 2,
            mid: mid,
            highs: highs,
            level: level,
            hitsBass: bass * 1.2,  // Estimate hits from level
            onBeat: 0,
            beatTime: 0,
            bpmTwitcher: 0,
            bpmSin4: 0,
            bpmConfidence: 0,
            energyIntensity: level,
            bassPresence: 0,
            midPresence: 0,
            highPresence: 0
        )
        state = await processor.update(oscLevels: osc)
    }
}

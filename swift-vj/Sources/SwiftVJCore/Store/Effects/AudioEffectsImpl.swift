// AudioEffectsImpl.swift - Audio monitoring effects
// Effects for audio level and beat tracking

import Foundation

/// Dependencies needed by audio effects
public struct AudioEnvironment: Sendable {
    public let synesthesiaAudio: SynesthesiaAudioProcessor

    public init(synesthesiaAudio: SynesthesiaAudioProcessor) {
        self.synesthesiaAudio = synesthesiaAudio
    }
}

/// Effects for audio monitoring
public enum AudioEffectsImpl {

    /// Start audio monitoring with batched updates
    ///
    /// Audio updates are high-frequency (1000+ Hz). We batch them to avoid
    /// overwhelming the store with actions. Updates are batched every 100ms.
    public static func startMonitoring(
        synesthesiaAudio: SynesthesiaAudioProcessor,
        batchInterval: Duration = .milliseconds(100)
    ) -> Effect<AudioAction> {
        .run(cancellationId: EffectCancellationId.audio) { send in
            while !Task.isCancelled {
                try? await Task.sleep(for: batchInterval)

                // Get current audio state
                let levels = synesthesiaAudio.getLevelsFast()
                let (bpm, beatPhase, _) = await synesthesiaAudio.getBPM()

                let state = AudioSubState(
                    level: levels.level,
                    beatPhase: beatPhase,
                    bpm: bpm,
                    energy: levels.level, // Use level as proxy for energy
                    bass: levels.bass,
                    mid: levels.mid,
                    high: levels.high
                )

                await send(.stateUpdated(state))
            }
        }
    }

    /// Stop audio monitoring
    public static func stopMonitoring() -> Effect<AudioAction> {
        .cancel(id: EffectCancellationId.audio)
    }

    /// Subscribe to BPM changes (less frequent, for Launchpad sync)
    public static func subscribeToBPM(
        synesthesiaAudio: SynesthesiaAudioProcessor,
        updateInterval: Duration = .seconds(5)
    ) -> Effect<AudioAction> {
        .run(cancellationId: EffectCancellationId.custom("bpm-sync")) { send in
            while !Task.isCancelled {
                try? await Task.sleep(for: updateInterval)

                let (bpm, _, _) = await synesthesiaAudio.getBPM()
                if bpm > 0 {
                    await send(.bpmDetected(bpm))
                }
            }
        }
    }

    /// Get current audio state snapshot
    public static func getSnapshot(
        synesthesiaAudio: SynesthesiaAudioProcessor
    ) -> Effect<AudioAction> {
        .run { send in
            let levels = synesthesiaAudio.getLevelsFast()
            let (bpm, beatPhase, _) = await synesthesiaAudio.getBPM()

            let state = AudioSubState(
                level: levels.level,
                beatPhase: beatPhase,
                bpm: bpm,
                energy: levels.level,
                bass: levels.bass,
                mid: levels.mid,
                high: levels.high
            )

            await send(.stateUpdated(state))
        }
    }
}

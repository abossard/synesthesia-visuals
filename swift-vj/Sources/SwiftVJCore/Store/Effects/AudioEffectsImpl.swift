// AudioEffectsImpl.swift - Audio monitoring effects (stub)
// Audio input from Magic is no longer routed through SwiftVJApp.
// Magic sends OSC directly to QLC+5 for audio-reactive lighting.

import Foundation

/// Dependencies needed by audio effects (currently unused — no audio input)
public struct AudioEnvironment: Sendable {
    public init() {}
}

/// Effects for audio monitoring (stubs — no audio source)
public enum AudioEffectsImpl {

    /// Start audio monitoring (no-op: no audio source)
    public static func startMonitoring(
        batchInterval: Duration = .milliseconds(100)
    ) -> Effect<AudioAction> {
        .none
    }

    /// Stop audio monitoring
    public static func stopMonitoring() -> Effect<AudioAction> {
        .cancel(id: EffectCancellationId.audio)
    }
}

// OSCEffects.swift - OSC communication effects
// Effects for OSC subscription and message sending

import Foundation

/// Effects for OSC communication
public enum OSCEffects {

    // MARK: - Subscription Effects

    /// Start OSC server and subscribe to all messages
    public static func startServer(
        onMessage: @escaping @Sendable (String, [String]) -> AppAction?
    ) -> Effect<AppAction> {
        .run(cancellationId: EffectCancellationId.osc) { send in
            // This effect runs continuously, dispatching actions for incoming OSC
            // The actual OSCHub is managed externally and calls back into this
            // For now, this is a placeholder that would be wired up during integration

            // In the real implementation, this would:
            // 1. Get reference to OSCHub from environment
            // 2. Subscribe to patterns
            // 3. Dispatch actions for each message

            // Keep the effect alive
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Subscribe to VDJ deck messages
    public static func subscribeToVDJ() -> Effect<AppAction> {
        .run(cancellationId: EffectCancellationId.custom("vdj")) { send in
            // Placeholder for VDJ subscription
            // Will dispatch playback actions when VDJ sends updates
        }
    }

    /// Subscribe to Synesthesia audio messages
    public static func subscribeToAudio() -> Effect<AppAction> {
        .run(cancellationId: EffectCancellationId.audio) { send in
            // Placeholder for audio subscription
            // Uses nonisolated fast path for high-frequency updates
        }
    }

    // MARK: - Send Effects

    /// Send OSC message to Magic/Synesthesia
    public static func sendToMagic(
        address: String,
        values: [Any]
    ) -> Effect<AppAction> {
        .fireAndForget {
            // Placeholder - actual implementation would use OSCHub
            // try? oscHub.sendToMagic(address, values: values)
        }
    }

    /// Send OSC message to VDJ
    public static func sendToVDJ(
        address: String,
        values: [Any] = []
    ) -> Effect<AppAction> {
        .fireAndForget {
            // Placeholder - actual implementation would use OSCHub
            // try? oscHub.sendToVDJ(address, values: values)
        }
    }

    /// Send OSC message to Synesthesia
    public static func sendToSynesthesia(
        address: String,
        values: [Any]
    ) -> Effect<AppAction> {
        .fireAndForget {
            // Placeholder - actual implementation would use OSCHub
            // try? oscHub.sendToSynesthesia(address, values: values)
        }
    }

    /// Send shader load command
    public static func sendShaderLoad(
        name: String,
        energy: Float,
        valence: Float
    ) -> Effect<AppAction> {
        .fireAndForget {
            // try? oscHub.sendToMagic("/shader/load", values: [name, energy, valence])
        }
    }

    /// Send image folder command
    public static func sendImageFolder(_ path: String) -> Effect<AppAction> {
        .fireAndForget {
            // try? oscHub.sendToMagic("/image/folder", values: [path])
        }
    }

    // MARK: - VDJ Query Effects

    /// Query VDJ for deck state
    public static func queryVDJDeck(_ deck: Int) -> Effect<AppAction> {
        .fireAndForget {
            // let verbs = ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength", "song_pos", "play"]
            // for verb in verbs {
            //     try? oscHub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
            // }
        }
    }

    /// Subscribe to VDJ updates
    public static func subscribeVDJ() -> Effect<AppAction> {
        .fireAndForget {
            // for deck in [1, 2] {
            //     for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength", "loaded"] {
            //         try? oscHub.sendToVDJ("/vdj/subscribe/deck/\(deck)/\(verb)")
            //     }
            // }
            // try? oscHub.sendToVDJ("/vdj/subscribe/crossfader")
        }
    }
}

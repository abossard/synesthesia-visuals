// PlaybackEffectsImpl.swift - Playback monitoring effects
// Effects for VDJ/Spotify playback tracking
// NOTE: PlaybackModule now uses dispatch pattern - no callbacks needed

import Foundation

/// Dependencies needed by playback effects
public struct PlaybackEnvironment: Sendable {
    public let playbackModule: PlaybackModule
    public let oscHub: OSCHub

    public init(playbackModule: PlaybackModule, oscHub: OSCHub) {
        self.playbackModule = playbackModule
        self.oscHub = oscHub
    }
}

/// Effects for playback monitoring
public enum PlaybackEffectsImpl {

    /// Start monitoring playback from current source
    /// NOTE: PlaybackModule dispatches actions directly via its dispatch closure
    /// This effect just starts the module - actions flow through the Store automatically
    public static func startMonitoring(
        playbackModule: PlaybackModule
    ) -> Effect<PlaybackAction> {
        .run(cancellationId: EffectCancellationId.playback) { send in
            // Start the module - it will dispatch actions via its dispatch closure
            do {
                try await playbackModule.start()
            } catch {
                // Log error but don't fail
            }

            // Keep effect alive (module runs its own polling loop)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Stop playback monitoring
    public static func stopMonitoring(
        playbackModule: PlaybackModule
    ) -> Effect<PlaybackAction> {
        .fireAndForget {
            await playbackModule.stop()
        }
    }

    /// Poll for current playback state
    public static func poll(
        playbackModule: PlaybackModule
    ) -> Effect<PlaybackAction> {
        .fireAndForget {
            await playbackModule.poll()
            // Module will dispatch trackChanged/positionUpdated via its dispatch closure
        }
    }

    /// Setup VDJ subscriptions and queries
    public static func setupVDJ(
        oscHub: OSCHub,
        playbackModule: PlaybackModule
    ) -> Effect<PlaybackAction> {
        .run { send in
            // Send VDJ subscriptions
            do {
                for deck in [1, 2] {
                    for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength", "loaded"] {
                        try oscHub.sendToVDJ("/vdj/subscribe/deck/\(deck)/\(verb)")
                    }
                }
                try oscHub.sendToVDJ("/vdj/subscribe/crossfader")
            } catch {
                // Ignore subscription errors
            }

            // Query current state
            do {
                for deck in [1, 2] {
                    for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength"] {
                        try oscHub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                    }
                    for verb in ["song_pos", "play", "volume", "is_audible"] {
                        try oscHub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                    }
                }
            } catch {
                // Ignore query errors
            }

            // Poll once - module dispatches result
            await playbackModule.poll()
        }
    }

    /// Setup playback source
    public static func setupSource(
        _ source: String,
        playbackModule: PlaybackModule,
        oscHub: OSCHub
    ) -> Effect<PlaybackAction> {
        .run { send in
            let sourceType: PlaybackSourceType = source == "vdj" ? .vdj : .spotify
            await playbackModule.setSource(sourceType)

            if sourceType == .vdj {
                // Setup VDJ
                do {
                    for deck in [1, 2] {
                        for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength", "loaded"] {
                            try oscHub.sendToVDJ("/vdj/subscribe/deck/\(deck)/\(verb)")
                        }
                    }
                    try oscHub.sendToVDJ("/vdj/subscribe/crossfader")
                } catch {
                    // Ignore errors
                }
            }
        }
    }

    /// Start periodic VDJ queries
    public static func startVDJPolling(
        oscHub: OSCHub,
        interval: Duration = .seconds(1)
    ) -> Effect<PlaybackAction> {
        .run(cancellationId: EffectCancellationId.custom("vdj-polling")) { send in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)

                // Query deck state
                do {
                    for deck in [1, 2] {
                        for verb in ["get_title", "get_artist", "get_album", "get_bpm", "get_songlength"] {
                            try oscHub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                        }
                        for verb in ["song_pos", "play", "volume", "is_audible"] {
                            try oscHub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                        }
                    }
                } catch {
                    // Ignore transient errors
                }
            }
        }
    }
}

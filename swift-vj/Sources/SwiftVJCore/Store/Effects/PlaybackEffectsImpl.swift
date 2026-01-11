// PlaybackEffectsImpl.swift - Playback monitoring effects
// Effects for VDJ/Spotify playback tracking

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
    public static func startMonitoring(
        environment: PlaybackEnvironment,
        onTrackChange: @escaping @Sendable (Track) async -> Void,
        onPositionUpdate: @escaping @Sendable (Double, Bool) async -> Void
    ) -> Effect<PlaybackAction> {
        .run(cancellationId: EffectCancellationId.playback) { send in
            // Register callbacks
            await environment.playbackModule.onTrackChange { track in
                await onTrackChange(track)
                await send(.trackChanged(track))
            }

            await environment.playbackModule.onPositionUpdate { position, isPlaying in
                await onPositionUpdate(position, isPlaying)
                await send(.positionUpdated(position: position, isPlaying: isPlaying))
            }

            // Start the module
            do {
                try await environment.playbackModule.start()
            } catch {
                // Log error but don't fail
            }

            // Keep effect alive
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
        .run { send in
            await playbackModule.poll()
            if let track = await playbackModule.currentTrack {
                await send(.trackChanged(track))
            }
            let state = await playbackModule.playbackState
            await send(.positionUpdated(position: state.position, isPlaying: state.isPlaying))
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

            // Poll once
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

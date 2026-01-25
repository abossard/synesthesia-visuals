// PlaybackModule - Track detection with source switching
// Following A Philosophy of Software Design: deep module hiding complexity
// Unidirectional Data Flow: dispatches actions instead of callbacks

import Foundation
import OSCKit

/// Playback source types
public enum PlaybackSourceType: String, Sendable, CaseIterable {
    case spotify = "spotify"
    case vdj = "vdj"
    case none = "none"
}

/// Playback module - monitors playback from VDJ or Spotify
///
/// Deep module interface:
/// - `start()` / `stop()` - lifecycle
/// - `setSource(_:)` - switch between VDJ/Spotify
/// - `currentTrack` - what's playing now
/// - `dispatch` - action dispatcher for unidirectional data flow
///
/// Hides: polling, source-specific protocols, state diffing
public actor PlaybackModule: Module {

    // MARK: - Configuration

    private static let pollInterval: TimeInterval = 1.0

    // MARK: - State

    public private(set) var isStarted: Bool = false
    private var currentState: PlaybackState = PlaybackState()
    private var sourceType: PlaybackSourceType = .none

    // Adapters
    private var spotifyMonitor: SpotifyMonitor?
    private var vdjMonitor: VDJMonitor?
    private var oscHub: OSCHub?

    // Polling
    private var pollTask: Task<Void, Never>?

    // MARK: - Action Dispatcher (Unidirectional Data Flow)

    /// Action dispatcher - set this to integrate with Store
    public var dispatch: (@Sendable (AppAction) async -> Void)?

    // MARK: - Init

    public init(oscHub: OSCHub? = nil) {
        self.oscHub = oscHub
    }
    
    // MARK: - Module Protocol
    
    public func start() async throws {
        guard !isStarted else { throw ModuleError.alreadyStarted }
        
        // Initialize adapters
        spotifyMonitor = SpotifyMonitor()
        vdjMonitor = VDJMonitor()
        
        isStarted = true
        
        // Start polling loop
        pollTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }
    
    public func stop() async {
        pollTask?.cancel()
        pollTask = nil
        
        isStarted = false
    }
    
    public func getStatus() -> ModuleStatus {
        var status = ModuleStatus([
            "started": .bool(isStarted),
            "source": .string(sourceType.rawValue),
            "has_track": .bool(currentState.hasTrack)
        ])

        if let track = currentState.track {
            status["artist"] = .string(track.artist)
            status["title"] = .string(track.title)
            status["position"] = .double(currentState.position)
            status["is_playing"] = .bool(currentState.isPlaying)
        }

        return status
    }
    
    // MARK: - Public API
    
    /// Current playback state
    public var playbackState: PlaybackState {
        currentState
    }
    
    /// Current track (nil if nothing playing)
    public var currentTrack: Track? {
        currentState.track
    }
    
    /// Current playback source
    public var currentSource: PlaybackSourceType {
        sourceType
    }
    
    /// Set playback source (hot-swap supported)
    public func setSource(_ source: PlaybackSourceType) async {
        guard source != sourceType else { return }
        
        sourceType = source
        
        // Start VDJ subscription if switching to VDJ
        if source == .vdj, let hub = oscHub, let vdj = vdjMonitor {
            try? await vdj.subscribe(using: hub)
        }
        
        // Clear current state when switching
        currentState = PlaybackState()
    }
    
    /// Set action dispatcher for Store integration
    public func setDispatch(_ dispatch: @escaping @Sendable (AppAction) async -> Void) {
        self.dispatch = dispatch
    }
    
    /// Force poll (for testing)
    public func poll() async {
        await pollOnce()
    }
    
    /// Handle VDJ OSC message (forwarded from OSCHub)
    public func handleVDJOSC(address: String, values: [any OSCValue]) async {
        await vdjMonitor?.handleOSC(address: address, values: values)
    }
    
    // MARK: - Private
    
    private func pollLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            try? await Task.sleep(for: .seconds(Self.pollInterval))
        }
    }
    
    private func pollOnce() async {
        let previousTrackKey = currentState.track?.key
        
        switch sourceType {
        case .spotify:
            await pollSpotify()
        case .vdj:
            await pollVDJ()
        case .none:
            return
        }
        
        // Detect track change
        let currentTrackKey = currentState.track?.key
        if currentTrackKey != previousTrackKey, let track = currentState.track {
            await fireTrackChange(track)
        }
        
        // Fire position update
        await firePositionUpdate(currentState.position, currentState.isPlaying)
    }
    
    private func pollSpotify() async {
        guard let monitor = spotifyMonitor else { return }
        
        do {
            let playback = try await monitor.getPlayback()
            
            let track = Track(
                artist: playback.artist,
                title: playback.title,
                album: playback.album,
                duration: Double(playback.durationMs) / 1000.0
            )
            
            currentState = PlaybackState(
                track: track,
                position: Double(playback.positionMs) / 1000.0,
                isPlaying: playback.isPlaying,
                lastUpdate: Date(),
                source: "spotify"
            )
        } catch {
            // Spotify not available - keep previous state but mark not playing
            if currentState.isPlaying {
                currentState = PlaybackState(
                    track: currentState.track,
                    position: currentState.position,
                    isPlaying: false,
                    lastUpdate: Date(),
                    source: "spotify"
                )
            }
        }
    }
    
    private func pollVDJ() async {
        guard let monitor = vdjMonitor, let hub = oscHub else { return }
        
        // Query VDJ for fresh data (VDJ doesn't push is_audible/position changes)
        try? await monitor.query(using: hub)
        
        let playback = await monitor.getPlayback()
        
        // Only log when deck selection changes or on track detection
        if let deck = playback.audibleDeck, deck.hasTrack {
            let track = Track(
                artist: deck.artist,
                title: deck.title,
                album: deck.album,
                duration: deck.duration
            )
            
            currentState = PlaybackState(
                track: track,
                position: deck.position,
                isPlaying: deck.isPlaying,
                lastUpdate: Date(),
                source: "vdj"
            )
        } else {
            // No audible track
            if currentState.hasTrack {
                currentState = PlaybackState(
                    track: nil,
                    position: 0,
                    isPlaying: false,
                    lastUpdate: Date(),
                    source: "vdj"
                )
            }
        }
    }
    
    private func fireTrackChange(_ track: Track) async {
        await dispatch?(.playback(.trackChanged(track)))
    }

    private func firePositionUpdate(_ position: Double, _ isPlaying: Bool) async {
        await dispatch?(.playback(.positionUpdated(position: position, isPlaying: isPlaying)))
    }
}

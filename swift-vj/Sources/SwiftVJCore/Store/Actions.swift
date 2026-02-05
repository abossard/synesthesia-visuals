// Actions.swift - Action types for unidirectional data flow
// Actions describe events that trigger state changes

import Foundation

// MARK: - Root App Action

/// Root action type for the application.
///
/// All state changes are triggered by actions. Actions are:
/// - Serializable (for debugging/logging)
/// - Composable (child actions embedded in parent)
/// - Descriptive (named after what happened, not what to do)
public enum AppAction: Sendable {
    // MARK: - Lifecycle
    case startup
    case shutdown
    case systemReady

    // MARK: - Child Actions
    case playback(PlaybackAction)
    case pipeline(PipelineAction)
    case render(RenderAction)
    case launchpad(LaunchpadAction)
    case audio(AudioAction)
    case ui(UIAction)
    case ledfx(LedFXAction)
    case songs(SongsAction)

    // MARK: - Persistence
    case loadPersistedState
    case persistedStateLoaded(PersistedState)
    case persistState
}

// MARK: - Playback Actions

/// Actions related to playback state
public enum PlaybackAction: Sendable {
    /// Track changed (from VDJ/Spotify)
    case trackChanged(Track)

    /// Playback position updated
    case positionUpdated(position: Double, isPlaying: Bool)

    /// Playback source changed (user selection)
    case sourceChanged(String)

    /// Playing state changed
    case playingStateChanged(Bool)

    /// Timing offset adjusted
    case timingOffsetChanged(Int)

    /// Request to start playback monitoring
    case startMonitoring

    /// Request to stop playback monitoring
    case stopMonitoring

    /// Poll for current state (VDJ query)
    case poll
}

// MARK: - Pipeline Actions

/// Actions related to pipeline processing
public enum PipelineAction: Sendable {
    /// Start processing a track
    case startProcessing(Track)

    /// Pipeline step started
    case stepStarted(String)

    /// Pipeline step completed with status
    case stepCompleted(String, PipelineStepStatus)

    /// Pipeline processing completed
    case processingCompleted(PipelineResult)

    /// Pipeline processing failed
    case processingFailed(String)

    /// Reset pipeline state
    case reset

    /// Clear pipeline cache
    case clearCache

    /// Update step status directly
    case updateStep(name: String, status: String, details: [String]?)
}

// MARK: - Render Actions

/// Actions related to rendering state
public enum RenderAction: Sendable {
    /// Select a shader
    case selectShader(String)

    /// Shader selected successfully
    case shaderSelected(String)

    /// Select a phase
    case selectPhase(Phase?)

    /// Phase detected from song analysis
    case phaseDetected(Phase?)

    /// Set image index
    case setImageIndex(Int)

    /// Advance to next image
    case nextImage

    /// Go to previous image
    case prevImage

    /// Images loaded from folder
    case imagesLoaded(count: Int, folderPath: String)

    /// Update shader count
    case shaderCountUpdated(Int)

    /// Start render engine
    case startEngine

    /// Stop render engine
    case stopEngine
}

// MARK: - Launchpad Actions

/// Actions related to Launchpad controller
public enum LaunchpadAction: Sendable {
    /// Launchpad connected
    case connected(String)

    /// Launchpad disconnected
    case disconnected

    /// Button pressed
    case buttonPressed(x: Int, y: Int)

    /// Button released
    case buttonReleased(x: Int, y: Int)

    /// Controller state updated
    case stateUpdated(ControllerStateSnapshot)

    /// Status updated
    case statusUpdated(LaunchpadStatusSnapshot)

    /// Bank changed
    case bankChanged(Int)

    /// Start Launchpad module
    case start

    /// Stop Launchpad module
    case stop

    /// Enter learn mode
    case enterLearnMode

    /// Exit learn mode
    case exitLearnMode
}

// MARK: - Audio Actions

/// Actions related to audio state
public enum AudioAction: Sendable {
    /// Audio state updated (batched for performance)
    case stateUpdated(AudioSubState)

    /// Individual level update (high frequency)
    case levelUpdated(Float)

    /// Beat phase updated
    case beatPhaseUpdated(Float)

    /// BPM detected
    case bpmDetected(Float)

    /// Start audio monitoring
    case startMonitoring

    /// Stop audio monitoring
    case stopMonitoring
}

// MARK: - UI Actions

/// Actions related to UI state
public enum UIAction: Sendable {
    /// Log a message
    case log(String, LogLevelState)

    /// Clear logs
    case clearLogs

    /// OSC message received (for debug view)
    case oscMessageReceived(address: String, args: [String])

    /// Clear OSC messages
    case clearOscMessages

    /// Toggle OSC debug mode
    case setOscDebugEnabled(Bool)

    /// Set OSC filter
    case setOscFilter(String)
}

// MARK: - LedFX Actions

/// Snapshot of LedFX state fetched from server
public struct LedFXRefreshSnapshot: Sendable, Equatable {
    public let serverInfo: LedFXInfo?
    public let scenes: [String: LedFXScene]
    public let virtuals: [String: LedFXVirtual]
    public let playlists: [String: LedFXPlaylist]
    public let isOnline: Bool
    public let healthSummary: String
    public let lastHealthCheck: Date

    public init(
        serverInfo: LedFXInfo?,
        scenes: [String: LedFXScene],
        virtuals: [String: LedFXVirtual],
        playlists: [String: LedFXPlaylist],
        isOnline: Bool,
        healthSummary: String,
        lastHealthCheck: Date
    ) {
        self.serverInfo = serverInfo
        self.scenes = scenes
        self.virtuals = virtuals
        self.playlists = playlists
        self.isOnline = isOnline
        self.healthSummary = healthSummary
        self.lastHealthCheck = lastHealthCheck
    }
}

/// Actions related to LedFX configuration and OSC → REST bridge
public enum LedFXAction: Sendable {
    /// Update the base URL field (UI state)
    case setBaseURL(String)

    /// Update the virtual IDs field (comma-separated UI state)
    case setVirtualIds(String)

    /// Update the scene filter regex (UI state)
    case setSceneFilter(String)

    /// Update the playlist filter regex (UI state)
    case setPlaylistFilter(String)

    /// Apply settings and reconnect
    case applySettings(baseURL: String, virtualIds: [String])

    /// Refresh server state (scenes, virtuals, playlists)
    case refresh

    /// Test the LedFX connection
    case testConnection

    /// Refresh succeeded with latest server snapshot
    case refreshCompleted(LedFXRefreshSnapshot)

    /// Refresh failed with error message
    case refreshFailed(String)

    /// Activate a scene by id
    case activateScene(String)

    /// Deactivate a scene by id
    case deactivateScene(String)

    /// Delete a scene by id
    case deleteScene(String)

    /// Activate a playlist by id
    case activatePlaylist(String)

    /// Playlist activated successfully
    case playlistActivated(String)

    /// Stop the current playlist
    case stopPlaylist

    /// Playlist stopped successfully
    case playlistStopped

    /// Set brightness for a virtual
    case setVirtualBrightness(id: String, brightness: Double)

    /// Generate scenes from DJ set metadata
    case generateScenes([LedFXSceneSeed])

    /// Generate a fresh OSC → REST bridge config
    case generateBridgeConfig

    /// Generated a bridge config successfully
    case generateConfigCompleted(yaml: String, playlistCount: Int, effectsCount: Int)

    /// Failed to generate bridge config
    case generateConfigFailed(String)

    /// Save the generated bridge config to disk
    case saveGeneratedConfig

    /// Load cached bridge config from disk
    case loadCachedConfig

    /// Cached config loaded successfully
    case cachedConfigLoaded(yaml: String, playlistCount: Int)

    /// Cached config failed to load
    case cachedConfigFailed(String)

    /// Load the generated bridge config into the bridge
    case loadGeneratedConfig(yaml: String)

    /// Send a test OSC message for the first scene
    case sendTestScene

    /// Send a test OSC message for the first playlist
    case sendTestPlaylist

    /// Send a test OSC message for the first oneshot
    case sendTestOneshot

    /// Apply settings completed
    case applyCompleted

    /// Update the current error message (nil clears)
    case setError(String?)

    /// Clear any LedFX error message
    case clearError
}

/// Input model for LedFX scene generation
public struct LedFXSceneSeed: Sendable, Equatable {
    public let name: String
    public let energy: Double
    public let valence: Double
    public let bpm: Double?

    public init(name: String, energy: Double, valence: Double, bpm: Double?) {
        self.name = name
        self.energy = energy
        self.valence = valence
        self.bpm = bpm
    }
}

// MARK: - Songs Actions

import SongRepository

/// Actions related to songs management
public enum SongsAction: Sendable {
    /// Load songs database
    case load

    /// Songs loaded
    case loaded(count: Int)

    /// Song recorded from pipeline
    case songRecorded(artist: String, title: String)

    /// Song selected in browser
    case songSelected(SongID?)

    /// Request to delete a song
    case deleteSong(SongID)

    /// Song deleted successfully
    case songDeleted(SongID)

    /// Request re-analysis
    case requestReanalysis(SongID)

    /// Re-analysis started
    case reanalysisStarted(SongID)

    /// Re-analysis completed
    case reanalysisCompleted(SongID)

    /// Update shader for song
    case setShader(SongID, String)

    /// Search songs
    case search(String)

    /// Search results received
    case searchResultsReceived([Song])

    /// Apply filter
    case applyFilter(SongFilter)

    /// Filter results received
    case filterResultsReceived([Song])

    /// Save songs database
    case save

    /// Clear search/filter
    case clearFilter

    /// Update statistics
    case statisticsUpdated(SongStatistics)

    /// Refresh displayed songs
    case refreshList

    /// Delete a single image from a song
    case deleteImage(SongID, URL)

    /// Song updated (e.g., image count changed)
    case songUpdated(Song)

    // MARK: - Folder Scanning

    /// Request to scan a folder for music files
    case scanFolderRequested(URL)

    /// Scan started with total file count
    case scanStarted(total: Int, folderName: String)

    /// Scan progress update
    case scanProgress(current: Int, found: Int)

    /// Song discovered during scan (add if not duplicate)
    case songDiscovered(artist: String, title: String)

    /// Scan completed
    case scanCompleted

    /// Request to cancel ongoing scan (from UI)
    case cancelScanRequested

    /// Scan was cancelled
    case scanCancelled
}

// MARK: - Action Descriptions (for debugging)

extension AppAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .startup: return "startup"
        case .shutdown: return "shutdown"
        case .systemReady: return "systemReady"
        case .playback(let action): return "playback.\(action)"
        case .pipeline(let action): return "pipeline.\(action)"
        case .render(let action): return "render.\(action)"
        case .launchpad(let action): return "launchpad.\(action)"
        case .audio(let action): return "audio.\(action)"
        case .ui(let action): return "ui.\(action)"
        case .ledfx(let action): return "ledfx.\(action)"
        case .songs(let action): return "songs.\(action)"
        case .loadPersistedState: return "loadPersistedState"
        case .persistedStateLoaded: return "persistedStateLoaded"
        case .persistState: return "persistState"
        }
    }
}

extension PlaybackAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .trackChanged(let track): return "trackChanged(\(track.artist) - \(track.title))"
        case .positionUpdated(let pos, let playing): return "positionUpdated(\(String(format: "%.1f", pos)), playing: \(playing))"
        case .sourceChanged(let source): return "sourceChanged(\(source))"
        case .playingStateChanged(let playing): return "playingStateChanged(\(playing))"
        case .timingOffsetChanged(let offset): return "timingOffsetChanged(\(offset))"
        case .startMonitoring: return "startMonitoring"
        case .stopMonitoring: return "stopMonitoring"
        case .poll: return "poll"
        }
    }
}

extension PipelineAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .startProcessing(let track): return "startProcessing(\(track.artist) - \(track.title))"
        case .stepStarted(let step): return "stepStarted(\(step))"
        case .stepCompleted(let step, _): return "stepCompleted(\(step))"
        case .processingCompleted: return "processingCompleted"
        case .processingFailed(let error): return "processingFailed(\(error))"
        case .reset: return "reset"
        case .clearCache: return "clearCache"
        case .updateStep(let name, let status, _): return "updateStep(\(name): \(status))"
        }
    }
}

extension RenderAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .selectShader(let name): return "selectShader(\(name))"
        case .shaderSelected(let name): return "shaderSelected(\(name))"
        case .selectPhase(let phase): return "selectPhase(\(phase?.rawValue ?? "auto"))"
        case .phaseDetected(let phase): return "phaseDetected(\(phase?.rawValue ?? "none"))"
        case .setImageIndex(let index): return "setImageIndex(\(index))"
        case .nextImage: return "nextImage"
        case .prevImage: return "prevImage"
        case .imagesLoaded(let count, _): return "imagesLoaded(\(count))"
        case .shaderCountUpdated(let count): return "shaderCountUpdated(\(count))"
        case .startEngine: return "startEngine"
        case .stopEngine: return "stopEngine"
        }
    }
}

extension LaunchpadAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .connected(let name): return "connected(\(name))"
        case .disconnected: return "disconnected"
        case .buttonPressed(let x, let y): return "buttonPressed(\(x), \(y))"
        case .buttonReleased(let x, let y): return "buttonReleased(\(x), \(y))"
        case .stateUpdated: return "stateUpdated"
        case .statusUpdated: return "statusUpdated"
        case .bankChanged(let bank): return "bankChanged(\(bank))"
        case .start: return "start"
        case .stop: return "stop"
        case .enterLearnMode: return "enterLearnMode"
        case .exitLearnMode: return "exitLearnMode"
        }
    }
}

extension AudioAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .stateUpdated: return "stateUpdated"
        case .levelUpdated(let level): return "levelUpdated(\(String(format: "%.2f", level)))"
        case .beatPhaseUpdated(let phase): return "beatPhaseUpdated(\(String(format: "%.2f", phase)))"
        case .bpmDetected(let bpm): return "bpmDetected(\(Int(bpm)))"
        case .startMonitoring: return "startMonitoring"
        case .stopMonitoring: return "stopMonitoring"
        }
    }
}

extension UIAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .log(let message, let level): return "log(\(level): \(message.prefix(50))...)"
        case .clearLogs: return "clearLogs"
        case .oscMessageReceived(let address, _): return "oscMessageReceived(\(address))"
        case .clearOscMessages: return "clearOscMessages"
        case .setOscDebugEnabled(let enabled): return "setOscDebugEnabled(\(enabled))"
        case .setOscFilter(let filter): return "setOscFilter(\(filter))"
        }
    }
}

extension SongsAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .load: return "load"
        case .loaded(let count): return "loaded(\(count))"
        case .songRecorded(let artist, let title): return "songRecorded(\(artist) - \(title))"
        case .songSelected(let id): return "songSelected(\(id?.rawValue ?? "none"))"
        case .deleteSong(let id): return "deleteSong(\(id))"
        case .songDeleted(let id): return "songDeleted(\(id))"
        case .requestReanalysis(let id): return "requestReanalysis(\(id))"
        case .reanalysisStarted(let id): return "reanalysisStarted(\(id))"
        case .reanalysisCompleted(let id): return "reanalysisCompleted(\(id))"
        case .setShader(let id, let shader): return "setShader(\(id), \(shader))"
        case .search(let query): return "search(\(query))"
        case .searchResultsReceived(let songs): return "searchResultsReceived(\(songs.count))"
        case .applyFilter: return "applyFilter"
        case .filterResultsReceived(let songs): return "filterResultsReceived(\(songs.count))"
        case .save: return "save"
        case .clearFilter: return "clearFilter"
        case .statisticsUpdated: return "statisticsUpdated"
        case .refreshList: return "refreshList"
        case .deleteImage: return "deleteImage"
        case .songUpdated(let song): return "songUpdated(\(song.id.rawValue))"
        case .scanFolderRequested(let url): return "scanFolderRequested(\(url.lastPathComponent))"
        case .scanStarted(let total, let name): return "scanStarted(\(total) files in \(name))"
        case .scanProgress(let current, let found): return "scanProgress(\(current), found: \(found))"
        case .songDiscovered(let artist, let title): return "songDiscovered(\(artist) - \(title))"
        case .scanCompleted: return "scanCompleted"
        case .cancelScanRequested: return "cancelScanRequested"
        case .scanCancelled: return "scanCancelled"
        }
    }
}

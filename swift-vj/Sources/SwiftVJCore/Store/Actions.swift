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
    case launcher(LauncherAction)
    case ledfx(LedFXAction)
    case songs(SongsAction)
    case automation(AutomationAction)
    case moodboard(MoodboardAction)
    case preview(PreviewAction)

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

    /// Track changed from Song Manager demo flow; always re-runs pipeline
    case demoTrackChanged(Track)

    /// Playback position updated
    case positionUpdated(position: Double, isPlaying: Bool)

    /// Playback source changed (user selection)
    case sourceChanged(String)

    /// Playing state changed
    case playingStateChanged(Bool)

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

    /// Toggle expanded/collapsed state for a step in Pipeline UI
    case toggleStepExpansion(String)
}

// MARK: - Render Actions

/// Actions related to rendering state
public enum RenderAction: Sendable {
    /// Enable or disable the renderer and Syphon output
    case setEnabled(Bool)

    /// Enable or disable a specific Syphon/render output
    case setOutputEnabled(output: RenderOutput, enabled: Bool)

    /// Select a shader
    case selectShader(String)

    /// Select a mask shader
    case selectMaskShader(String)

    /// Shader selected successfully
    case shaderSelected(String)

    /// Mask shader selected successfully
    case maskShaderSelected(String)

    /// Navigate to next shader
    case selectNextShader

    /// Navigate to previous shader
    case selectPreviousShader

    /// Select random shader
    case selectRandomShader

    /// Navigate to next mask shader
    case selectNextMaskShader

    /// Navigate to previous mask shader
    case selectPreviousMaskShader

    /// Select random mask shader
    case selectRandomMaskShader

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

    /// Update per-shader workspace controls (bin0/bin1/bin2/zoom)
    case setShaderWorkspaceControls(shaderName: String, controls: ShaderWorkspaceControls)

    /// Reset per-shader workspace controls to defaults
    case resetShaderWorkspaceControls(shaderName: String)

    /// Toggle shader playlist auto-advance on song change
    case setShaderAutoAdvanceOnSongChange(Bool)

    /// Toggle mask playlist auto-advance on song change
    case setMaskAutoAdvanceOnSongChange(Bool)

    /// Set latest AI shader suggestion (optional if no match)
    case setAISuggestedShader(name: String?, phase: Phase?)

    /// Add shader to phase playlist (duplicates allowed)
    case addShaderToPhasePlaylist(phase: Phase, shaderName: String, activate: Bool)

    /// Add mask to phase playlist (duplicates allowed)
    case addMaskToPhasePlaylist(phase: Phase, maskName: String, activate: Bool)

    /// Remove shader playlist item at index
    case removeShaderFromPhasePlaylist(phase: Phase, index: Int)

    /// Remove mask playlist item at index
    case removeMaskFromPhasePlaylist(phase: Phase, index: Int)

    /// Move shader playlist items
    case moveShaderInPhasePlaylist(phase: Phase, fromIndices: [Int], toIndex: Int)

    /// Move mask playlist items
    case moveMaskInPhasePlaylist(phase: Phase, fromIndices: [Int], toIndex: Int)

    /// Activate shader playlist item at index
    case activateShaderInPhasePlaylist(phase: Phase, index: Int)

    /// Activate mask playlist item at index
    case activateMaskInPhasePlaylist(phase: Phase, index: Int)

    /// Advance active shader/mask playlist entries for the phase on song change
    case advancePhasePlaylistsOnSongChange(phase: Phase)

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
    case stateUpdated(ControllerState)

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

    /// Force Launchpad programmer mode
    case forceProgrammerMode

    /// Diagnostic: flash all pads red briefly
    case flashAll

    /// Diagnostic: render rainbow pattern on 8x8 grid
    case rainbowPattern

    /// Diagnostic: clear all pads
    case clearAll

    /// Forward OSC event into Launchpad domain
    case oscEventReceived(OscEvent)
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

    /// Include audio OSC messages in debug capture
    case setOscAudioMessagesEnabled(Bool)

    /// Set OSC filter
    case setOscFilter(String)

    /// Set shader catalog search text
    case setShaderCatalogSearchText(String)

    /// Set shader catalog folder filter
    case setShaderCatalogFolder(String)

    /// Set shader catalog badge filter
    case setShaderCatalogBadgeFilter(ShaderCatalogBadgeFilter)

    /// Set shader catalog phase filter
    case setShaderCatalogPhaseFilter(Phase?)

    /// Set shader catalog sort order
    case setShaderCatalogSortOrder(ShaderCatalogSortOrder)

    /// Set shader catalog view mode
    case setShaderCatalogViewMode(ShaderCatalogViewMode)

    /// Replace shader catalog selection set
    case setShaderCatalogSelection(Set<String>)

    /// Toggle one shader in catalog selection
    case toggleShaderCatalogSelection(String)

    /// Clear shader catalog selection set
    case clearShaderCatalogSelection

    /// Set pending bulk phases for shader catalog
    case setShaderCatalogBulkPhases(Set<Phase>)

    /// Reload Tachikoma configuration in app-layer AI modules
    case reloadTachikomaConfig
}

// MARK: - Launcher Actions

/// Aggregate launch results for batch startup operations.
public struct LauncherLaunchReport: Sendable, Equatable {
    public var launchedTargetIDs: [String]
    public var alreadyRunningTargetIDs: [String]
    public var failedTargetErrors: [String: String]
    public var runningTargetIDs: Set<String>

    public init(
        launchedTargetIDs: [String] = [],
        alreadyRunningTargetIDs: [String] = [],
        failedTargetErrors: [String: String] = [:],
        runningTargetIDs: Set<String> = []
    ) {
        self.launchedTargetIDs = launchedTargetIDs
        self.alreadyRunningTargetIDs = alreadyRunningTargetIDs
        self.failedTargetErrors = failedTargetErrors
        self.runningTargetIDs = runningTargetIDs
    }
}

/// Actions related to controlled app/command launching.
public enum LauncherAction: Sendable {
    /// User dropped one or more file URLs to analyze as launch targets.
    case addAppTargetsRequested([URL])

    /// App-layer analysis produced normalized app targets.
    case appTargetsAnalyzed([LaunchTarget])

    /// Add a command-line launch target.
    case addCommandTargetRequested(commandLine: String, workingDirectory: String?)

    /// Remove an existing launch target.
    case removeTarget(id: String)

    /// Enable/disable startup autostart for a launch target.
    case setAutoStart(id: String, enabled: Bool)

    /// Launch a single target now.
    case launchTargetRequested(id: String)

    /// Launch all configured targets that are not currently running.
    case launchMissingRequested

    /// Launch only autostart-enabled targets that are not running.
    case launchAutoStartRequested

    /// Completion for single-target launch request.
    case launchTargetCompleted(id: String, launched: Bool, error: String?)

    /// Completion for a batch launch request.
    case launchAllCompleted(LauncherLaunchReport)

    /// Clear last launcher error.
    case clearError
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

    /// Start a demo playback for a selected song (UI-triggered test flow)
    case demoPlayRequested(SongID)

    /// Demo playback initialized successfully
    case demoPlayStarted(SongID)

    /// Demo playback failed to start
    case demoPlayFailed(SongID, String)

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
    case songDiscovered(artist: String, title: String, audioFilePath: String? = nil)

    /// Scan completed
    case scanCompleted

    /// Request to cancel ongoing scan (from UI)
    case cancelScanRequested

    /// Scan was cancelled
    case scanCancelled
}

// MARK: - Automation Actions

/// Actions related to per-song timecoded automation and replay.
public enum AutomationAction: Sendable {
    /// Master enable/disable for timeline replay/recording.
    case setEnabled(Bool)

    /// Enable/disable auto-recording from live control actions.
    case setAutoRecordEnabled(Bool)

    /// Update OSC address prefixes used by auto-recording.
    case setAutoRecordPrefixes([String])

    /// Select song in timeline editor.
    case selectSong(SongID?)

    /// Playback track changed - update active runtime song.
    case trackChanged(SongID?)

    /// Playback tick used for deterministic timeline replay.
    case playbackTick(position: Double, isPlaying: Bool)

    /// Ensure timeline object exists for a song.
    case ensureTimeline(SongID)

    /// Replace full timeline for a song.
    case setTimeline(songID: SongID, timeline: SongAutomationTimeline)

    /// Clear all cues/lanes for a song.
    case clearTimeline(SongID)

    /// Add cue to timeline.
    case addCue(songID: SongID, cue: AutomationCue)

    /// Update cue in timeline.
    case updateCue(songID: SongID, cue: AutomationCue)

    /// Remove cue from timeline.
    case removeCue(songID: SongID, cueID: UUID)

    /// Add value lane (for graphs).
    case addValueLane(songID: SongID, lane: AutomationValueLane)

    /// Remove value lane.
    case removeValueLane(songID: SongID, laneID: String)

    /// Add value keyframe point.
    case addValuePoint(songID: SongID, laneID: String, point: AutomationValuePoint)

    /// Update value keyframe point.
    case updateValuePoint(songID: SongID, laneID: String, point: AutomationValuePoint)

    /// Remove value keyframe point.
    case removeValuePoint(songID: SongID, laneID: String, pointID: UUID)

    /// Auto-record LedFX action from UI interaction.
    case recordLedFXAction(songID: SongID, position: Double, action: LedFXAction)

    /// Auto-record outgoing OSC command from any target.
    case recordOSC(
        songID: SongID,
        position: Double,
        target: AutomationOSCTarget,
        address: String,
        args: [AutomationOSCValue],
        source: String?
    )
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
        case .launcher(let action): return "launcher.\(action)"
        case .ledfx(let action): return "ledfx.\(action)"
        case .songs(let action): return "songs.\(action)"
        case .automation(let action): return "automation.\(action)"
        case .moodboard(let action): return "moodboard.\(action)"
        case .preview(let action): return "preview.\(action)"
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
        case .demoTrackChanged(let track): return "demoTrackChanged(\(track.artist) - \(track.title))"
        case .positionUpdated(let pos, let playing): return "positionUpdated(\(String(format: "%.1f", pos)), playing: \(playing))"
        case .sourceChanged(let source): return "sourceChanged(\(source))"
        case .playingStateChanged(let playing): return "playingStateChanged(\(playing))"
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
        case .toggleStepExpansion(let step): return "toggleStepExpansion(\(step))"
        }
    }
}

extension RenderAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .setEnabled(let enabled): return "setEnabled(\(enabled))"
        case .setOutputEnabled(let output, let enabled): return "setOutputEnabled(\(output.rawValue), \(enabled))"
        case .selectShader(let name): return "selectShader(\(name))"
        case .selectMaskShader(let name): return "selectMaskShader(\(name))"
        case .shaderSelected(let name): return "shaderSelected(\(name))"
        case .maskShaderSelected(let name): return "maskShaderSelected(\(name))"
        case .selectNextShader: return "selectNextShader"
        case .selectPreviousShader: return "selectPreviousShader"
        case .selectRandomShader: return "selectRandomShader"
        case .selectNextMaskShader: return "selectNextMaskShader"
        case .selectPreviousMaskShader: return "selectPreviousMaskShader"
        case .selectRandomMaskShader: return "selectRandomMaskShader"
        case .selectPhase(let phase): return "selectPhase(\(phase?.rawValue ?? "auto"))"
        case .phaseDetected(let phase): return "phaseDetected(\(phase?.rawValue ?? "none"))"
        case .setImageIndex(let index): return "setImageIndex(\(index))"
        case .nextImage: return "nextImage"
        case .prevImage: return "prevImage"
        case .imagesLoaded(let count, _): return "imagesLoaded(\(count))"
        case .shaderCountUpdated(let count): return "shaderCountUpdated(\(count))"
        case .setShaderWorkspaceControls(let shaderName, let controls):
            return "setShaderWorkspaceControls(\(shaderName), bin0: \(String(format: "%.2f", controls.bin0)), bin1: \(String(format: "%.2f", controls.bin1)), bin2: \(String(format: "%.2f", controls.bin2)), zoom: \(String(format: "%.2f", controls.zoom)))"
        case .resetShaderWorkspaceControls(let shaderName): return "resetShaderWorkspaceControls(\(shaderName))"
        case .setShaderAutoAdvanceOnSongChange(let enabled): return "setShaderAutoAdvanceOnSongChange(\(enabled))"
        case .setMaskAutoAdvanceOnSongChange(let enabled): return "setMaskAutoAdvanceOnSongChange(\(enabled))"
        case .setAISuggestedShader(let name, let phase):
            return "setAISuggestedShader(\(name ?? "nil"), phase: \(phase?.rawValue ?? "nil"))"
        case .addShaderToPhasePlaylist(let phase, let shaderName, let activate):
            return "addShaderToPhasePlaylist(\(phase.rawValue), \(shaderName), activate: \(activate))"
        case .addMaskToPhasePlaylist(let phase, let maskName, let activate):
            return "addMaskToPhasePlaylist(\(phase.rawValue), \(maskName), activate: \(activate))"
        case .removeShaderFromPhasePlaylist(let phase, let index):
            return "removeShaderFromPhasePlaylist(\(phase.rawValue), index: \(index))"
        case .removeMaskFromPhasePlaylist(let phase, let index):
            return "removeMaskFromPhasePlaylist(\(phase.rawValue), index: \(index))"
        case .moveShaderInPhasePlaylist(let phase, let fromIndices, let toIndex):
            return "moveShaderInPhasePlaylist(\(phase.rawValue), from: \(fromIndices), to: \(toIndex))"
        case .moveMaskInPhasePlaylist(let phase, let fromIndices, let toIndex):
            return "moveMaskInPhasePlaylist(\(phase.rawValue), from: \(fromIndices), to: \(toIndex))"
        case .activateShaderInPhasePlaylist(let phase, let index):
            return "activateShaderInPhasePlaylist(\(phase.rawValue), index: \(index))"
        case .activateMaskInPhasePlaylist(let phase, let index):
            return "activateMaskInPhasePlaylist(\(phase.rawValue), index: \(index))"
        case .advancePhasePlaylistsOnSongChange(let phase):
            return "advancePhasePlaylistsOnSongChange(\(phase.rawValue))"
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
        case .forceProgrammerMode: return "forceProgrammerMode"
        case .flashAll: return "flashAll"
        case .rainbowPattern: return "rainbowPattern"
        case .clearAll: return "clearAll"
        case .oscEventReceived(let event): return "oscEventReceived(\(event.address))"
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
        case .setOscAudioMessagesEnabled(let enabled): return "setOscAudioMessagesEnabled(\(enabled))"
        case .setOscFilter(let filter): return "setOscFilter(\(filter))"
        case .setShaderCatalogSearchText(let query): return "setShaderCatalogSearchText(\(query))"
        case .setShaderCatalogFolder(let folder): return "setShaderCatalogFolder(\(folder))"
        case .setShaderCatalogBadgeFilter(let filter): return "setShaderCatalogBadgeFilter(\(filter.rawValue))"
        case .setShaderCatalogPhaseFilter(let phase): return "setShaderCatalogPhaseFilter(\(phase?.rawValue ?? "all"))"
        case .setShaderCatalogSortOrder(let order): return "setShaderCatalogSortOrder(\(order.rawValue))"
        case .setShaderCatalogViewMode(let mode): return "setShaderCatalogViewMode(\(mode.rawValue))"
        case .setShaderCatalogSelection(let names): return "setShaderCatalogSelection(\(names.count))"
        case .toggleShaderCatalogSelection(let name): return "toggleShaderCatalogSelection(\(name))"
        case .clearShaderCatalogSelection: return "clearShaderCatalogSelection"
        case .setShaderCatalogBulkPhases(let phases): return "setShaderCatalogBulkPhases(\(phases.count))"
        case .reloadTachikomaConfig: return "reloadTachikomaConfig"
        }
    }
}

extension LauncherAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .addAppTargetsRequested(let urls): return "addAppTargetsRequested(\(urls.count))"
        case .appTargetsAnalyzed(let targets): return "appTargetsAnalyzed(\(targets.count))"
        case .addCommandTargetRequested(let commandLine, let workingDirectory):
            let cwd = workingDirectory ?? "-"
            return "addCommandTargetRequested(\(commandLine), cwd: \(cwd))"
        case .removeTarget(let id): return "removeTarget(\(id))"
        case .setAutoStart(let id, let enabled): return "setAutoStart(\(id), \(enabled))"
        case .launchTargetRequested(let id): return "launchTargetRequested(\(id))"
        case .launchMissingRequested: return "launchMissingRequested"
        case .launchAutoStartRequested: return "launchAutoStartRequested"
        case .launchTargetCompleted(let id, let launched, let error):
            if let error { return "launchTargetCompleted(\(id), launched: \(launched), error: \(error))" }
            return "launchTargetCompleted(\(id), launched: \(launched))"
        case .launchAllCompleted(let report):
            return "launchAllCompleted(launched: \(report.launchedTargetIDs.count), failed: \(report.failedTargetErrors.count))"
        case .clearError: return "clearError"
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
        case .demoPlayRequested(let id): return "demoPlayRequested(\(id.rawValue))"
        case .demoPlayStarted(let id): return "demoPlayStarted(\(id.rawValue))"
        case .demoPlayFailed(let id, let reason): return "demoPlayFailed(\(id.rawValue), \(reason))"
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
        case .songDiscovered(let artist, let title, _): return "songDiscovered(\(artist) - \(title))"
        case .scanCompleted: return "scanCompleted"
        case .cancelScanRequested: return "cancelScanRequested"
        case .scanCancelled: return "scanCancelled"
        }
    }
}

extension AutomationAction: CustomStringConvertible {
    public var description: String {
        switch self {
        case .setEnabled(let enabled): return "setEnabled(\(enabled))"
        case .setAutoRecordEnabled(let enabled): return "setAutoRecordEnabled(\(enabled))"
        case .setAutoRecordPrefixes(let prefixes): return "setAutoRecordPrefixes(\(prefixes.count))"
        case .selectSong(let id): return "selectSong(\(id?.rawValue ?? "none"))"
        case .trackChanged(let id): return "trackChanged(\(id?.rawValue ?? "none"))"
        case .playbackTick(let position, let isPlaying):
            return "playbackTick(\(String(format: "%.2f", position)), playing: \(isPlaying))"
        case .ensureTimeline(let songID): return "ensureTimeline(\(songID.rawValue))"
        case .setTimeline(let songID, _): return "setTimeline(\(songID.rawValue))"
        case .clearTimeline(let songID): return "clearTimeline(\(songID.rawValue))"
        case .addCue(let songID, let cue): return "addCue(\(songID.rawValue), \(cue.actionType.rawValue), t:\(String(format: "%.2f", cue.timeSec)))"
        case .updateCue(let songID, let cue): return "updateCue(\(songID.rawValue), \(cue.id.uuidString))"
        case .removeCue(let songID, let cueID): return "removeCue(\(songID.rawValue), \(cueID.uuidString))"
        case .addValueLane(let songID, let lane): return "addValueLane(\(songID.rawValue), \(lane.id))"
        case .removeValueLane(let songID, let laneID): return "removeValueLane(\(songID.rawValue), \(laneID))"
        case .addValuePoint(let songID, let laneID, let point):
            return "addValuePoint(\(songID.rawValue), \(laneID), t:\(String(format: "%.2f", point.timeSec)), v:\(String(format: "%.2f", point.value)))"
        case .updateValuePoint(let songID, let laneID, let point):
            return "updateValuePoint(\(songID.rawValue), \(laneID), \(point.id.uuidString))"
        case .removeValuePoint(let songID, let laneID, let pointID):
            return "removeValuePoint(\(songID.rawValue), \(laneID), \(pointID.uuidString))"
        case .recordLedFXAction(let songID, let position, let action):
            return "recordLedFXAction(\(songID.rawValue), t:\(String(format: "%.2f", position)), \(action))"
        case .recordOSC(let songID, let position, let target, let address, _, let source):
            return "recordOSC(\(songID.rawValue), t:\(String(format: "%.2f", position)), \(target.rawValue), \(address), src: \(source ?? "-"))"
        }
    }
}

// MARK: - Moodboard Actions

import SongRepository

/// Actions for the moodboard visual song graph canvas.
public enum MoodboardAction: Sendable {
    // MARK: Canvas Lifecycle
    /// Load the moodboard graph from song data
    case loadFromSongs
    /// Canvas data loaded from songs and connections
    case canvasLoaded(nodes: [MoodboardNode], edges: [MoodboardEdge], connections: [SongConnection], phaseEdges: [PhaseFlowEdge], positions: [CanvasPositionEntry])

    // MARK: Node Operations
    /// Add a song to the canvas at a position
    case addSongNode(SongID, position: CGPoint)
    /// Remove a node from the canvas
    case removeNode(String)
    /// Move a single node to a new position
    case moveNode(String, to: CGPoint)
    /// Batch move multiple nodes (drag selection)
    case moveNodes([(String, CGPoint)])

    // MARK: Edge Operations
    /// Create an explicit connection between two songs
    case connectNodes(sourceId: String, targetId: String, edgeType: EdgeType, weight: Double)
    /// Remove an edge
    case removeEdge(String)
    /// Update an edge's weight
    case updateEdgeWeight(String, weight: Double)

    // MARK: Phase Flow
    /// Add a phase flow edge
    case addPhaseEdge(from: String, to: String, weight: Double)
    /// Remove a phase flow edge
    case removePhaseEdge(from: String, to: String)
    /// Auto-suggest phase flow from existing phases
    case suggestPhaseFlow
    /// Phase flow was updated (from effect)
    case phaseFlowUpdated([PhaseFlowEdge], order: [String])
    /// Filter canvas to show only songs in a phase (nil = show all)
    case filterByPhase(String?)

    // MARK: Tag Operations
    /// Add a tag to a song (triggers graph rebuild)
    case addTagToSong(SongID, label: String, category: TagCategory)
    /// Remove a tag from a song (triggers graph rebuild)
    case removeTagFromSong(SongID, label: String, category: TagCategory)
    /// Graph was rebuilt after tag/connection change
    case graphRebuilt(nodes: [MoodboardNode], edges: [MoodboardEdge])

    // MARK: Viewport
    /// Viewport changed (pan/zoom)
    case viewportChanged(ViewportState)
    /// Save canvas positions (debounced)
    case saveCanvasPositions
    /// Canvas positions saved
    case canvasPositionsSaved

    // MARK: Selection
    /// Select nodes (replaces selection)
    case selectNodes(Set<String>)
    /// Select edges (replaces selection)
    case selectEdges(Set<String>)

    // MARK: UI Panels
    /// Toggle the library panel
    case toggleLibraryPanel
    /// Show song detail for a song (nil = hide)
    case showSongDetail(SongID?)

    // MARK: Board Management
    /// Save the current board with a name
    case saveBoard(name: String)
    /// Board was saved successfully
    case boardSaved(MoodboardBoardSummary)
    /// Load a saved board by ID
    case loadBoard(id: String)
    /// Board was loaded successfully
    case boardLoaded(MoodboardBoard)
    /// Delete a saved board by ID
    case deleteBoard(id: String)
    /// Board was deleted
    case boardDeleted(id: String)
    /// Load the list of saved boards
    case loadBoardList
    /// Board list was loaded
    case boardListLoaded([MoodboardBoardSummary])
    /// Create a new empty board
    case newBoard

    // MARK: Tag Node Operations
    /// Add a standalone tag node to the canvas (genre, mood, or phase)
    case addTagNode(label: String, category: TagCategory, position: CGPoint)
    /// Remove a tag node from the canvas
    case removeTagNode(String)

    // MARK: Edge Drawing
    /// Start drawing an edge from a node's handle
    case startDrawingEdge(sourceId: String)
    /// Update the drawing endpoint as mouse moves
    case updateDrawingEdge(endPoint: CGPoint)
    /// Complete edge drawing by dropping on a target node
    case finishDrawingEdge(targetId: String)
    /// Cancel edge drawing
    case cancelDrawingEdge

    // MARK: Tag Manager
    /// Toggle the tag manager panel
    case toggleTagManagerPanel
    /// Merge sourceTagId into targetTagId: re-point all edges, remove source
    case mergeTags(sourceTagId: String, targetTagId: String)
    /// Select all song nodes connected to a tag node
    case selectSongsForTag(tagNodeId: String)
    /// Move viewport to center on a tag and its connected songs
    case focusOnTag(tagNodeId: String)
    /// Rename a tag node
    case renameTag(tagNodeId: String, newLabel: String)

    // MARK: Layout
    /// Apply an auto-layout algorithm to all nodes
    case applyLayout(LayoutMode)
    /// Fit viewport to show all nodes
    case fitViewport
    /// Remove all selected nodes and edges
    case removeSelected
}

// MARK: - Preview Actions

/// Actions for song preview playback
public enum PreviewAction: Sendable {
    /// Start playing a song preview
    case play(SongID)
    /// Pause current preview
    case pause
    /// Resume paused preview
    case resume
    /// Stop preview and reset state
    case stop
    /// Seek to absolute position in seconds
    case seekTo(Double)
    /// Set the start offset for previews in seconds
    case setPreviewStartSeconds(Int)
    /// Position update from audio adapter (position in seconds, total duration)
    case positionUpdated(position: Double, duration: Double)
    /// Playback reached end of track
    case playbackFinished
}

// AppState.swift - Immutable application state for unidirectional data flow
// Single source of truth for all application data

import Foundation
import SongRepository

// MARK: - Root App State

/// Root application state - immutable snapshot of all app data.
///
/// This is the single source of truth for the entire application.
/// State is organized into logical sub-states for clarity.
public struct AppState: Equatable, Sendable {
    /// Playback state (current track, position, source)
    public var playback: PlaybackSubState

    /// Pipeline processing state (steps, results)
    public var pipeline: PipelineSubState

    /// Rendering state (shaders, phases, images)
    public var render: RenderSubState

    /// Launchpad controller state
    public var launchpad: LaunchpadSubState

    /// Audio state (levels, BPM, beat phase)
    public var audio: AudioSubState

    /// UI state (logs, OSC debug, settings)
    public var ui: UISubState

    /// Controlled app/command launcher state
    public var launcher: LauncherSubState

    /// LedFX integration state
    public var ledfx: LedFXSubState

    /// Songs management state
    public var songs: SongsSubState

    /// Whether the system is running
    public var isRunning: Bool

    /// Module references for legacy effect execution.
    ///
    /// - Note: Side effects are now handled via `EffectEnvironment` singleton.
    ///   This struct remains for backward compatibility but should be phased out
    ///   as more effects migrate to the environment pattern.
    ///
    /// - Important: `ModuleReferences` is excluded from `Equatable` conformance
    ///   to prevent spurious state change notifications.
    public var modules: ModuleReferences

    public init(
        playback: PlaybackSubState = PlaybackSubState(),
        pipeline: PipelineSubState = PipelineSubState(),
        render: RenderSubState = RenderSubState(),
        launchpad: LaunchpadSubState = LaunchpadSubState(),
        audio: AudioSubState = AudioSubState(),
        ui: UISubState = UISubState(),
        launcher: LauncherSubState = LauncherSubState(),
        ledfx: LedFXSubState = LedFXSubState(),
        songs: SongsSubState = SongsSubState(),
        isRunning: Bool = false,
        modules: ModuleReferences = ModuleReferences()
    ) {
        self.playback = playback
        self.pipeline = pipeline
        self.render = render
        self.launchpad = launchpad
        self.audio = audio
        self.ui = ui
        self.launcher = launcher
        self.ledfx = ledfx
        self.songs = songs
        self.isRunning = isRunning
        self.modules = modules
    }

    // Equatable excludes module references (they're not value types)
    public static func == (lhs: AppState, rhs: AppState) -> Bool {
        lhs.playback == rhs.playback &&
        lhs.pipeline == rhs.pipeline &&
        lhs.render == rhs.render &&
        lhs.launchpad == rhs.launchpad &&
        lhs.audio == rhs.audio &&
        lhs.ui == rhs.ui &&
        lhs.launcher == rhs.launcher &&
        lhs.ledfx == rhs.ledfx &&
        lhs.songs == rhs.songs &&
        lhs.isRunning == rhs.isRunning
    }
}

// MARK: - Playback Sub-State

/// Playback-related state
public struct PlaybackSubState: Equatable, Sendable {
    /// Currently playing track
    public var currentTrack: Track?

    /// Current playback position in seconds
    public var position: Double

    /// Whether audio is currently playing
    public var isPlaying: Bool

    /// Playback source (vdj, spotify)
    public var source: String

    public init(
        currentTrack: Track? = nil,
        position: Double = 0,
        isPlaying: Bool = false,
        source: String = "vdj"
    ) {
        self.currentTrack = currentTrack
        self.position = position
        self.isPlaying = isPlaying
        self.source = source
    }
}

// MARK: - Pipeline Sub-State

/// Pipeline processing state
public struct PipelineSubState: Equatable, Sendable {
    /// Current pipeline step states
    public var steps: [PipelineStepState]

    /// Latest pipeline result
    public var result: PipelineResult?

    /// Whether pipeline is currently processing
    public var isProcessing: Bool

    /// Current processing track key (for deduplication)
    public var processingTrackKey: String?

    /// Last error if processing failed
    public var error: String?

    /// Expanded/collapsed state of step rows in Pipeline UI (single source of truth)
    public var expandedStepNames: Set<String>

    public init(
        steps: [PipelineStepState] = PipelineStepState.defaultSteps,
        result: PipelineResult? = nil,
        isProcessing: Bool = false,
        processingTrackKey: String? = nil,
        error: String? = nil,
        expandedStepNames: Set<String> = []
    ) {
        self.steps = steps
        self.result = result
        self.isProcessing = isProcessing
        self.processingTrackKey = processingTrackKey
        self.error = error
        self.expandedStepNames = expandedStepNames
    }

    /// Update a specific step
    public mutating func updateStep(_ name: String, status: String, details: [String]? = nil) {
        if let index = steps.firstIndex(where: { $0.name == name }) {
            steps[index] = PipelineStepState(
                name: name,
                status: status,
                details: details,
                timestamp: Date()
            )
        }
    }

    /// Reset all steps to pending
    public mutating func resetSteps() {
        steps = PipelineStepState.defaultSteps
    }

    /// Toggle expansion state for a given step name
    public mutating func toggleStepExpansion(_ stepName: String) {
        if expandedStepNames.contains(stepName) {
            expandedStepNames.remove(stepName)
        } else {
            expandedStepNames.insert(stepName)
        }
    }
}

/// State of a single pipeline step
public struct PipelineStepState: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var status: String
    public var details: [String]?
    public var timestamp: Date

    public init(
        id: UUID = UUID(),
        name: String,
        status: String = "pending",
        details: [String]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.details = details
        self.timestamp = timestamp
    }

    /// Default pipeline steps
    public static let defaultSteps: [PipelineStepState] = [
        PipelineStepState(name: "lyrics", status: "pending"),
        PipelineStepState(name: "ai", status: "pending"),
        PipelineStepState(name: "shaders", status: "pending"),
        PipelineStepState(name: "images", status: "pending"),
        PipelineStepState(name: "osc", status: "pending")
    ]
}

// MARK: - Render Sub-State

public enum RenderOutput: String, CaseIterable, Codable, Sendable {
    case shader
    case mask
    case lyrics
    case refrain
    case songInfo
    case image

    public var displayName: String {
        switch self {
        case .songInfo:
            return "Song Info"
        default:
            return rawValue.capitalized
        }
    }
}

public struct RenderOutputsState: Equatable, Codable, Sendable {
    public var shader: Bool
    public var mask: Bool
    public var lyrics: Bool
    public var refrain: Bool
    public var songInfo: Bool
    public var image: Bool

    public init(
        shader: Bool = true,
        mask: Bool = true,
        lyrics: Bool = true,
        refrain: Bool = true,
        songInfo: Bool = true,
        image: Bool = true
    ) {
        self.shader = shader
        self.mask = mask
        self.lyrics = lyrics
        self.refrain = refrain
        self.songInfo = songInfo
        self.image = image
    }

    public func isEnabled(_ output: RenderOutput) -> Bool {
        switch output {
        case .shader: return shader
        case .mask: return mask
        case .lyrics: return lyrics
        case .refrain: return refrain
        case .songInfo: return songInfo
        case .image: return image
        }
    }

    public mutating func setEnabled(_ enabled: Bool, for output: RenderOutput) {
        switch output {
        case .shader: shader = enabled
        case .mask: mask = enabled
        case .lyrics: lyrics = enabled
        case .refrain: refrain = enabled
        case .songInfo: songInfo = enabled
        case .image: image = enabled
        }
    }

    public var hasAnyTextOutputEnabled: Bool {
        lyrics || refrain || songInfo
    }
}

public struct ShaderWorkspaceControls: Equatable, Codable, Sendable {
    public var bin0: Float
    public var bin1: Float
    public var bin2: Float
    public var zoom: Float

    public init(
        bin0: Float = 0,
        bin1: Float = 0,
        bin2: Float = 0,
        zoom: Float = 1
    ) {
        self.bin0 = bin0
        self.bin1 = bin1
        self.bin2 = bin2
        self.zoom = zoom
    }

    public static let `default` = ShaderWorkspaceControls()
}

/// Rendering-related state
public struct RenderSubState: Equatable, Sendable {
    /// Whether rendering and Syphon output are enabled
    public var isEnabled: Bool

    /// Per-output enablement for Syphon/render tiles
    public var outputs: RenderOutputsState

    /// Currently selected shader name
    public var selectedShader: String?

    /// Currently selected mask shader name
    public var selectedMaskShader: String?

    /// Current set phase (nil = auto)
    public var currentPhase: Phase?

    /// Detected phase from song analysis
    public var detectedSongPhase: Phase?

    /// Current image index in folder
    public var imageIndex: Int

    /// Total images in current folder
    public var imageCount: Int

    /// Available shader count
    public var shaderCount: Int

    /// Per-shader workspace controls (bin0/bin1/bin2/zoom)
    public var shaderControlsByShader: [String: ShaderWorkspaceControls]

    /// Effective phase (manual or detected)
    public var effectivePhase: Phase? {
        currentPhase ?? detectedSongPhase
    }

    public init(
        isEnabled: Bool = true,
        outputs: RenderOutputsState = RenderOutputsState(),
        selectedShader: String? = nil,
        selectedMaskShader: String? = nil,
        currentPhase: Phase? = nil,
        detectedSongPhase: Phase? = nil,
        imageIndex: Int = 0,
        imageCount: Int = 0,
        shaderCount: Int = 0,
        shaderControlsByShader: [String: ShaderWorkspaceControls] = [:]
    ) {
        self.isEnabled = isEnabled
        self.outputs = outputs
        self.selectedShader = selectedShader
        self.selectedMaskShader = selectedMaskShader
        self.currentPhase = currentPhase
        self.detectedSongPhase = detectedSongPhase
        self.imageIndex = imageIndex
        self.imageCount = imageCount
        self.shaderCount = shaderCount
        self.shaderControlsByShader = shaderControlsByShader
    }

    public func shaderControls(for shaderName: String?) -> ShaderWorkspaceControls {
        guard let shaderName else { return .default }
        return shaderControlsByShader[shaderName] ?? .default
    }
}

// MARK: - Launchpad Sub-State

/// Launchpad controller state
public struct LaunchpadSubState: Equatable, Sendable {
    /// Whether Launchpad is connected
    public var isConnected: Bool

    /// Connected device name
    public var deviceName: String?

    /// Current bank (0-7)
    public var currentBank: Int

    /// Full controller state (single source of truth for Launchpad UI)
    public var controllerState: ControllerState?

    /// Monotonic revision for controllerState updates (lets app layer avoid stale comparisons)
    public var controllerRevision: UInt64

    /// Connection status for UI
    public var status: LaunchpadStatusSnapshot?

    public init(
        isConnected: Bool = false,
        deviceName: String? = nil,
        currentBank: Int = 0,
        controllerState: ControllerState? = nil,
        controllerRevision: UInt64 = 0,
        status: LaunchpadStatusSnapshot? = nil
    ) {
        self.isConnected = isConnected
        self.deviceName = deviceName
        self.currentBank = currentBank
        self.controllerState = controllerState
        self.controllerRevision = controllerRevision
        self.status = status
    }

    public static func == (lhs: LaunchpadSubState, rhs: LaunchpadSubState) -> Bool {
        let lhsSnapshot = lhs.controllerState.map(ControllerStateSnapshot.init(from:))
        let rhsSnapshot = rhs.controllerState.map(ControllerStateSnapshot.init(from:))
        return lhs.isConnected == rhs.isConnected &&
            lhs.deviceName == rhs.deviceName &&
            lhs.currentBank == rhs.currentBank &&
            lhs.controllerRevision == rhs.controllerRevision &&
            lhs.status == rhs.status &&
            lhsSnapshot == rhsSnapshot
    }
}

/// Simplified snapshot of controller state for state comparison
public struct ControllerStateSnapshot: Equatable, Sendable {
    public var activeBank: Int
    public var activeScene: String?
    public var activePreset: String?
    public var learnPhase: String

    public init(
        activeBank: Int = 0,
        activeScene: String? = nil,
        activePreset: String? = nil,
        learnPhase: String = "idle"
    ) {
        self.activeBank = activeBank
        self.activeScene = activeScene
        self.activePreset = activePreset
        self.learnPhase = learnPhase
    }

    public init(from state: ControllerState) {
        self.activeBank = state.activeBank
        self.activeScene = state.activeScene
        self.activePreset = state.activePreset
        self.learnPhase = String(describing: state.learnState.phase)
    }
}

/// Simplified snapshot of launchpad status
public struct LaunchpadStatusSnapshot: Equatable, Sendable {
    public var isConnected: Bool
    public var deviceName: String?
    public var activeBank: Int
    public var padCount: Int
    public var isLearnMode: Bool

    public init(
        isConnected: Bool = false,
        deviceName: String? = nil,
        activeBank: Int = 0,
        padCount: Int = 0,
        isLearnMode: Bool = false
    ) {
        self.isConnected = isConnected
        self.deviceName = deviceName
        self.activeBank = activeBank
        self.padCount = padCount
        self.isLearnMode = isLearnMode
    }

    public init(from status: LaunchpadStatus) {
        self.isConnected = status.isConnected
        self.deviceName = status.deviceName
        self.activeBank = 0  // LaunchpadStatus doesn't track activeBank
        self.padCount = status.configuredPadCount
        self.isLearnMode = status.isLearnMode
    }
}

// MARK: - Audio Sub-State

/// Audio processing state
public struct AudioSubState: Equatable, Sendable {
    /// Current audio level (0.0 - 1.0)
    public var level: Float

    /// Beat phase (0.0 - 1.0)
    public var beatPhase: Float

    /// Detected BPM
    public var bpm: Float

    /// Energy level (0.0 - 1.0)
    public var energy: Float

    /// Bass level
    public var bass: Float

    /// Mid level
    public var mid: Float

    /// High level
    public var high: Float

    public init(
        level: Float = 0,
        beatPhase: Float = 0,
        bpm: Float = 0,
        energy: Float = 0,
        bass: Float = 0,
        mid: Float = 0,
        high: Float = 0
    ) {
        self.level = level
        self.beatPhase = beatPhase
        self.bpm = bpm
        self.energy = energy
        self.bass = bass
        self.mid = mid
        self.high = high
    }
}

// MARK: - UI Sub-State

/// Badge filter options for shader catalog workflow
public enum ShaderCatalogBadgeFilter: String, CaseIterable, Codable, Sendable {
    case all = "All"
    case black = "Black"
    case monochromatic = "Monochromatic"
    case analyzed = "Analyzed"
    case notAnalyzed = "Not Analyzed"
}

/// Sort options for shader catalog workflow
public enum ShaderCatalogSortOrder: String, CaseIterable, Codable, Sendable {
    case name = "Name"
    case unanalyzedFirst = "Unanalyzed First"
    case phaseCoverage = "Phase Coverage"
}

/// Display mode for shader catalog workflow
public enum ShaderCatalogViewMode: String, CaseIterable, Codable, Sendable {
    case grid = "Grid"
    case list = "List"
}

/// UI state for shader browsing and curation workflow.
public struct ShaderCatalogSubState: Equatable, Sendable {
    public var searchText: String
    public var selectedFolder: String
    public var badgeFilter: ShaderCatalogBadgeFilter
    public var phaseFilter: Phase?
    public var sortOrder: ShaderCatalogSortOrder
    public var viewMode: ShaderCatalogViewMode
    public var selectedShaders: Set<String>
    public var bulkPhases: Set<Phase>

    public init(
        searchText: String = "",
        selectedFolder: String = "ALL",
        badgeFilter: ShaderCatalogBadgeFilter = .all,
        phaseFilter: Phase? = nil,
        sortOrder: ShaderCatalogSortOrder = .name,
        viewMode: ShaderCatalogViewMode = .grid,
        selectedShaders: Set<String> = [],
        bulkPhases: Set<Phase> = []
    ) {
        self.searchText = searchText
        self.selectedFolder = selectedFolder
        self.badgeFilter = badgeFilter
        self.phaseFilter = phaseFilter
        self.sortOrder = sortOrder
        self.viewMode = viewMode
        self.selectedShaders = selectedShaders
        self.bulkPhases = bulkPhases
    }

    public mutating func toggleSelection(_ shaderName: String) {
        if selectedShaders.contains(shaderName) {
            selectedShaders.remove(shaderName)
        } else {
            selectedShaders.insert(shaderName)
        }
    }
}

/// UI-related state
public struct UISubState: Equatable, Sendable {
    /// Log entries
    public var logEntries: [LogEntryState]

    /// OSC messages (grouped by address)
    public var oscMessages: [String: OSCLogEntryState]

    /// OSC message count
    public var oscMessageCount: Int

    /// OSC filter string
    public var oscFilter: String

    /// Whether OSC debug is enabled
    public var oscDebugEnabled: Bool

    /// Shader catalog UI workflow state
    public var shaderCatalog: ShaderCatalogSubState

    /// Maximum log entries to keep
    public static let maxLogEntries = 500

    public init(
        logEntries: [LogEntryState] = [],
        oscMessages: [String: OSCLogEntryState] = [:],
        oscMessageCount: Int = 0,
        oscFilter: String = "",
        oscDebugEnabled: Bool = false,
        shaderCatalog: ShaderCatalogSubState = ShaderCatalogSubState()
    ) {
        self.logEntries = logEntries
        self.oscMessages = oscMessages
        self.oscMessageCount = oscMessageCount
        self.oscFilter = oscFilter
        self.oscDebugEnabled = oscDebugEnabled
        self.shaderCatalog = shaderCatalog
    }

    /// Add a log entry, trimming old entries if needed
    public mutating func addLog(_ message: String, level: LogLevelState) {
        let entry = LogEntryState(message: message, level: level, timestamp: Date())
        logEntries.append(entry)
        if logEntries.count > Self.maxLogEntries {
            logEntries.removeFirst(logEntries.count - Self.maxLogEntries)
        }
    }

    /// Record an OSC message
    public mutating func recordOSC(_ address: String, args: [String]) {
        guard oscDebugEnabled else { return }
        guard oscFilter.isEmpty || address.localizedCaseInsensitiveContains(oscFilter) else { return }
        let entry = OSCLogEntryState(address: address, args: args, timestamp: Date())
        oscMessages[address] = entry
        oscMessageCount += 1
    }
}

// MARK: - Launcher Sub-State

/// A user-configured launch target for either a macOS app bundle or command line.
public struct LaunchTarget: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, Equatable {
        case app
        case command
    }

    public var id: String
    public var kind: Kind
    public var displayName: String
    public var autoStart: Bool

    /// App target fields
    public var appBundleIdentifier: String?
    public var appPath: String?

    /// Command target fields
    public var commandLine: String?
    public var workingDirectory: String?

    public init(
        id: String,
        kind: Kind,
        displayName: String,
        autoStart: Bool = false,
        appBundleIdentifier: String? = nil,
        appPath: String? = nil,
        commandLine: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.autoStart = autoStart
        self.appBundleIdentifier = appBundleIdentifier
        self.appPath = appPath
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
    }

    public var normalizedIdentity: String {
        switch kind {
        case .app:
            if let bundle = appBundleIdentifier?.lowercased(), !bundle.isEmpty {
                return "app.bundle:\(bundle)"
            }
            let app = (appPath ?? "").lowercased()
            return "app.path:\(app)"
        case .command:
            let cmd = (commandLine ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let cwd = (workingDirectory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "cmd:\(cmd)|cwd:\(cwd)"
        }
    }

    public static func appTarget(
        id: String,
        displayName: String,
        bundleIdentifier: String?,
        appPath: String
    ) -> LaunchTarget {
        LaunchTarget(
            id: id,
            kind: .app,
            displayName: displayName,
            autoStart: false,
            appBundleIdentifier: bundleIdentifier,
            appPath: appPath
        )
    }

    public static func commandTarget(
        id: String,
        displayName: String,
        commandLine: String,
        workingDirectory: String?
    ) -> LaunchTarget {
        LaunchTarget(
            id: id,
            kind: .command,
            displayName: displayName,
            autoStart: false,
            commandLine: commandLine,
            workingDirectory: workingDirectory
        )
    }
}

/// Launcher domain state used by Master page launch controls.
public struct LauncherSubState: Equatable, Sendable {
    public var targets: [LaunchTarget]
    public var runningTargetIDs: Set<String>
    public var isLaunchingAll: Bool
    public var lastError: String?
    public var lastLaunchSummary: String?
    public var revision: UInt64

    public init(
        targets: [LaunchTarget] = [],
        runningTargetIDs: Set<String> = [],
        isLaunchingAll: Bool = false,
        lastError: String? = nil,
        lastLaunchSummary: String? = nil,
        revision: UInt64 = 0
    ) {
        self.targets = targets
        self.runningTargetIDs = runningTargetIDs
        self.isLaunchingAll = isLaunchingAll
        self.lastError = lastError
        self.lastLaunchSummary = lastLaunchSummary
        self.revision = revision
    }
}

// MARK: - LedFX Sub-State

/// LedFX integration state for UI and bridge config
public struct LedFXSubState: Equatable, Sendable {
    public var baseURL: String
    public var virtualIdsString: String
    public var isRefreshing: Bool
    public var isApplying: Bool
    public var isGeneratingConfig: Bool
    public var serverInfo: LedFXInfo?
    public var scenes: [String: LedFXScene]
    public var virtuals: [String: LedFXVirtual]
    public var playlists: [String: LedFXPlaylist]
    public var activePlaylistId: String?
    public var sceneFilter: String
    public var playlistFilter: String
    public var errorMessage: String?
    public var generatedYaml: String?
    public var playlistCount: Int
    public var effectsCount: Int
    public var isRunning: Bool
    public var healthSummary: String
    public var lastHealthCheck: Date?
    public var revision: UInt64

    public init(
        baseURL: String = "http://127.0.0.1:8888",
        virtualIdsString: String = "",
        isRefreshing: Bool = false,
        isApplying: Bool = false,
        isGeneratingConfig: Bool = false,
        serverInfo: LedFXInfo? = nil,
        scenes: [String: LedFXScene] = [:],
        virtuals: [String: LedFXVirtual] = [:],
        playlists: [String: LedFXPlaylist] = [:],
        activePlaylistId: String? = nil,
        sceneFilter: String = "",
        playlistFilter: String = "",
        errorMessage: String? = nil,
        generatedYaml: String? = nil,
        playlistCount: Int = 0,
        effectsCount: Int = 0,
        isRunning: Bool = false,
        healthSummary: String = "Unknown",
        lastHealthCheck: Date? = nil,
        revision: UInt64 = 0
    ) {
        self.baseURL = baseURL
        self.virtualIdsString = virtualIdsString
        self.isRefreshing = isRefreshing
        self.isApplying = isApplying
        self.isGeneratingConfig = isGeneratingConfig
        self.serverInfo = serverInfo
        self.scenes = scenes
        self.virtuals = virtuals
        self.playlists = playlists
        self.activePlaylistId = activePlaylistId
        self.sceneFilter = sceneFilter
        self.playlistFilter = playlistFilter
        self.errorMessage = errorMessage
        self.generatedYaml = generatedYaml
        self.playlistCount = playlistCount
        self.effectsCount = effectsCount
        self.isRunning = isRunning
        self.healthSummary = healthSummary
        self.lastHealthCheck = lastHealthCheck
        self.revision = revision
    }
}

/// Log entry state
public struct LogEntryState: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let message: String
    public let level: LogLevelState
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        message: String,
        level: LogLevelState,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.message = message
        self.level = level
        self.timestamp = timestamp
    }
}

/// Log level state (mirrors LogLevel for Sendable)
public enum LogLevelState: String, Sendable, Equatable, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// OSC log entry state
public struct OSCLogEntryState: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let address: String
    public let args: [String]
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        address: String,
        args: [String],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.address = address
        self.args = args
        self.timestamp = timestamp
    }
}

// MARK: - Songs Sub-State

/// Songs management state
public struct SongsSubState: Equatable, Sendable {
    /// Total song count
    public var totalCount: Int

    /// Currently selected song ID (in browser)
    public var selectedSongId: SongID?

    /// Current search query
    public var searchQuery: String

    /// Current filter
    public var filter: SongFilter

    /// Current sort order
    public var sortOrder: SongSortOrder

    /// Filtered/searched results (for UI display)
    public var displayedSongs: [Song]

    /// Song being re-analyzed
    public var reanalyzingSongId: SongID?

    /// Statistics snapshot
    public var statistics: SongStatistics?

    /// Whether songs are loading
    public var isLoading: Bool

    /// Folder scan progress (nil when not scanning)
    public var scanProgress: FolderScanProgress?

    public init(
        totalCount: Int = 0,
        selectedSongId: SongID? = nil,
        searchQuery: String = "",
        filter: SongFilter = .all,
        sortOrder: SongSortOrder = .recentlyPlayed,
        displayedSongs: [Song] = [],
        reanalyzingSongId: SongID? = nil,
        statistics: SongStatistics? = nil,
        isLoading: Bool = false,
        scanProgress: FolderScanProgress? = nil
    ) {
        self.totalCount = totalCount
        self.selectedSongId = selectedSongId
        self.searchQuery = searchQuery
        self.filter = filter
        self.sortOrder = sortOrder
        self.displayedSongs = displayedSongs
        self.reanalyzingSongId = reanalyzingSongId
        self.statistics = statistics
        self.isLoading = isLoading
        self.scanProgress = scanProgress
    }
}

// MARK: - Folder Scan Progress

/// Progress state for folder scanning
public struct FolderScanProgress: Equatable, Sendable {
    /// Current file being scanned (1-based)
    public var current: Int

    /// Total files to scan
    public var total: Int

    /// Number of songs discovered so far
    public var foundCount: Int

    /// Whether scan is in progress
    public var isScanning: Bool

    /// Folder being scanned
    public var folderName: String

    /// Progress percentage (0.0 - 1.0)
    public var progress: Double {
        total > 0 ? Double(current) / Double(total) : 0
    }

    public init(
        current: Int = 0,
        total: Int = 0,
        foundCount: Int = 0,
        isScanning: Bool = false,
        folderName: String = ""
    ) {
        self.current = current
        self.total = total
        self.foundCount = foundCount
        self.isScanning = isScanning
        self.folderName = folderName
    }
}

// MARK: - Module References

/// References to module instances (not part of equatable state).
///
/// These are stored for effect execution but not compared in state equality.
public struct ModuleReferences: Sendable {
    // Note: These would be set during app initialization
    // and accessed by effects. For now, they're placeholders.

    public init() {}
}

// MARK: - Persisted State

/// State that should be persisted to UserDefaults
public struct PersistedState: Codable, Sendable {
    public var renderEnabled: Bool
    public var renderOutputs: RenderOutputsState
    public var shaderControlsByShader: [String: ShaderWorkspaceControls]
    public var selectedShader: String?
    public var selectedMaskShader: String?
    public var currentPhase: String?
    public var playbackSource: String
    public var launcherTargets: [LaunchTarget]

    public init(
        renderEnabled: Bool = true,
        renderOutputs: RenderOutputsState = RenderOutputsState(),
        shaderControlsByShader: [String: ShaderWorkspaceControls] = [:],
        selectedShader: String? = nil,
        selectedMaskShader: String? = nil,
        currentPhase: String? = nil,
        playbackSource: String = "vdj",
        launcherTargets: [LaunchTarget] = []
    ) {
        self.renderEnabled = renderEnabled
        self.renderOutputs = renderOutputs
        self.shaderControlsByShader = shaderControlsByShader
        self.selectedShader = selectedShader
        self.selectedMaskShader = selectedMaskShader
        self.currentPhase = currentPhase
        self.playbackSource = playbackSource
        self.launcherTargets = launcherTargets
    }

    /// Create from current app state
    public init(from state: AppState) {
        self.renderEnabled = state.render.isEnabled
        self.renderOutputs = state.render.outputs
        self.shaderControlsByShader = state.render.shaderControlsByShader
        self.selectedShader = state.render.selectedShader
        self.selectedMaskShader = state.render.selectedMaskShader
        self.currentPhase = state.render.currentPhase?.rawValue
        self.playbackSource = state.playback.source
        self.launcherTargets = state.launcher.targets
    }

    /// Apply to app state
    public func apply(to state: inout AppState) {
        state.render.isEnabled = renderEnabled
        state.render.outputs = renderOutputs
        state.render.shaderControlsByShader = shaderControlsByShader
        state.render.selectedShader = selectedShader
        state.render.selectedMaskShader = selectedMaskShader
        if let phaseStr = currentPhase {
            state.render.currentPhase = Phase.from(phaseStr)
        }
        state.playback.source = playbackSource
        state.launcher.targets = launcherTargets
        state.launcher.revision &+= 1
    }
}

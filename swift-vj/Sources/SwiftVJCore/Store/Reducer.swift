// Reducer.swift - Pure functions for state transitions
// Reducers handle actions and return new state + effects

import Foundation

// MARK: - Root Reducer

/// Root reducer that combines all sub-reducers.
///
/// This is a pure function: (State, Action) → (State, Effect)
/// - State mutations happen synchronously
/// - Side effects are returned as Effect values
public func appReducer(state: inout AppState, action: AppAction) -> Effect<AppAction> {
    switch action {
    // MARK: Lifecycle
    case .startup:
        state.isRunning = true
        state.ui.addLog("Starting VJ system...", level: .info)
        return .merge(
            .send(.loadPersistedState),
            .send(.playback(.startMonitoring)),
            .send(.launchpad(.start)),
            .send(.audio(.startMonitoring))
        )

    case .shutdown:
        state.isRunning = false
        state.ui.addLog("Shutting down...", level: .info)
        return .merge(
            .send(.persistState),
            .send(.playback(.stopMonitoring)),
            .send(.launchpad(.stop)),
            .send(.audio(.stopMonitoring))
        )

    case .systemReady:
        state.isRunning = true
        state.ui.addLog("System ready", level: .info)
        return .none

    // MARK: Child Reducers
    case .playback(let playbackAction):
        var playbackState = state.playback
        let effect = playbackReducer(state: &playbackState, action: playbackAction, appState: &state)
        state.playback = playbackState
        return effect.map { AppAction.playback($0) }

    case .pipeline(let pipelineAction):
        var pipelineState = state.pipeline
        let effect = pipelineReducer(state: &pipelineState, action: pipelineAction, appState: &state)
        state.pipeline = pipelineState
        return effect

    case .render(let renderAction):
        var renderState = state.render
        let effect = renderReducer(state: &renderState, action: renderAction, appState: &state)
        state.render = renderState
        return effect

    case .launchpad(let launchpadAction):
        var launchpadState = state.launchpad
        let effect = launchpadReducer(state: &launchpadState, action: launchpadAction, appState: &state)
        state.launchpad = launchpadState
        return effect.map { AppAction.launchpad($0) }

    case .audio(let audioAction):
        return audioReducer(state: &state.audio, action: audioAction)
            .map { AppAction.audio($0) }

    case .ui(let uiAction):
        return uiReducer(state: &state.ui, action: uiAction)
            .map { AppAction.ui($0) }

    // MARK: Persistence
    case .loadPersistedState:
        return PersistenceEffects.loadState()

    case .persistedStateLoaded(let persisted):
        persisted.apply(to: &state)
        state.ui.addLog("Loaded persisted state", level: .debug)
        return .none

    case .persistState:
        let persisted = PersistedState(from: state)
        return PersistenceEffects.saveState(persisted)
    }
}

// MARK: - Playback Reducer

/// Reducer for playback-related actions
public func playbackReducer(
    state: inout PlaybackSubState,
    action: PlaybackAction,
    appState: inout AppState
) -> Effect<PlaybackAction> {
    switch action {
    case .trackChanged(let track):
        let previousTrack = state.currentTrack
        state.currentTrack = track

        // Log track change
        appState.ui.addLog("♪ \(track.artist) - \(track.title)", level: .info)

        // Trigger pipeline processing if track actually changed
        if previousTrack?.key != track.key {
            // Dispatch pipeline processing via effect
            // The effect will be caught by the app layer and processed
            return Effect<PlaybackAction>.run { _ in
                // Fire-and-forget: notify that pipeline should start
                // The actual processing happens in SwiftVJApp via EffectEnvironment
                await EffectEnvironment.shared.processPipelineTrack?(track)
            }
        }
        return .none

    case .positionUpdated(let position, let isPlaying):
        state.position = position
        state.isPlaying = isPlaying
        return .none

    case .sourceChanged(let source):
        state.source = source
        appState.ui.addLog("Playback source: \(source)", level: .info)
        // Fire-and-forget: save preference and setup source (both are side effects with no result)
        return .run { _ in
            UserDefaults.standard.set(source, forKey: "playbackSource")
            // setupSource is currently a placeholder - when implemented,
            // it will configure the playback monitor for the new source
        }

    case .playingStateChanged(let isPlaying):
        state.isPlaying = isPlaying
        return .none

    case .timingOffsetChanged(let offset):
        state.timingOffsetMs = offset
        appState.ui.addLog("Timing offset: \(offset)ms", level: .info)
        return .none

    case .startMonitoring:
        return PlaybackEffects.startMonitoring()

    case .stopMonitoring:
        return PlaybackEffects.stopMonitoring()

    case .poll:
        return PlaybackEffects.poll()
    }
}

// MARK: - Pipeline Reducer

/// Reducer for pipeline-related actions
public func pipelineReducer(
    state: inout PipelineSubState,
    action: PipelineAction,
    appState: inout AppState
) -> Effect<AppAction> {
    switch action {
    case .startProcessing(let track):
        // Skip if already processing this track
        if state.processingTrackKey == track.key && state.isProcessing {
            return .none
        }

        state.isProcessing = true
        state.processingTrackKey = track.key
        state.error = nil
        state.resetSteps()

        appState.ui.addLog("Processing: \(track.artist) - \(track.title)", level: .info)

        return PipelineEffects.processTrack(track)

    case .stepStarted(let stepName):
        state.updateStep(stepName, status: "running")
        return .none

    case .stepCompleted(let stepName, let stepStatus):
        state.updateStep(stepName, status: stepStatus.displayText, details: stepStatus.logDetails)

        // Log detailed info for specific steps
        switch stepStatus {
        case .ai(_, _, _, let keywords, let themes):
            if !keywords.isEmpty {
                appState.ui.addLog("  Keywords: \(keywords.joined(separator: ", "))", level: .info)
            }
            if !themes.isEmpty {
                appState.ui.addLog("  Themes: \(themes.joined(separator: ", "))", level: .info)
            }
        case .images(let count, let folder, _, _) where count > 0:
            appState.ui.addLog("  Images: \(count) → \(folder)", level: .info)
        default:
            break
        }

        return .none

    case .processingCompleted(let result):
        state.isProcessing = false
        state.result = result

        // Log summary
        appState.ui.addLog("Pipeline: \(result.totalTimeMs)ms - \(result.artist) - \(result.title)", level: .info)

        // Update render state from result
        var effects: [Effect<AppAction>] = []
        
        // Update detected phase if AI analysis succeeded
        if result.aiAvailable, let djPhase = result.categories["dj_phase"] as? String,
           let phase = Phase.from(djPhase) {
            effects.append(.send(.render(.phaseDetected(phase))))
        }
        
        // Handle shader selection based on auto-drive mode
        if appState.render.autoDriveMode != .manual {
            // In auto-drive mode, trigger auto-selection
            effects.append(.send(.render(.autoSelectShader)))
        } else if result.shaderMatched {
            // In manual mode, only select shader if pipeline matched one
            effects.append(.send(.render(.selectShader(result.shaderName))))
        }

        if result.imagesFound && !result.imagesFolder.isEmpty {
            effects.append(.send(.render(.imagesLoaded(count: result.imagesCount, folderPath: result.imagesFolder))))
        }

        return effects.isEmpty ? .none : .merge(effects)

    case .processingFailed(let error):
        state.isProcessing = false
        state.error = error
        appState.ui.addLog("Pipeline failed: \(error)", level: .error)
        return .none

    case .reset:
        state.resetSteps()
        state.isProcessing = false
        state.processingTrackKey = nil
        state.error = nil
        return .none

    case .clearCache:
        return PipelineEffects.clearCache()

    case .updateStep(let name, let status, let details):
        state.updateStep(name, status: status, details: details)
        return .none
    }
}

// MARK: - Render Reducer

/// Reducer for render-related actions
public func renderReducer(
    state: inout RenderSubState,
    action: RenderAction,
    appState: inout AppState
) -> Effect<AppAction> {
    switch action {
    case .selectShader(let name):
        state.selectedShader = name
        appState.ui.addLog("Selected shader: \(name)", level: .info)
        
        // Record preference if in auto-drive mode and preferences are enabled
        var effects: [Effect<AppAction>] = [
            RenderEffects.loadShader(name),
            .send(.persistState)
        ]
        
        if state.autoDriveMode != .manual && state.rememberShaderPreferences {
            if let track = appState.playback.currentTrack {
                effects.append(RenderEffects.recordShaderPreference(trackKey: track.key, shaderName: name))
            }
        }
        
        return .merge(effects)

    case .shaderSelected(let name):
        state.selectedShader = name
        return .none

    case .selectPhase(let phase):
        state.currentPhase = phase
        if let phase = phase {
            appState.ui.addLog("Phase: \(phase.displayName)", level: .info)
        } else {
            appState.ui.addLog("Phase: Auto", level: .info)
        }
        return .send(.persistState)

    case .phaseDetected(let phase):
        state.detectedSongPhase = phase
        return .none

    case .setImageIndex(let index):
        state.imageIndex = index
        return RenderEffects.setImageIndex(index)

    case .nextImage:
        let newIndex = (state.imageIndex + 1) % max(1, state.imageCount)
        state.imageIndex = newIndex
        return RenderEffects.setImageIndex(newIndex)

    case .prevImage:
        let newIndex = (state.imageIndex - 1 + state.imageCount) % max(1, state.imageCount)
        state.imageIndex = newIndex
        return RenderEffects.setImageIndex(newIndex)

    case .imagesLoaded(let count, let folderPath):
        state.imageCount = count
        state.imageIndex = 0
        appState.ui.addLog("[Images] Loaded \(count) from: \(URL(fileURLWithPath: folderPath).lastPathComponent)", level: .info)
        return RenderEffects.loadImagesFromFolder(folderPath)

    case .shaderCountUpdated(let count):
        state.shaderCount = count
        appState.ui.addLog("Shaders: \(count) loaded", level: .info)
        return .none

    case .startEngine:
        return RenderEffects.startEngine()

    case .stopEngine:
        return RenderEffects.stopEngine()
        
    case .setAutoDriveMode(let mode):
        state.autoDriveMode = mode
        appState.ui.addLog("Auto-drive: \(mode.displayName)", level: .info)
        
        // If switching to auto mode and we have a track, trigger auto-selection
        var effects: [Effect<AppAction>] = [.send(.persistState)]
        if mode != .manual && appState.playback.currentTrack != nil {
            effects.append(.send(.render(.autoSelectShader)))
        }
        return .merge(effects)
        
    case .setRememberShaderPreferences(let remember):
        state.rememberShaderPreferences = remember
        appState.ui.addLog("Remember shader preferences: \(remember)", level: .info)
        return .send(.persistState)
        
    case .autoSelectShader:
        // Auto-select shader based on current track and mode
        guard state.autoDriveMode != .manual else { return .none }
        guard let track = appState.playback.currentTrack else { return .none }
        
        // Use pipeline result if available for better matching
        let energy = appState.pipeline.result?.energy ?? 0.5
        let valence = appState.pipeline.result?.valence ?? 0.0
        
        // Determine phase based on mode
        let phase: Phase?
        switch state.autoDriveMode {
        case .manual:
            return .none  // Shouldn't reach here
        case .autoPhase:
            // Use manual phase if set, otherwise don't filter
            phase = state.currentPhase
        case .autoFull:
            // Use detected phase or manual override
            phase = state.effectivePhase
        }
        
        return RenderEffects.autoSelectShader(
            trackKey: track.key,
            energy: energy,
            valence: valence,
            phase: phase,
            rememberPreferences: state.rememberShaderPreferences
        )
    }
}

// MARK: - Launchpad Reducer

/// Reducer for Launchpad-related actions
public func launchpadReducer(
    state: inout LaunchpadSubState,
    action: LaunchpadAction,
    appState: inout AppState
) -> Effect<LaunchpadAction> {
    switch action {
    case .connected(let deviceName):
        state.isConnected = true
        state.deviceName = deviceName
        appState.ui.addLog("Launchpad: Connected to \(deviceName)", level: .info)
        return .none

    case .disconnected:
        state.isConnected = false
        state.deviceName = nil
        appState.ui.addLog("Launchpad: Disconnected", level: .info)
        return .none

    case .buttonPressed(let x, let y):
        return LaunchpadEffects.handleButtonPress(x: x, y: y)

    case .buttonReleased(let x, let y):
        return LaunchpadEffects.handleButtonRelease(x: x, y: y)

    case .stateUpdated(let snapshot):
        state.controllerState = snapshot
        state.currentBank = snapshot.activeBank
        return .none

    case .statusUpdated(let status):
        state.status = status
        state.isConnected = status.isConnected
        state.deviceName = status.deviceName
        return .none

    case .bankChanged(let bank):
        state.currentBank = bank
        return .none

    case .start:
        return LaunchpadEffects.start()

    case .stop:
        return LaunchpadEffects.stop()

    case .enterLearnMode:
        return LaunchpadEffects.enterLearnMode()

    case .exitLearnMode:
        return LaunchpadEffects.exitLearnMode()
    }
}

// MARK: - Audio Reducer

/// Reducer for audio-related actions
public func audioReducer(
    state: inout AudioSubState,
    action: AudioAction
) -> Effect<AudioAction> {
    switch action {
    case .stateUpdated(let newState):
        state = newState
        return .none

    case .levelUpdated(let level):
        state.level = level
        return .none

    case .beatPhaseUpdated(let phase):
        state.beatPhase = phase
        return .none

    case .bpmDetected(let bpm):
        state.bpm = bpm
        return .none

    case .startMonitoring:
        return AudioEffects.startMonitoring()

    case .stopMonitoring:
        return AudioEffects.stopMonitoring()
    }
}

// MARK: - UI Reducer

/// Reducer for UI-related actions
public func uiReducer(
    state: inout UISubState,
    action: UIAction
) -> Effect<UIAction> {
    switch action {
    case .log(let message, let level):
        state.addLog(message, level: level)
        return .none

    case .clearLogs:
        state.logEntries.removeAll()
        return .none

    case .oscMessageReceived(let address, let args):
        state.recordOSC(address, args: args)
        return .none

    case .clearOscMessages:
        state.oscMessages.removeAll()
        state.oscMessageCount = 0
        return .none

    case .setOscDebugEnabled(let enabled):
        state.oscDebugEnabled = enabled
        return .none

    case .setOscFilter(let filter):
        state.oscFilter = filter
        return .none
    }
}

// MARK: - Effect Placeholders

/// Placeholder effects - to be implemented in Phase 3
public enum PlaybackEffects {
    public static func startMonitoring() -> Effect<PlaybackAction> { .none }
    public static func stopMonitoring() -> Effect<PlaybackAction> { .none }
    public static func poll() -> Effect<PlaybackAction> { .none }
    public static func setupSource(_ source: String) -> Effect<PlaybackAction> { .none }
}

public enum PipelineEffects {
    public static func processTrack(_ track: Track) -> Effect<AppAction> { .none }
    public static func clearCache() -> Effect<AppAction> { .none }
}

public enum RenderEffects {
    public static func loadShader(_ name: String) -> Effect<AppAction> {
        .run { _ in
            // Execute shader loading via environment
            await EffectEnvironment.shared.loadShader?(name)
        }
    }
    
    public static func autoSelectShader(
        trackKey: String,
        energy: Double,
        valence: Double,
        phase: Phase?,
        rememberPreferences: Bool
    ) -> Effect<AppAction> {
        .run { _ in
            await EffectEnvironment.shared.autoSelectShader?(trackKey, energy, valence, phase, rememberPreferences)
        }
    }
    
    public static func recordShaderPreference(trackKey: String, shaderName: String) -> Effect<AppAction> {
        .fireAndForget {
            await EffectEnvironment.shared.recordShaderPreference?(trackKey, shaderName)
        }
    }
    
    public static func setImageIndex(_ index: Int) -> Effect<AppAction> { .none }
    public static func loadImagesFromFolder(_ path: String) -> Effect<AppAction> { .none }
    public static func startEngine() -> Effect<AppAction> { .none }
    public static func stopEngine() -> Effect<AppAction> { .none }
}

public enum LaunchpadEffects {
    public static func start() -> Effect<LaunchpadAction> { .none }
    public static func stop() -> Effect<LaunchpadAction> { .none }
    public static func handleButtonPress(x: Int, y: Int) -> Effect<LaunchpadAction> { .none }
    public static func handleButtonRelease(x: Int, y: Int) -> Effect<LaunchpadAction> { .none }
    public static func enterLearnMode() -> Effect<LaunchpadAction> { .none }
    public static func exitLearnMode() -> Effect<LaunchpadAction> { .none }
}

public enum AudioEffects {
    public static func startMonitoring() -> Effect<AudioAction> { .none }
    public static func stopMonitoring() -> Effect<AudioAction> { .none }
}

public enum PersistenceEffects {
    public static func loadState() -> Effect<AppAction> {
        .run { send in
            // Load from UserDefaults
            let shader = UserDefaults.standard.string(forKey: "selectedShader")
            let phase = UserDefaults.standard.string(forKey: "currentPhase")
            let source = UserDefaults.standard.string(forKey: "playbackSource") ?? "vdj"
            let autoDrive = UserDefaults.standard.string(forKey: "autoDriveMode") ?? "manual"
            let rememberPrefs = UserDefaults.standard.bool(forKey: "rememberShaderPreferences")

            let persisted = PersistedState(
                selectedShader: shader,
                currentPhase: phase,
                playbackSource: source,
                autoDriveMode: autoDrive,
                rememberShaderPreferences: rememberPrefs
            )

            await send(.persistedStateLoaded(persisted))
        }
    }

    public static func saveState(_ state: PersistedState) -> Effect<AppAction> {
        .fireAndForget {
            if let shader = state.selectedShader {
                UserDefaults.standard.set(shader, forKey: "selectedShader")
            }
            if let phase = state.currentPhase {
                UserDefaults.standard.set(phase, forKey: "currentPhase")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentPhase")
            }
            UserDefaults.standard.set(state.playbackSource, forKey: "playbackSource")
            UserDefaults.standard.set(state.autoDriveMode, forKey: "autoDriveMode")
            UserDefaults.standard.set(state.rememberShaderPreferences, forKey: "rememberShaderPreferences")
        }
    }

    public static func savePlaybackSource(_ source: String) -> Effect<AppAction> {
        .fireAndForget {
            UserDefaults.standard.set(source, forKey: "playbackSource")
        }
    }
}

// Reducer.swift - Pure functions for state transitions
// Reducers handle actions and return new state + effects

import Foundation
import SongRepository

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

    case .launcher(let launcherAction):
        var launcherState = state.launcher
        let effect = launcherReducer(state: &launcherState, action: launcherAction, appState: &state)
        state.launcher = launcherState
        return effect

    case .ledfx(let ledfxAction):
        var ledfxState = state.ledfx
        let effect = ledfxReducer(state: &ledfxState, action: ledfxAction)
        state.ledfx = ledfxState
        return effect

    case .songs(let songsAction):
        var songsState = state.songs
        let effect = songsReducer(state: &songsState, action: songsAction, appState: &state)
        state.songs = songsState
        return effect

    // MARK: Persistence
    case .loadPersistedState:
        return PersistenceEffects.loadState()

    case .persistedStateLoaded(let persisted):
        persisted.apply(to: &state)
        state.ui.addLog("Loaded persisted state", level: .debug)
        var followUp: [Effect<AppAction>] = [
            .send(.render(.setEnabled(persisted.renderEnabled)))
        ]
        if let shader = persisted.selectedShader, !shader.isEmpty {
            followUp.append(.send(.render(.selectShader(shader))))
        }
        if let mask = persisted.selectedMaskShader, !mask.isEmpty {
            followUp.append(.send(.render(.selectMaskShader(mask))))
        }
        if state.launcher.targets.contains(where: \.autoStart) {
            followUp.append(.send(.launcher(.launchAutoStartRequested)))
        }
        return followUp.isEmpty ? .none : .merge(followUp)

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
        return handleTrackChange(
            track,
            forcePipelineRun: false,
            state: &state,
            appState: &appState
        )

    case .demoTrackChanged(let track):
        return handleTrackChange(
            track,
            forcePipelineRun: true,
            state: &state,
            appState: &appState
        )

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

    case .startMonitoring:
        return PlaybackEffects.startMonitoring()

    case .stopMonitoring:
        return PlaybackEffects.stopMonitoring()

    case .poll:
        return PlaybackEffects.poll()
    }
}

private func handleTrackChange(
    _ track: Track,
    forcePipelineRun: Bool,
    state: inout PlaybackSubState,
    appState: inout AppState
) -> Effect<PlaybackAction> {
    let previousTrack = state.currentTrack
    state.currentTrack = track

    // Log track change
    appState.ui.addLog("♪ \(track.artist) - \(track.title)", level: .info)

    // Trigger pipeline processing for new tracks, or always for explicit demo play.
    guard forcePipelineRun || previousTrack?.key != track.key else {
        return .none
    }

    return Effect<PlaybackAction>.run { _ in
        // Fire-and-forget: notify that pipeline should start
        // The actual processing happens in SwiftVJApp via EffectEnvironment
        await EffectEnvironment.shared.processPipelineTrack?(track)
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
        state.expandedStepNames.removeAll()

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

        if result.shaderMatched {
            effects.append(.send(.render(.selectShader(result.shaderName))))
        }

        if result.imagesFound && !result.imagesFolder.isEmpty {
            effects.append(.send(.render(.imagesLoaded(count: result.imagesCount, folderPath: result.imagesFolder))))
        }

        // Auto-save song to database
        effects.append(SongsEffects.recordSong(from: result))

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
        state.expandedStepNames.removeAll()
        return .none

    case .clearCache:
        return PipelineEffects.clearCache()

    case .updateStep(let name, let status, let details):
        state.updateStep(name, status: status, details: details)
        return .none

    case .toggleStepExpansion(let stepName):
        state.toggleStepExpansion(stepName)
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
    case .setEnabled(let enabled):
        state.isEnabled = enabled
        appState.ui.addLog(enabled ? "Renderer enabled" : "Renderer disabled", level: .info)
        return .merge(
            RenderEffects.setEnabled(enabled),
            .send(.persistState)
        )

    case .selectShader(let name):
        state.selectedShader = name
        appState.ui.addLog("Selected shader: \(name)", level: .info)
        return .merge(
            RenderEffects.loadShader(name),
            .send(.persistState)
        )

    case .selectMaskShader(let name):
        state.selectedMaskShader = name
        appState.ui.addLog("Selected mask: \(name)", level: .info)
        return .merge(
            RenderEffects.loadMaskShader(name),
            .send(.persistState)
        )

    case .shaderSelected(let name):
        state.selectedShader = name
        return .none

    case .maskShaderSelected(let name):
        state.selectedMaskShader = name
        return .none

    case .selectNextShader:
        return RenderEffects.selectNextShader(current: state.selectedShader)

    case .selectPreviousShader:
        return RenderEffects.selectPreviousShader(current: state.selectedShader)

    case .selectRandomShader:
        return RenderEffects.selectRandomShader()

    case .selectNextMaskShader:
        return RenderEffects.selectNextMaskShader(current: state.selectedMaskShader)

    case .selectPreviousMaskShader:
        return RenderEffects.selectPreviousMaskShader(current: state.selectedMaskShader)

    case .selectRandomMaskShader:
        return RenderEffects.selectRandomMaskShader()

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
        state.isEnabled = true
        appState.ui.addLog("Renderer enabled", level: .info)
        return .merge(
            RenderEffects.startEngine(),
            .send(.persistState)
        )

    case .stopEngine:
        state.isEnabled = false
        appState.ui.addLog("Renderer disabled", level: .info)
        return .merge(
            RenderEffects.stopEngine(),
            .send(.persistState)
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

    case .stateUpdated(let controllerState):
        state.controllerState = controllerState
        state.currentBank = controllerState.activeBank
        state.controllerRevision &+= 1
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

    case .forceProgrammerMode:
        return LaunchpadEffects.forceProgrammerMode()

    case .flashAll:
        return LaunchpadEffects.flashAll()

    case .rainbowPattern:
        return LaunchpadEffects.rainbowPattern()

    case .clearAll:
        return LaunchpadEffects.clearAll()

    case .oscEventReceived(let event):
        return LaunchpadEffects.receiveOscEvent(event)

    case .bpmUpdated(let bpm):
        _ = bpm
        return .none
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

    case .reloadTachikomaConfig:
        return .fireAndForget {
            await EffectEnvironment.shared.reloadLLMConfiguration?()
        }
    }
}

// MARK: - Launcher Reducer

/// Reducer for controlled app/command launcher actions.
public func launcherReducer(
    state: inout LauncherSubState,
    action: LauncherAction,
    appState: inout AppState
) -> Effect<AppAction> {
    switch action {
    case .addAppTargetsRequested(let urls):
        state.lastError = nil
        return LauncherEffects.analyzeDroppedItems(urls)
            .map { AppAction.launcher($0) }

    case .appTargetsAnalyzed(let incomingTargets):
        var existingByIdentity = Dictionary(uniqueKeysWithValues: state.targets.map { ($0.normalizedIdentity, $0.id) })
        var added = 0

        for target in incomingTargets where target.kind == .app {
            let identity = target.normalizedIdentity
            if existingByIdentity[identity] != nil { continue }
            state.targets.append(target)
            existingByIdentity[identity] = target.id
            added += 1
        }

        state.revision &+= 1
        if added > 0 {
            appState.ui.addLog("Launcher: added \(added) app target(s)", level: .info)
            return .send(.persistState)
        }
        appState.ui.addLog("Launcher: no new app targets to add", level: .debug)
        return .none

    case .addCommandTargetRequested(let commandLine, let workingDirectory):
        let trimmedCommand = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCommand.isEmpty else {
            state.lastError = "Command line cannot be empty."
            state.revision &+= 1
            return .none
        }
        let trimmedCwd = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCwd = (trimmedCwd?.isEmpty == true) ? nil : trimmedCwd

        let commandName = trimmedCommand.split(separator: " ").first.map(String.init) ?? "Command"
        let target = LaunchTarget.commandTarget(
            id: "cmd:\(UUID().uuidString)",
            displayName: commandName,
            commandLine: trimmedCommand,
            workingDirectory: normalizedCwd
        )

        if state.targets.contains(where: { $0.normalizedIdentity == target.normalizedIdentity }) {
            state.lastError = "That command target already exists."
            state.revision &+= 1
            return .none
        }

        state.lastError = nil
        state.targets.append(target)
        state.revision &+= 1
        appState.ui.addLog("Launcher: added command target \(commandName)", level: .info)
        return .send(.persistState)

    case .removeTarget(let id):
        let before = state.targets.count
        state.targets.removeAll { $0.id == id }
        state.runningTargetIDs.remove(id)
        if state.targets.count != before {
            state.revision &+= 1
            appState.ui.addLog("Launcher: removed target", level: .info)
            return .send(.persistState)
        }
        return .none

    case .setAutoStart(let id, let enabled):
        guard let index = state.targets.firstIndex(where: { $0.id == id }) else { return .none }
        state.targets[index].autoStart = enabled
        state.revision &+= 1
        return .send(.persistState)

    case .launchTargetRequested(let id):
        guard let target = state.targets.first(where: { $0.id == id }) else {
            state.lastError = "Launch target not found."
            state.revision &+= 1
            return .none
        }
        state.lastError = nil
        state.revision &+= 1
        return LauncherEffects.launchTarget(target)
            .map { AppAction.launcher($0) }

    case .launchMissingRequested:
        state.isLaunchingAll = true
        state.lastError = nil
        state.revision &+= 1
        return LauncherEffects.launchTargetsIfNeeded(state.targets)
            .map { AppAction.launcher($0) }

    case .launchAutoStartRequested:
        let autostartTargets = state.targets.filter(\.autoStart)
        guard !autostartTargets.isEmpty else { return .none }
        state.isLaunchingAll = true
        state.lastError = nil
        state.revision &+= 1
        return LauncherEffects.launchTargetsIfNeeded(autostartTargets)
            .map { AppAction.launcher($0) }

    case .launchTargetCompleted(let id, let launched, let error):
        if let target = state.targets.first(where: { $0.id == id }) {
            switch target.kind {
            case .app:
                if launched || error == nil {
                    state.runningTargetIDs.insert(id)
                    state.lastError = nil
                }
            case .command:
                // Command targets always run in external terminal; we don't infer runtime state.
                state.runningTargetIDs.remove(id)
                if launched {
                    state.lastError = nil
                }
            }
        }
        if let error, !error.isEmpty {
            state.lastError = error
            appState.ui.addLog("Launcher: \(error)", level: .error)
        }
        state.revision &+= 1
        return .none

    case .launchAllCompleted(let report):
        state.isLaunchingAll = false
        state.runningTargetIDs = report.runningTargetIDs
        if let firstError = report.failedTargetErrors.values.sorted().first {
            state.lastError = firstError
        } else {
            state.lastError = nil
        }

        let launched = report.launchedTargetIDs.count
        let already = report.alreadyRunningTargetIDs.count
        let failed = report.failedTargetErrors.count
        state.lastLaunchSummary = "Launched \(launched), already running \(already), failed \(failed)"
        appState.ui.addLog("Launcher: \(state.lastLaunchSummary ?? "completed")", level: failed > 0 ? .warning : .info)
        state.revision &+= 1
        return .none

    case .clearError:
        state.lastError = nil
        state.revision &+= 1
        return .none
    }
}

// MARK: - LedFX Reducer

/// Reducer for LedFX-related actions (effect-only)
public func ledfxReducer(state: inout LedFXSubState, action: LedFXAction) -> Effect<AppAction> {
    let previous = state
    let effect: Effect<AppAction>

    switch action {
    case .setBaseURL(let value):
        state.baseURL = normalizeLedFXBaseURL(value)
        effect = LedFXEffects.handle(action)

    case .setVirtualIds(let value):
        state.virtualIdsString = value
        effect = LedFXEffects.handle(action)

    case .setSceneFilter(let value):
        state.sceneFilter = value
        effect = .none

    case .setPlaylistFilter(let value):
        state.playlistFilter = value
        effect = .none

    case .applySettings(let baseURL, let virtualIds):
        state.baseURL = normalizeLedFXBaseURL(baseURL)
        state.virtualIdsString = virtualIds.joined(separator: ", ")
        state.isApplying = true
        state.errorMessage = nil
        effect = LedFXEffects.handle(action)

    case .applyCompleted:
        state.isApplying = false
        effect = .none

    case .refresh, .testConnection:
        state.isRefreshing = true
        state.errorMessage = nil
        effect = LedFXEffects.handle(action)

    case .refreshCompleted(let snapshot):
        state.isRefreshing = false
        state.serverInfo = snapshot.serverInfo
        state.scenes = snapshot.scenes
        state.virtuals = snapshot.virtuals
        state.playlists = snapshot.playlists
        if let active = state.activePlaylistId,
           snapshot.playlists[active] == nil {
            state.activePlaylistId = nil
        }
        state.isRunning = snapshot.isOnline
        state.healthSummary = snapshot.healthSummary
        state.lastHealthCheck = snapshot.lastHealthCheck
        effect = .none

    case .refreshFailed(let message):
        state.isRefreshing = false
        state.errorMessage = message
        state.isRunning = false
        state.healthSummary = "Offline"
        state.lastHealthCheck = Date()
        effect = .none

    case .generateBridgeConfig:
        state.isGeneratingConfig = true
        state.errorMessage = nil
        effect = LedFXEffects.handle(action)

    case .generateConfigCompleted(let yaml, let playlistCount, let effectsCount):
        state.isGeneratingConfig = false
        state.generatedYaml = yaml
        state.playlistCount = playlistCount
        state.effectsCount = effectsCount
        effect = .none

    case .generateConfigFailed(let message):
        state.isGeneratingConfig = false
        state.errorMessage = message
        effect = .none

    case .loadCachedConfig:
        state.errorMessage = nil
        effect = LedFXEffects.handle(action)

    case .cachedConfigLoaded(let yaml, let playlistCount):
        state.generatedYaml = yaml
        state.playlistCount = playlistCount
        state.effectsCount = 0
        effect = .none

    case .cachedConfigFailed(let message):
        state.errorMessage = message
        effect = .none

    case .loadGeneratedConfig(let yaml):
        state.errorMessage = nil
        state.generatedYaml = yaml
        effect = LedFXEffects.handle(action)

    case .activateScene(_),
         .deactivateScene(_),
         .deleteScene(_),
         .activatePlaylist(_),
         .stopPlaylist,
         .setVirtualBrightness(_, _),
         .generateScenes(_),
         .saveGeneratedConfig,
         .sendTestScene,
         .sendTestPlaylist,
         .sendTestOneshot:
        state.errorMessage = nil
        effect = LedFXEffects.handle(action)

    case .playlistActivated(let id):
        state.activePlaylistId = id
        effect = .none

    case .playlistStopped:
        state.activePlaylistId = nil
        effect = .none

    case .setError(let message):
        state.errorMessage = message
        effect = .none

    case .clearError:
        state.errorMessage = nil
        effect = .none
    }

    if state != previous {
        state.revision &+= 1
    }
    return effect
}

private func normalizeLedFXBaseURL(_ baseURL: String) -> String {
    baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")).trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Songs Reducer

/// Reducer for songs-related actions
public func songsReducer(
    state: inout SongsSubState,
    action: SongsAction,
    appState: inout AppState
) -> Effect<AppAction> {
    switch action {
    case .load:
        state.isLoading = true
        return SongsEffects.load()

    case .loaded(let count):
        state.totalCount = count
        state.isLoading = false
        appState.ui.addLog("Songs: Loaded \(count) songs", level: .info)
        // Trigger initial list refresh
        return .send(.songs(.refreshList))

    case .songRecorded(let artist, let title):
        state.totalCount += 1
        appState.ui.addLog("Song saved: \(artist) - \(title)", level: .info)
        return .none

    case .songSelected(let id):
        state.selectedSongId = id
        return .none

    case .demoPlayRequested(let id):
        state.selectedSongId = id
        return SongsEffects.demoPlay(id)

    case .demoPlayStarted(let id):
        state.selectedSongId = id
        appState.ui.addLog("Demo Play: \(id.artist) - \(id.title)", level: .info)
        return .none

    case .demoPlayFailed(_, let reason):
        appState.ui.addLog("Demo Play failed: \(reason)", level: .error)
        return .none

    case .deleteSong(let id):
        return SongsEffects.deleteSong(id)

    case .songDeleted(let id):
        state.totalCount = max(0, state.totalCount - 1)
        if state.selectedSongId == id {
            state.selectedSongId = nil
        }
        state.displayedSongs.removeAll { $0.id == id }
        appState.ui.addLog("Song deleted: \(id)", level: .info)
        return .none

    case .requestReanalysis(let id):
        state.reanalyzingSongId = id
        appState.ui.addLog("Re-analyzing: \(id)", level: .info)
        return SongsEffects.reanalyze(id)

    case .reanalysisStarted(let id):
        state.reanalyzingSongId = id
        return .none

    case .reanalysisCompleted(let id):
        state.reanalyzingSongId = nil
        appState.ui.addLog("Re-analysis complete: \(id)", level: .info)
        // Trigger refresh of displayed songs
        return .send(.songs(.refreshList))

    case .setShader(let id, let shader):
        return SongsEffects.setShader(shader, for: id)

    case .search(let query):
        state.searchQuery = query
        if query.isEmpty {
            return .send(.songs(.refreshList))
        }
        return SongsEffects.search(query)

    case .searchResultsReceived(let songs):
        state.displayedSongs = songs
        return .none

    case .applyFilter(let filter):
        state.filter = filter
        return SongsEffects.filter(filter, sortBy: state.sortOrder)

    case .filterResultsReceived(let songs):
        state.displayedSongs = songs
        return .none

    case .save:
        return SongsEffects.save()

    case .clearFilter:
        state.searchQuery = ""
        state.filter = .all
        return .send(.songs(.refreshList))

    case .statisticsUpdated(let statistics):
        state.statistics = statistics
        state.totalCount = statistics.totalCount
        return .none

    case .deleteImage(let id, let url):
        return SongsEffects.deleteImage(id, url: url)

    case .songUpdated(let song):
        if let index = state.displayedSongs.firstIndex(where: { $0.id == song.id }) {
            state.displayedSongs[index] = song
        }
        return .none

    case .refreshList:
        // Refresh with current filter and sort
        if state.searchQuery.isEmpty {
            return SongsEffects.filter(state.filter, sortBy: state.sortOrder)
        } else {
            return SongsEffects.search(state.searchQuery)
        }

    // MARK: - Folder Scanning

    case .scanFolderRequested(let url):
        // Start the scan effect
        return SongsEffects.scanFolder(url)

    case .scanStarted(let total, let folderName):
        state.scanProgress = FolderScanProgress(
            current: 0,
            total: total,
            foundCount: 0,
            isScanning: true,
            folderName: folderName
        )
        appState.ui.addLog("Scanning folder: \(folderName) (\(total) files)", level: .info)
        return .none

    case .scanProgress(let current, let found):
        state.scanProgress?.current = current
        state.scanProgress?.foundCount = found
        return .none

    case .songDiscovered(let artist, let title):
        let songId = SongID(artist: artist, title: title)

        // Check for duplicate in existing displayed songs
        let alreadyExists = state.displayedSongs.contains { $0.id == songId }

        if !alreadyExists {
            // Create minimal song entry and add to store
            return SongsEffects.addDiscoveredSong(artist: artist, title: title)
        }
        return .none

    case .scanCompleted:
        let foundCount = state.scanProgress?.foundCount ?? 0
        state.scanProgress = nil
        appState.ui.addLog("Scan complete: \(foundCount) songs added", level: .info)
        // Refresh the list to show new songs
        return .merge(
            .send(.songs(.refreshList)),
            .send(.songs(.save))
        )

    case .cancelScanRequested:
        return SongsEffects.cancelScan().map { _ in AppAction.songs(.scanCancelled) }

    case .scanCancelled:
        let scannedCount = state.scanProgress?.current ?? 0
        let foundCount = state.scanProgress?.foundCount ?? 0
        state.scanProgress = nil
        appState.ui.addLog("Scan cancelled: \(foundCount) songs added (scanned \(scannedCount) files)", level: .info)
        return .merge(
            .send(.songs(.refreshList)),
            .send(.songs(.save))
        )
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
    public static func setEnabled(_ enabled: Bool) -> Effect<AppAction> {
        .run { _ in
            await EffectEnvironment.shared.setRenderEnabled?(enabled)
        }
    }

    public static func loadShader(_ name: String) -> Effect<AppAction> {
        .run { _ in
            // Execute shader loading via environment
            await EffectEnvironment.shared.loadShader?(name)
        }
    }

    public static func loadMaskShader(_ name: String) -> Effect<AppAction> {
        .run { _ in
            await EffectEnvironment.shared.loadMaskShader?(name)
        }
    }

    public static func selectNextShader(current: String?) -> Effect<AppAction> {
        selectAdjacentName(current: current, fromMasks: false, step: 1)
    }

    public static func selectPreviousShader(current: String?) -> Effect<AppAction> {
        selectAdjacentName(current: current, fromMasks: false, step: -1)
    }

    public static func selectRandomShader() -> Effect<AppAction> {
        .run { send in
            let names = await EffectEnvironment.shared.availableShaderNames?() ?? []
            guard let choice = names.randomElement() else { return }
            await send(.render(.selectShader(choice)))
        }
    }

    public static func selectNextMaskShader(current: String?) -> Effect<AppAction> {
        selectAdjacentName(current: current, fromMasks: true, step: 1)
    }

    public static func selectPreviousMaskShader(current: String?) -> Effect<AppAction> {
        selectAdjacentName(current: current, fromMasks: true, step: -1)
    }

    public static func selectRandomMaskShader() -> Effect<AppAction> {
        .run { send in
            let names = await EffectEnvironment.shared.availableMaskShaderNames?() ?? []
            guard let choice = names.randomElement() else { return }
            await send(.render(.selectMaskShader(choice)))
        }
    }

    public static func setImageIndex(_ index: Int) -> Effect<AppAction> {
        .run { _ in
            await EffectEnvironment.shared.setImageIndex?(index)
        }
    }
    public static func loadImagesFromFolder(_ path: String) -> Effect<AppAction> {
        .run { _ in
            await EffectEnvironment.shared.loadImagesFromFolder?(path)
        }
    }
    public static func startEngine() -> Effect<AppAction> { setEnabled(true) }
    public static func stopEngine() -> Effect<AppAction> { setEnabled(false) }

    private static func selectAdjacentName(
        current: String?,
        fromMasks: Bool,
        step: Int
    ) -> Effect<AppAction> {
        .run { send in
            let names = fromMasks
                ? (await EffectEnvironment.shared.availableMaskShaderNames?() ?? [])
                : (await EffectEnvironment.shared.availableShaderNames?() ?? [])

            guard !names.isEmpty else { return }

            let nextName: String
            if let current, let index = names.firstIndex(of: current) {
                let offset = (index + step + names.count) % names.count
                nextName = names[offset]
            } else {
                nextName = names[0]
            }

            if fromMasks {
                await send(.render(.selectMaskShader(nextName)))
            } else {
                await send(.render(.selectShader(nextName)))
            }
        }
    }
}

public enum LauncherEffects {
    public static func analyzeDroppedItems(_ urls: [URL]) -> Effect<LauncherAction> {
        .run { send in
            guard let handler = await EffectEnvironment.shared.launcherHandler else { return }
            let analyzed = await handler.analyzeDroppedItems(urls)
            await send(.appTargetsAnalyzed(analyzed))
        }
    }

    public static func launchTarget(_ target: LaunchTarget) -> Effect<LauncherAction> {
        .run { send in
            guard let handler = await EffectEnvironment.shared.launcherHandler else {
                await send(.launchTargetCompleted(id: target.id, launched: false, error: "Launcher unavailable"))
                return
            }
            let result = await handler.launchTarget(target)
            await send(.launchTargetCompleted(id: target.id, launched: result.launched, error: result.error))
        }
    }

    public static func launchTargetsIfNeeded(_ targets: [LaunchTarget]) -> Effect<LauncherAction> {
        .run { send in
            guard let handler = await EffectEnvironment.shared.launcherHandler else {
                await send(.launchAllCompleted(
                    LauncherLaunchReport(
                        failedTargetErrors: ["launcher": "Launcher unavailable"],
                        runningTargetIDs: []
                    )
                ))
                return
            }
            let report = await handler.launchTargetsIfNeeded(targets)
            await send(.launchAllCompleted(report))
        }
    }
}

public enum LaunchpadEffects {
    public static func start() -> Effect<LaunchpadAction> {
        .run(cancellationId: EffectCancellationId.launchpad) { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.start()
        }
    }

    public static func stop() -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.stop()
        }
    }

    public static func handleButtonPress(x: Int, y: Int) -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.buttonPressed(x: x, y: y)
        }
    }

    public static func handleButtonRelease(x: Int, y: Int) -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.buttonReleased(x: x, y: y)
        }
    }

    public static func enterLearnMode() -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.enterLearnMode()
        }
    }

    public static func exitLearnMode() -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.exitLearnMode()
        }
    }

    public static func forceProgrammerMode() -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.forceProgrammerMode()
        }
    }

    public static func flashAll() -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.flashAll()
        }
    }

    public static func rainbowPattern() -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.rainbowPattern()
        }
    }

    public static func clearAll() -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.clearAll()
        }
    }

    public static func receiveOscEvent(_ event: OscEvent) -> Effect<LaunchpadAction> {
        .run { _ in
            guard let handler = await EffectEnvironment.shared.launchpadHandler else { return }
            await handler.receiveOscEvent(event)
        }
    }

}

public enum AudioEffects {
    public static func startMonitoring() -> Effect<AudioAction> { .none }
    public static func stopMonitoring() -> Effect<AudioAction> { .none }
}

public enum PersistenceEffects {
    public static func loadState() -> Effect<AppAction> {
        .run { send in
            // Load from UserDefaults
            let renderEnabled = (UserDefaults.standard.object(forKey: "renderEnabled") as? Bool) ?? true
            let shader = UserDefaults.standard.string(forKey: "selectedShader")
            let maskShader = UserDefaults.standard.string(forKey: "selectedMaskShader")
            let phase = UserDefaults.standard.string(forKey: "currentPhase")
            let source = UserDefaults.standard.string(forKey: "playbackSource") ?? "vdj"
            let launcherTargets: [LaunchTarget]
            if let launcherData = UserDefaults.standard.data(forKey: "launcherTargets"),
               let decoded = try? JSONDecoder().decode([LaunchTarget].self, from: launcherData) {
                launcherTargets = decoded
            } else {
                launcherTargets = []
            }

            let persisted = PersistedState(
                renderEnabled: renderEnabled,
                selectedShader: shader,
                selectedMaskShader: maskShader,
                currentPhase: phase,
                playbackSource: source,
                launcherTargets: launcherTargets
            )

            await send(.persistedStateLoaded(persisted))
        }
    }

    public static func saveState(_ state: PersistedState) -> Effect<AppAction> {
        .fireAndForget {
            UserDefaults.standard.set(state.renderEnabled, forKey: "renderEnabled")
            if let shader = state.selectedShader {
                UserDefaults.standard.set(shader, forKey: "selectedShader")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedShader")
            }
            if let maskShader = state.selectedMaskShader {
                UserDefaults.standard.set(maskShader, forKey: "selectedMaskShader")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedMaskShader")
            }
            if let phase = state.currentPhase {
                UserDefaults.standard.set(phase, forKey: "currentPhase")
            } else {
                UserDefaults.standard.removeObject(forKey: "currentPhase")
            }
            UserDefaults.standard.set(state.playbackSource, forKey: "playbackSource")
            if let launcherData = try? JSONEncoder().encode(state.launcherTargets) {
                UserDefaults.standard.set(launcherData, forKey: "launcherTargets")
            } else {
                UserDefaults.standard.removeObject(forKey: "launcherTargets")
            }
        }
    }

    public static func savePlaybackSource(_ source: String) -> Effect<AppAction> {
        .fireAndForget {
            UserDefaults.standard.set(source, forKey: "playbackSource")
        }
    }
}

public enum LedFXEffects {
    public static func handle(_ action: LedFXAction) -> Effect<AppAction> {
        .run { _ in
            await EffectEnvironment.shared.ledfxActionHandler?(action)
        }
    }
}

public enum SongsEffects {
    public static func load() -> Effect<AppAction> {
        .run { send in
            guard let module = await EffectEnvironment.shared.songsModule else {
                await send(.songs(.loaded(count: 0)))
                return
            }
            try? await module.start()
            let count = await module.songCount
            let stats = await module.statistics
            await send(.songs(.loaded(count: count)))
            await send(.songs(.statisticsUpdated(stats)))
        }
    }

    public static func recordSong(from result: PipelineResult) -> Effect<AppAction> {
        .run { send in
            guard let module = await EffectEnvironment.shared.songsModule else {
                return
            }

            // Extract DJ phase from categories if available
            var djPhase: Phase? = nil
            if !result.mood.isEmpty {
                // Simple phase detection from mood/energy
                if result.energy > 0.7 {
                    djPhase = .peak
                } else if result.energy > 0.5 {
                    djPhase = .buildup
                } else if result.energy > 0.3 {
                    djPhase = .disco
                } else {
                    djPhase = .release
                }
            }

        await module.recordSong(
            artist: result.artist,
            title: result.title,
            album: result.album,
            duration: 0,  // Not available in PipelineResult
            bpm: 0,       // Not available in PipelineResult
            musicalKey: "",  // Not available in PipelineResult
            mood: result.mood,
            energy: result.energy,
            valence: result.valence,
            keywords: result.keywords,
            themes: result.themes,
            visualAdjectives: result.visualAdjectives,
            categories: result.categories,
            djPhase: djPhase,
            shaderName: result.shaderMatched ? result.shaderName : nil,
            imagesFolderPath: result.imagesFound ? result.imagesFolder : nil,
            imagesCount: result.imagesCount,
            hasLyrics: result.lyricsFound,
            lyricsText: result.plainLyrics,
            lyricsLineCount: result.lyricsLineCount,
            refrainCount: result.refrainLines.count
        )

        await send(.songs(.songRecorded(artist: result.artist, title: result.title)))
        }
    }

    public static func save() -> Effect<AppAction> {
        .fireAndForget {
            await EffectEnvironment.shared.songsModule?.saveNow()
        }
    }

    public static func search(_ query: String) -> Effect<AppAction> {
        .run { send in
            guard let module = await EffectEnvironment.shared.songsModule else {
                await send(.songs(.searchResultsReceived([])))
                return
            }
            let results = await module.search(query: query)
            await send(.songs(.searchResultsReceived(results)))
        }
    }

    public static func filter(_ filter: SongFilter, sortBy order: SongSortOrder) -> Effect<AppAction> {
        .run { send in
            guard let module = await EffectEnvironment.shared.songsModule else {
                await send(.songs(.filterResultsReceived([])))
                return
            }
            let results = await module.query(filter: filter, sortBy: order)
            await send(.songs(.filterResultsReceived(results)))
        }
    }

    public static func deleteSong(_ id: SongID) -> Effect<AppAction> {
        .run { send in
            await EffectEnvironment.shared.songsModule?.deleteSong(id: id)
            await send(.songs(.songDeleted(id)))
        }
    }

    public static func setShader(_ shader: String, for id: SongID) -> Effect<AppAction> {
        .fireAndForget {
            await EffectEnvironment.shared.songsModule?.setShader(shader, for: id)
        }
    }

    public static func deleteImage(_ id: SongID, url: URL) -> Effect<AppAction> {
        .run { send in
            guard let module = await EffectEnvironment.shared.songsModule else { return }
            if let updated = try? await module.deleteImage(id: id, imageURL: url) {
                await send(.songs(.songUpdated(updated)))
            }
            await send(.songs(.refreshList))
        }
    }

    public static func reanalyze(_ id: SongID) -> Effect<AppAction> {
        .run { send in
            guard let songsModule = await EffectEnvironment.shared.songsModule,
                  let song = await songsModule.getSong(id: id) else {
                return
            }

            await send(.songs(.reanalysisStarted(id)))

            // Clear caches to force fresh analysis
            await EffectEnvironment.shared.clearLyricsCache?(song.artist, song.title)
            await EffectEnvironment.shared.clearPipelineCache?(song.artist, song.title)
            await EffectEnvironment.shared.clearImagesCache?(song.artist, song.title)

            // Mark for reanalysis in the module
            await songsModule.markForReanalysis(id: id)

            // Trigger pipeline processing for this song
            let track = Track(
                artist: song.artist,
                title: song.title,
                album: song.album,
                duration: song.duration,
                bpm: song.bpm,
                musicalKey: song.musicalKey
            )

            // Use pipeline to re-analyze
            await EffectEnvironment.shared.processPipelineTrack?(track)

            // Mark reanalysis as completed
            await send(.songs(.reanalysisCompleted(id)))
        }
    }

    public static func demoPlay(_ id: SongID) -> Effect<AppAction> {
        .run(cancellationId: EffectCancellationId.custom("songs.demo-play")) { send in
            guard let songsModule = await EffectEnvironment.shared.songsModule else {
                await send(.songs(.demoPlayFailed(id, "Songs module not available")))
                return
            }
            guard let song = await songsModule.getSong(id: id) else {
                await send(.songs(.demoPlayFailed(id, "Song not found")))
                return
            }

            await send(.songs(.demoPlayStarted(id)))
            await send(.pipeline(.reset))
            await EffectEnvironment.shared.clearPipelineCache?(song.artist, song.title)

            let track = Track(
                artist: song.artist,
                title: song.title,
                album: song.album,
                duration: song.duration,
                bpm: song.bpm,
                musicalKey: song.musicalKey
            )

            // Route through playback actions so full flow remains:
            // UI -> AppAction -> Reducer -> Effects -> State -> View.
            await send(.playback(.demoTrackChanged(track)))
            await send(.playback(.positionUpdated(position: 0, isPlaying: true)))
            await send(.playback(.playingStateChanged(true)))
        }
    }

    // MARK: - Folder Scanning Effects

    /// Cancellation ID for folder scanning
    private static let scanCancellationId = EffectCancellationId.custom("folderScan")

    /// Scan a folder for audio files and extract metadata
    public static func scanFolder(_ folderURL: URL) -> Effect<AppAction> {
        .run(cancellationId: scanCancellationId) { send in
            // Find all audio files
            let audioFiles = AudioMetadata.findAudioFiles(in: folderURL)
            let total = audioFiles.count
            let folderName = folderURL.lastPathComponent

            guard total > 0 else {
                await send(.songs(.scanCompleted))
                return
            }

            await send(.songs(.scanStarted(total: total, folderName: folderName)))

            var foundCount = 0
            var existingIds: Set<SongID> = []

            // Get existing song IDs to check for duplicates
            if let module = await EffectEnvironment.shared.songsModule {
                let allSongs = await module.allSongs
                existingIds = Set(allSongs.map(\.id))
            }

            for (index, fileURL) in audioFiles.enumerated() {
                // Check for cancellation
                if Task.isCancelled { break }

                // Extract metadata
                if let metadata = await AudioMetadata.extractMetadata(from: fileURL) {
                    let songId = SongID(artist: metadata.artist, title: metadata.title)

                    // Skip if already exists
                    if !existingIds.contains(songId) {
                        existingIds.insert(songId)
                        foundCount += 1
                        await send(.songs(.songDiscovered(artist: metadata.artist, title: metadata.title)))
                    }
                }

                // Update progress every 10 files or on last file
                if index % 10 == 0 || index == total - 1 {
                    await send(.songs(.scanProgress(current: index + 1, found: foundCount)))
                }
            }

            if Task.isCancelled {
                await send(.songs(.scanCancelled))
            } else {
                await send(.songs(.scanCompleted))
            }
        }
    }

    /// Cancel ongoing folder scan
    public static func cancelScan() -> Effect<AppAction> {
        .cancel(id: scanCancellationId)
    }

    /// Add a discovered song to the database
    public static func addDiscoveredSong(artist: String, title: String) -> Effect<AppAction> {
        .fireAndForget {
            guard let module = await EffectEnvironment.shared.songsModule else { return }

            // Create minimal song - just artist and title
            await module.recordSong(
                artist: artist,
                title: title,
                album: "",
                duration: 0,
                bpm: 0,
                musicalKey: "",
                mood: "",
                energy: 0.5,
                valence: 0,
                keywords: [],
                themes: [],
                visualAdjectives: [],
                categories: [:],
                djPhase: nil,
                shaderName: nil,
                imagesFolderPath: nil,
                imagesCount: 0,
                hasLyrics: false,
                lyricsText: "",
                lyricsLineCount: 0,
                refrainCount: 0,
                incrementPlayCount: false
            )
        }
    }
}

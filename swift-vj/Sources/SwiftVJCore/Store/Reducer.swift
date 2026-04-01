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
        var followUp: [Effect<AppAction>] = [
            effect.map { AppAction.playback($0) }
        ]
        switch playbackAction {
        case .trackChanged(let track), .demoTrackChanged(let track):
            followUp.append(.send(.automation(.trackChanged(SongID(artist: track.artist, title: track.title)))))
        case .positionUpdated(let position, let isPlaying):
            followUp.append(.send(.automation(.playbackTick(position: position, isPlaying: isPlaying))))
        default:
            break
        }
        return .merge(followUp)

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

    case .automation(let automationAction):
        var automationState = state.automation
        let effect = automationReducer(state: &automationState, action: automationAction, appState: &state)
        state.automation = automationState
        return effect

    case .preview(let previewAction):
        return previewReducer(state: &state.preview, action: previewAction, songs: state.songs)

    // MARK: Persistence
    case .loadPersistedState:
        return PersistenceEffects.loadState()

    case .persistedStateLoaded(let persisted):
        persisted.apply(to: &state)
        state.ui.addLog("Loaded persisted state", level: .debug)
        var followUp: [Effect<AppAction>] = [
            .send(.render(.setEnabled(persisted.renderEnabled)))
        ]
        for output in RenderOutput.allCases {
            followUp.append(
                .send(.render(.setOutputEnabled(
                    output: output,
                    enabled: persisted.renderOutputs.isEnabled(output)
                )))
            )
        }
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
        effects.append(
            .send(.render(.setAISuggestedShader(
                name: result.shaderMatched ? result.shaderName : nil,
                phase: appState.render.effectivePhase
            )))
        )
        if let phase = appState.render.effectivePhase {
            effects.append(.send(.render(.advancePhasePlaylistsOnSongChange(phase: phase))))
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

    case .setOutputEnabled(let output, let enabled):
        let wasEnabled = state.outputs.isEnabled(output)
        state.outputs.setEnabled(enabled, for: output)
        if wasEnabled != enabled {
            appState.ui.addLog("\(output.displayName) output \(enabled ? "enabled" : "disabled")", level: .info)
            return .merge(
                RenderEffects.setOutputEnabled(output, enabled: enabled),
                .send(.persistState)
            )
        }
        return RenderEffects.setOutputEnabled(output, enabled: enabled)

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

    case .setShaderWorkspaceControls(let shaderName, let controls):
        if controls == .default {
            state.shaderControlsByShader.removeValue(forKey: shaderName)
        } else {
            state.shaderControlsByShader[shaderName] = controls
        }
        return .send(.persistState)

    case .resetShaderWorkspaceControls(let shaderName):
        state.shaderControlsByShader.removeValue(forKey: shaderName)
        appState.ui.addLog("Reset shader controls for \(shaderName)", level: .info)
        return .send(.persistState)

    case .setShaderAutoAdvanceOnSongChange(let enabled):
        state.shaderAutoAdvanceOnSongChange = enabled
        appState.ui.addLog("Shader auto-advance on song change \(enabled ? "enabled" : "disabled")", level: .info)
        return .send(.persistState)

    case .setMaskAutoAdvanceOnSongChange(let enabled):
        state.maskAutoAdvanceOnSongChange = enabled
        appState.ui.addLog("Mask auto-advance on song change \(enabled ? "enabled" : "disabled")", level: .info)
        return .send(.persistState)

    case .setAISuggestedShader(let name, let phase):
        state.aiSuggestedShaderName = name?.isEmpty == true ? nil : name
        state.aiSuggestedShaderPhase = phase
        return .none

    case .addShaderToPhasePlaylist(let phase, let shaderName, let activate):
        let phaseKey = phase.rawValue
        var playlist = state.shaderPlaylistByPhase[phaseKey] ?? []
        playlist.insert(shaderName, at: 0)
        state.shaderPlaylistByPhase[phaseKey] = playlist
        if activate {
            state.shaderPlaylistIndexByPhase[phaseKey] = 0
            appState.ui.addLog("Added + activated shader \(shaderName) for \(phase.displayName)", level: .info)
            return .send(.render(.selectShader(shaderName)))
        }
        if let currentIndex = state.shaderPlaylistIndexByPhase[phaseKey] {
            state.shaderPlaylistIndexByPhase[phaseKey] = currentIndex + 1
        }
        appState.ui.addLog("Added shader \(shaderName) to top of \(phase.displayName) playlist", level: .info)
        return .send(.persistState)

    case .addMaskToPhasePlaylist(let phase, let maskName, let activate):
        let phaseKey = phase.rawValue
        var playlist = state.maskPlaylistByPhase[phaseKey] ?? []
        playlist.insert(maskName, at: 0)
        state.maskPlaylistByPhase[phaseKey] = playlist
        if activate {
            state.maskPlaylistIndexByPhase[phaseKey] = 0
            appState.ui.addLog("Added + activated mask \(maskName) for \(phase.displayName)", level: .info)
            return .send(.render(.selectMaskShader(maskName)))
        }
        if let currentIndex = state.maskPlaylistIndexByPhase[phaseKey] {
            state.maskPlaylistIndexByPhase[phaseKey] = currentIndex + 1
        }
        appState.ui.addLog("Added mask \(maskName) to top of \(phase.displayName) playlist", level: .info)
        return .send(.persistState)

    case .removeShaderFromPhasePlaylist(let phase, let index):
        let phaseKey = phase.rawValue
        var playlist = state.shaderPlaylistByPhase[phaseKey] ?? []
        guard playlist.indices.contains(index) else { return .none }
        playlist.remove(at: index)
        state.shaderPlaylistByPhase[phaseKey] = playlist

        if playlist.isEmpty {
            state.shaderPlaylistIndexByPhase.removeValue(forKey: phaseKey)
            return .send(.persistState)
        }

        if let currentIndex = state.shaderPlaylistIndexByPhase[phaseKey] {
            let adjustedIndex: Int
            if currentIndex > index {
                adjustedIndex = max(0, currentIndex - 1)
            } else if currentIndex == index {
                adjustedIndex = min(index, playlist.count - 1)
            } else {
                adjustedIndex = currentIndex
            }
            state.shaderPlaylistIndexByPhase[phaseKey] = adjustedIndex
            if phase == state.effectivePhase, currentIndex == index {
                return .send(.render(.selectShader(playlist[adjustedIndex])))
            }
        }
        return .send(.persistState)

    case .removeMaskFromPhasePlaylist(let phase, let index):
        let phaseKey = phase.rawValue
        var playlist = state.maskPlaylistByPhase[phaseKey] ?? []
        guard playlist.indices.contains(index) else { return .none }
        playlist.remove(at: index)
        state.maskPlaylistByPhase[phaseKey] = playlist

        if playlist.isEmpty {
            state.maskPlaylistIndexByPhase.removeValue(forKey: phaseKey)
            return .send(.persistState)
        }

        if let currentIndex = state.maskPlaylistIndexByPhase[phaseKey] {
            let adjustedIndex: Int
            if currentIndex > index {
                adjustedIndex = max(0, currentIndex - 1)
            } else if currentIndex == index {
                adjustedIndex = min(index, playlist.count - 1)
            } else {
                adjustedIndex = currentIndex
            }
            state.maskPlaylistIndexByPhase[phaseKey] = adjustedIndex
            if phase == state.effectivePhase, currentIndex == index {
                return .send(.render(.selectMaskShader(playlist[adjustedIndex])))
            }
        }
        return .send(.persistState)

    case .moveShaderInPhasePlaylist(let phase, let fromIndices, let toIndex):
        let phaseKey = phase.rawValue
        let oldPlaylist = state.shaderPlaylistByPhase[phaseKey] ?? []
        let movedPlaylist = movePlaylistItems(oldPlaylist, fromIndices: fromIndices, toIndex: toIndex)
        guard movedPlaylist != oldPlaylist else { return .none }
        state.shaderPlaylistByPhase[phaseKey] = movedPlaylist
        if let currentIndex = state.shaderPlaylistIndexByPhase[phaseKey] {
            let oldOrder = Array(oldPlaylist.indices)
            let newOrder = movePlaylistItems(oldOrder, fromIndices: fromIndices, toIndex: toIndex)
            if let remappedIndex = newOrder.firstIndex(of: currentIndex) {
                state.shaderPlaylistIndexByPhase[phaseKey] = remappedIndex
            } else {
                state.shaderPlaylistIndexByPhase[phaseKey] = min(currentIndex, max(0, movedPlaylist.count - 1))
            }
        }
        return .send(.persistState)

    case .moveMaskInPhasePlaylist(let phase, let fromIndices, let toIndex):
        let phaseKey = phase.rawValue
        let oldPlaylist = state.maskPlaylistByPhase[phaseKey] ?? []
        let movedPlaylist = movePlaylistItems(oldPlaylist, fromIndices: fromIndices, toIndex: toIndex)
        guard movedPlaylist != oldPlaylist else { return .none }
        state.maskPlaylistByPhase[phaseKey] = movedPlaylist
        if let currentIndex = state.maskPlaylistIndexByPhase[phaseKey] {
            let oldOrder = Array(oldPlaylist.indices)
            let newOrder = movePlaylistItems(oldOrder, fromIndices: fromIndices, toIndex: toIndex)
            if let remappedIndex = newOrder.firstIndex(of: currentIndex) {
                state.maskPlaylistIndexByPhase[phaseKey] = remappedIndex
            } else {
                state.maskPlaylistIndexByPhase[phaseKey] = min(currentIndex, max(0, movedPlaylist.count - 1))
            }
        }
        return .send(.persistState)

    case .activateShaderInPhasePlaylist(let phase, let index):
        let phaseKey = phase.rawValue
        let playlist = state.shaderPlaylistByPhase[phaseKey] ?? []
        guard playlist.indices.contains(index) else { return .none }
        state.shaderPlaylistIndexByPhase[phaseKey] = index
        return .send(.render(.selectShader(playlist[index])))

    case .activateMaskInPhasePlaylist(let phase, let index):
        let phaseKey = phase.rawValue
        let playlist = state.maskPlaylistByPhase[phaseKey] ?? []
        guard playlist.indices.contains(index) else { return .none }
        state.maskPlaylistIndexByPhase[phaseKey] = index
        return .send(.render(.selectMaskShader(playlist[index])))

    case .advancePhasePlaylistsOnSongChange(let phase):
        let phaseKey = phase.rawValue
        var followUp: [Effect<AppAction>] = []

        if state.shaderAutoAdvanceOnSongChange {
            let shaderPlaylist = state.shaderPlaylistByPhase[phaseKey] ?? []
            if !shaderPlaylist.isEmpty {
                let currentIndex = state.shaderPlaylistCurrentIndex(for: phase) ?? -1
                let nextIndex = (currentIndex + 1 + shaderPlaylist.count) % shaderPlaylist.count
                state.shaderPlaylistIndexByPhase[phaseKey] = nextIndex
                let shaderName = shaderPlaylist[nextIndex]
                appState.ui.addLog("Performance shader: \(shaderName) (\(phase.displayName))", level: .info)
                followUp.append(.send(.render(.selectShader(shaderName))))
            }
        }

        if state.maskAutoAdvanceOnSongChange {
            let maskPlaylist = state.maskPlaylistByPhase[phaseKey] ?? []
            if !maskPlaylist.isEmpty {
                let currentIndex = state.maskPlaylistCurrentIndex(for: phase) ?? -1
                let nextIndex = (currentIndex + 1 + maskPlaylist.count) % maskPlaylist.count
                state.maskPlaylistIndexByPhase[phaseKey] = nextIndex
                let maskName = maskPlaylist[nextIndex]
                appState.ui.addLog("Performance mask: \(maskName) (\(phase.displayName))", level: .info)
                followUp.append(.send(.render(.selectMaskShader(maskName))))
            }
        }

        return followUp.isEmpty ? .none : .merge(followUp)

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

private func movePlaylistItems<T>(
    _ values: [T],
    fromIndices: [Int],
    toIndex: Int
) -> [T] {
    guard !values.isEmpty else { return values }
    let uniqueSorted = Array(Set(fromIndices.filter { values.indices.contains($0) })).sorted()
    guard !uniqueSorted.isEmpty else { return values }

    var result = values
    let movingItems = uniqueSorted.map { result[$0] }
    for index in uniqueSorted.reversed() {
        result.remove(at: index)
    }

    let removedBeforeTarget = uniqueSorted.filter { $0 < toIndex }.count
    let adjustedTarget = max(0, min(toIndex - removedBeforeTarget, result.count))
    result.insert(contentsOf: movingItems, at: adjustedTarget)
    return result
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

    case .setOscAudioMessagesEnabled(let enabled):
        state.oscAudioMessagesEnabled = enabled
        return .none

    case .setOscFilter(let filter):
        state.oscFilter = filter
        return .none

    case .setShaderCatalogSearchText(let query):
        state.shaderCatalog.searchText = query
        return .none

    case .setShaderCatalogFolder(let folder):
        state.shaderCatalog.selectedFolder = folder
        return .none

    case .setShaderCatalogBadgeFilter(let filter):
        state.shaderCatalog.badgeFilter = filter
        return .none

    case .setShaderCatalogPhaseFilter(let phase):
        state.shaderCatalog.phaseFilter = phase
        return .none

    case .setShaderCatalogSortOrder(let order):
        state.shaderCatalog.sortOrder = order
        return .none

    case .setShaderCatalogViewMode(let mode):
        state.shaderCatalog.viewMode = mode
        return .none

    case .setShaderCatalogSelection(let names):
        state.shaderCatalog.selectedShaders = names
        return .none

    case .toggleShaderCatalogSelection(let name):
        state.shaderCatalog.toggleSelection(name)
        return .none

    case .clearShaderCatalogSelection:
        state.shaderCatalog.selectedShaders.removeAll()
        return .none

    case .setShaderCatalogBulkPhases(let phases):
        state.shaderCatalog.bulkPhases = phases
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
                // Command targets are tracked by the app-layer process registry.
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

    case .terminateTargetRequested(let id):
        guard let target = state.targets.first(where: { $0.id == id }) else {
            state.lastError = "Terminate target not found."
            state.revision &+= 1
            return .none
        }
        state.lastError = nil
        state.revision &+= 1
        return LauncherEffects.terminateTarget(target)
            .map { AppAction.launcher($0) }

    case .terminateAllRequested:
        guard !state.targets.isEmpty else { return .none }
        state.lastError = nil
        state.revision &+= 1
        return LauncherEffects.terminateAll(state.targets)
            .map { AppAction.launcher($0) }

    case .terminateTargetCompleted(let id, let terminated, let error):
        if terminated {
            state.runningTargetIDs.remove(id)
            state.lastError = nil
        }
        if let error, !error.isEmpty {
            state.lastError = error
            appState.ui.addLog("Launcher: \(error)", level: .error)
        } else if terminated {
            appState.ui.addLog("Launcher: terminated target", level: .info)
        }
        state.revision &+= 1
        return .none

    case .terminateAllCompleted(let report):
        state.runningTargetIDs = report.runningTargetIDs
        if let firstError = report.failedTargetErrors.values.sorted().first {
            state.lastError = firstError
        } else {
            state.lastError = nil
        }
        let terminated = report.terminatedTargetIDs.count
        let notRunning = report.notRunningTargetIDs.count
        let failed = report.failedTargetErrors.count
        state.lastLaunchSummary = "Stopped \(terminated), not running \(notRunning), failed \(failed)"
        appState.ui.addLog("Launcher: \(state.lastLaunchSummary ?? "terminate completed")", level: failed > 0 ? .warning : .info)
        state.revision &+= 1
        return .none

    case .addKnownTarget(let knownTarget):
        let target = knownTarget.launchTarget
        if state.targets.contains(where: { $0.normalizedIdentity == target.normalizedIdentity }) {
            state.lastError = "\(target.displayName) is already configured."
            state.revision &+= 1
            return .none
        }
        state.targets.append(target)
        state.lastError = nil
        state.revision &+= 1
        appState.ui.addLog("Launcher: added \(target.displayName)", level: .info)
        return .send(.persistState)

    case .setRigPreset(let preset):
        state.rigPreset = preset
        state.revision &+= 1
        return .send(.persistState)

    case .startRig:
        var added = 0
        for known in state.rigPreset.targets {
            let target = known.launchTarget
            if !state.targets.contains(where: { $0.normalizedIdentity == target.normalizedIdentity }) {
                state.targets.append(target)
                added += 1
            }
        }

        let rigIdentities = Set(state.rigPreset.targets.map { $0.launchTarget.normalizedIdentity })
        let rigTargets = state.targets.filter { rigIdentities.contains($0.normalizedIdentity) }

        guard !rigTargets.isEmpty else {
            state.lastError = "No targets configured in rig preset."
            state.revision &+= 1
            return .none
        }

        state.isLaunchingAll = true
        state.lastError = nil
        state.revision &+= 1
        if added > 0 {
            appState.ui.addLog("Launcher: added \(added) rig target(s)", level: .info)
        }
        appState.ui.addLog("Launcher: starting \(state.rigPreset.name) (\(rigTargets.count) targets)", level: .info)
        return .merge([
            added > 0 ? .send(.persistState) : .none,
            LauncherEffects.launchTargetsIfNeeded(rigTargets)
                .map { AppAction.launcher($0) }
        ])

    case .stopRig:
        let rigIdentities = Set(state.rigPreset.targets.map { $0.launchTarget.normalizedIdentity })
        let rigTargets = state.targets.filter {
            rigIdentities.contains($0.normalizedIdentity)
        }
        guard !rigTargets.isEmpty else { return .none }
        state.lastError = nil
        state.revision &+= 1
        appState.ui.addLog("Launcher: stopping \(state.rigPreset.name)", level: .info)
        return LauncherEffects.terminateAll(rigTargets)
            .map { AppAction.launcher($0) }
    }
}

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

    case .songDiscovered(let artist, let title, let audioFilePath):
        let songId = SongID(artist: artist, title: title)

        // Check for duplicate in existing displayed songs
        let existingSong = state.displayedSongs.first { $0.id == songId }

        if let existing = existingSong {
            // Song exists but may lack audioFilePath — update it if we found the file
            let hasNoAudio = existing.audioFilePath == nil || existing.audioFilePath?.isEmpty == true
            if hasNoAudio, let path = audioFilePath {
                // Also update the in-memory displayed song immediately
                if let idx = state.displayedSongs.firstIndex(where: { $0.id == songId }) {
                    state.displayedSongs[idx] = existing.withAudioFilePath(path)
                }
                return SongsEffects.setAudioFilePath(songId: songId, path: path)
            }
            return .none
        } else {
            // Create minimal song entry and add to store
            return SongsEffects.addDiscoveredSong(artist: artist, title: title, audioFilePath: audioFilePath)
        }

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

// MARK: - Automation Reducer

public func automationReducer(
    state: inout AutomationSubState,
    action: AutomationAction,
    appState: inout AppState
) -> Effect<AppAction> {
    switch action {
    case .setEnabled(let enabled):
        state.isEnabled = enabled
        appState.ui.addLog("Automation \(enabled ? "enabled" : "disabled")", level: .info)
        return .send(.persistState)

    case .setAutoRecordEnabled(let enabled):
        state.autoRecordEnabled = enabled
        appState.ui.addLog("Automation auto-record \(enabled ? "enabled" : "disabled")", level: .info)
        return .send(.persistState)

    case .setAutoRecordPrefixes(let prefixes):
        let normalized = prefixes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        state.autoRecordPrefixes = normalized
        appState.ui.addLog("Automation record prefixes updated (\(normalized.count))", level: .info)
        return .send(.persistState)

    case .selectSong(let songID):
        state.selectedSongId = songID
        return .none

    case .trackChanged(let songID):
        state.playbackSongId = songID
        if state.selectedSongId == nil {
            state.selectedSongId = songID
        }
        return .none

    case .ensureTimeline(let songID):
        _ = ensureAutomationTimeline(for: songID, state: &state)
        return .send(.persistState)

    case .setTimeline(let songID, let timeline):
        state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
        return .send(.persistState)

    case .clearTimeline(let songID):
        state.timelineBySongId[songID.rawValue] = SongAutomationTimeline.empty
        state.firedCueIdsBySongId[songID.rawValue] = []
        state.lastLaneValueBySongId[songID.rawValue] = [:]
        state.lastPlaybackPositionBySongId[songID.rawValue] = 0
        state.lastRecordedOSCBySongId[songID.rawValue] = [:]
        return .send(.persistState)

    case .addCue(let songID, let cue):
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        timeline.cues.append(cue)
        state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
        return .send(.persistState)

    case .updateCue(let songID, let cue):
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        if let index = timeline.cues.firstIndex(where: { $0.id == cue.id }) {
            timeline.cues[index] = cue
            state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
            return .send(.persistState)
        }
        return .none

    case .removeCue(let songID, let cueID):
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        timeline.cues.removeAll { $0.id == cueID }
        state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
        state.firedCueIdsBySongId[songID.rawValue]?.remove(cueID)
        return .send(.persistState)

    case .addValueLane(let songID, let lane):
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        guard !timeline.valueLanes.contains(where: { $0.id == lane.id }) else { return .none }
        timeline.valueLanes.append(lane)
        state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
        return .send(.persistState)

    case .removeValueLane(let songID, let laneID):
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        timeline.valueLanes.removeAll { $0.id == laneID }
        state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
        state.lastLaneValueBySongId[songID.rawValue]?[laneID] = nil
        return .send(.persistState)

    case .addValuePoint(let songID, let laneID, let point):
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        if let laneIndex = timeline.valueLanes.firstIndex(where: { $0.id == laneID }) {
            timeline.valueLanes[laneIndex].points.append(point)
            state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
            return .send(.persistState)
        }
        return .none

    case .updateValuePoint(let songID, let laneID, let point):
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        guard let laneIndex = timeline.valueLanes.firstIndex(where: { $0.id == laneID }),
              let pointIndex = timeline.valueLanes[laneIndex].points.firstIndex(where: { $0.id == point.id }) else {
            return .none
        }
        timeline.valueLanes[laneIndex].points[pointIndex] = point
        state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
        return .send(.persistState)

    case .removeValuePoint(let songID, let laneID, let pointID):
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        guard let laneIndex = timeline.valueLanes.firstIndex(where: { $0.id == laneID }) else {
            return .none
        }
        timeline.valueLanes[laneIndex].points.removeAll { $0.id == pointID }
        state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
        return .send(.persistState)

    case .recordLedFXAction(let songID, let position, let action):
        guard state.isEnabled, state.autoRecordEnabled else { return .none }
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        var changed = false

        switch action {
        case .activateScene(let sceneID):
            timeline.cues.append(
                AutomationCue(
                    timeSec: position,
                    actionType: .ledfxActivateScene,
                    value: sceneID,
                    source: "auto-ledfx"
                )
            )
            changed = true
        case .activatePlaylist(let playlistID):
            timeline.cues.append(
                AutomationCue(
                    timeSec: position,
                    actionType: .ledfxActivatePlaylist,
                    value: playlistID,
                    source: "auto-ledfx"
                )
            )
            changed = true
        case .stopPlaylist:
            timeline.cues.append(
                AutomationCue(
                    timeSec: position,
                    actionType: .ledfxStopPlaylist,
                    value: "",
                    source: "auto-ledfx"
                )
            )
            changed = true
        case .setVirtualBrightness(let virtualID, let brightness):
            let laneID = "ledfx-brightness:\(virtualID)"
            if let laneIndex = timeline.valueLanes.firstIndex(where: { $0.id == laneID }) {
                timeline.valueLanes[laneIndex].points.append(
                    AutomationValuePoint(timeSec: position, value: brightness)
                )
            } else {
                timeline.valueLanes.append(
                    AutomationValueLane(
                        id: laneID,
                        displayName: "Brightness \(virtualID)",
                        targetType: .ledfxVirtualBrightness,
                        target: virtualID,
                        points: [AutomationValuePoint(timeSec: position, value: brightness)]
                    )
                )
            }
            changed = true
        default:
            break
        }

        guard changed else { return .none }
        state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
        return .send(.persistState)

    case .recordOSC(let songID, let position, let target, let address, let args, let source):
        guard state.isEnabled, state.autoRecordEnabled else { return .none }
        guard shouldRecordOSCAddress(address, prefixes: state.autoRecordPrefixes) else { return .none }
        var timeline = ensureAutomationTimeline(for: songID, state: &state)
        let sampleKey = "\(target.rawValue):\(address)"
        var samplesByAddress = state.lastRecordedOSCBySongId[songID.rawValue] ?? [:]
        let previousSample = samplesByAddress[sampleKey]
        guard shouldRecordOSCSample(
            previous: previousSample,
            currentTime: position,
            currentArgs: args,
            maxHz: state.autoRecordMaxHz,
            minDelta: state.autoRecordMinDelta
        ) else {
            return .none
        }
        samplesByAddress[sampleKey] = AutomationRecordedOSCSample(timeSec: max(0, position), args: args)
        state.lastRecordedOSCBySongId[songID.rawValue] = samplesByAddress

        timeline.cues.append(
            AutomationCue(
                timeSec: position,
                actionType: .osc,
                value: address,
                oscTarget: target,
                args: args,
                source: source ?? "auto-osc"
            )
        )
        state.timelineBySongId[songID.rawValue] = normalizedTimeline(timeline)
        return .send(.persistState)

    case .playbackTick(let position, let isPlaying):
        guard let songID = state.playbackSongId ?? state.selectedSongId else { return .none }
        let songKey = songID.rawValue
        let previous = state.lastPlaybackPositionBySongId[songKey] ?? position
        state.lastPlaybackPositionBySongId[songKey] = position

        guard state.isEnabled,
              isPlaying,
              let timeline = state.timelineBySongId[songKey],
              timeline.playbackEnabled else {
            return .none
        }

        var firedCueIDs = state.firedCueIdsBySongId[songKey] ?? Set<UUID>()
        let seekBack = position + 0.05 < previous

        if seekBack {
            let keep = Set(timeline.cues.filter { $0.timeSec <= position }.map(\.id))
            firedCueIDs = firedCueIDs.intersection(keep)
        }

        var commands: [AutomationRuntimeCommand] = []
        if !seekBack {
            for cue in timeline.cues where cue.timeSec > previous && cue.timeSec <= position {
                if firedCueIDs.insert(cue.id).inserted {
                    commands.append(.cue(cue))
                }
            }
        }

        var laneValues = state.lastLaneValueBySongId[songKey] ?? [:]
        for lane in timeline.valueLanes {
            guard lane.targetType == .ledfxVirtualBrightness,
                  let value = sampleAutomationValue(points: lane.points, at: position) else {
                continue
            }
            if let last = laneValues[lane.id], abs(last - value) < 0.01 {
                continue
            }
            laneValues[lane.id] = value
            commands.append(.ledfxBrightness(virtualID: lane.target, value: value))
        }

        state.lastLaneValueBySongId[songKey] = laneValues
        state.firedCueIdsBySongId[songKey] = firedCueIDs

        guard !commands.isEmpty else { return .none }
        return .merge(commands.map(AutomationEffects.execute))
    }
}

private enum AutomationRuntimeCommand {
    case cue(AutomationCue)
    case ledfxBrightness(virtualID: String, value: Double)
}

private func ensureAutomationTimeline(
    for songID: SongID,
    state: inout AutomationSubState
) -> SongAutomationTimeline {
    if let existing = state.timelineBySongId[songID.rawValue] {
        return existing
    }
    let timeline = SongAutomationTimeline(
        valueLanes: [
            AutomationValueLane(
                id: "ledfx-brightness:main",
                displayName: "Brightness main",
                targetType: .ledfxVirtualBrightness,
                target: "main",
                points: []
            )
        ]
    )
    state.timelineBySongId[songID.rawValue] = timeline
    return timeline
}

private func normalizedTimeline(_ timeline: SongAutomationTimeline) -> SongAutomationTimeline {
    let sortedCues = timeline.cues.sorted { lhs, rhs in
        if lhs.timeSec == rhs.timeSec {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.timeSec < rhs.timeSec
    }
    let sortedLanes = timeline.valueLanes.map { lane in
        var copy = lane
        copy.points = lane.points.sorted { lhs, rhs in
            if lhs.timeSec == rhs.timeSec {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.timeSec < rhs.timeSec
        }
        return copy
    }
    return SongAutomationTimeline(
        cues: sortedCues,
        valueLanes: sortedLanes,
        updatedAt: Date(),
        playbackEnabled: timeline.playbackEnabled
    )
}

private func sampleAutomationValue(
    points: [AutomationValuePoint],
    at position: Double
) -> Double? {
    guard !points.isEmpty else { return nil }
    let sorted = points.sorted { $0.timeSec < $1.timeSec }
    if position <= sorted[0].timeSec {
        return sorted[0].value
    }
    if position >= sorted[sorted.count - 1].timeSec {
        return sorted[sorted.count - 1].value
    }
    for index in 1..<sorted.count {
        let left = sorted[index - 1]
        let right = sorted[index]
        guard position >= left.timeSec, position <= right.timeSec else { continue }
        let span = right.timeSec - left.timeSec
        guard span > 0 else { return right.value }
        let t = (position - left.timeSec) / span
        return left.value + (right.value - left.value) * t
    }
    return sorted.last?.value
}

private func shouldRecordOSCAddress(_ address: String, prefixes: [String]) -> Bool {
    let normalizedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedAddress.isEmpty else { return false }
    guard !prefixes.isEmpty else { return true }
    return prefixes.contains { prefix in
        let normalizedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrefix.isEmpty else { return false }
        return normalizedAddress.hasPrefix(normalizedPrefix)
    }
}

private func shouldRecordOSCSample(
    previous: AutomationRecordedOSCSample?,
    currentTime: Double,
    currentArgs: [AutomationOSCValue],
    maxHz: Double,
    minDelta: Double
) -> Bool {
    guard let previous else { return true }
    let minInterval = maxHz > 0 ? 1.0 / maxHz : 0
    if currentTime - previous.timeSec < minInterval {
        return false
    }
    return hasSignificantOSCArgsChange(previous.args, currentArgs, minDelta: minDelta)
}

private func hasSignificantOSCArgsChange(
    _ lhs: [AutomationOSCValue],
    _ rhs: [AutomationOSCValue],
    minDelta: Double
) -> Bool {
    if lhs.count != rhs.count { return true }
    for (left, right) in zip(lhs, rhs) {
        switch (left, right) {
        case (.float(let l), .float(let r)):
            if abs(l - r) >= minDelta { return true }
        case (.int(let l), .int(let r)):
            if abs(Double(l) - Double(r)) >= minDelta { return true }
        case (.int(let l), .float(let r)):
            if abs(Double(l) - r) >= minDelta { return true }
        case (.float(let l), .int(let r)):
            if abs(l - Double(r)) >= minDelta { return true }
        case (.string(let l), .string(let r)):
            if l != r { return true }
        default:
            return true
        }
    }
    return false
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

    public static func setOutputEnabled(_ output: RenderOutput, enabled: Bool) -> Effect<AppAction> {
        .run { _ in
            await EffectEnvironment.shared.setRenderOutputEnabled?(output, enabled)
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

enum AutomationEffects {
    fileprivate static func execute(_ command: AutomationRuntimeCommand) -> Effect<AppAction> {
        switch command {
        case .ledfxBrightness(let virtualID, let value):
            return .send(.ledfx(.setVirtualBrightness(id: virtualID, brightness: value)))

        case .cue(let cue):
            switch cue.actionType {
            case .ledfxActivateScene:
                guard !cue.value.isEmpty else { return .none }
                return .send(.ledfx(.activateScene(cue.value)))
            case .ledfxActivatePlaylist:
                guard !cue.value.isEmpty else { return .none }
                return .send(.ledfx(.activatePlaylist(cue.value)))
            case .ledfxStopPlaylist:
                return .send(.ledfx(.stopPlaylist))
            case .osc:
                guard let target = cue.oscTarget else {
                    return .send(.ui(.log("Automation cue missing OSC target for \(cue.value)", .warning)))
                }
                return .run { send in
                    do {
                        try await EffectEnvironment.shared.sendOSC?(
                            target.rawValue,
                            cue.value,
                            automationOSCValuesToSendable(cue.args),
                            cue.source ?? "automation-replay"
                        )
                    } catch {
                        await send(.ui(.log("Automation OSC failed (\(cue.value)): \(error.localizedDescription)", .error)))
                    }
                }
            }
        }
    }
}

private func automationOSCValuesToSendable(_ values: [AutomationOSCValue]) -> [any Sendable] {
    values.map { value in
        switch value {
        case .int(let intValue):
            return intValue
        case .float(let floatValue):
            return floatValue
        case .string(let stringValue):
            return stringValue
        case .bool(let boolValue):
            return boolValue
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

    public static func terminateTarget(_ target: LaunchTarget) -> Effect<LauncherAction> {
        .run { send in
            guard let handler = await EffectEnvironment.shared.launcherHandler else {
                await send(.terminateTargetCompleted(id: target.id, terminated: false, error: "Launcher unavailable"))
                return
            }
            let result = await handler.terminateTarget(target)
            await send(.terminateTargetCompleted(id: target.id, terminated: result.terminated, error: result.error))
        }
    }

    public static func terminateAll(_ targets: [LaunchTarget]) -> Effect<LauncherAction> {
        .run { send in
            guard let handler = await EffectEnvironment.shared.launcherHandler else {
                await send(.terminateAllCompleted(
                    LauncherTerminateReport(
                        failedTargetErrors: ["launcher": "Launcher unavailable"],
                        runningTargetIDs: []
                    )
                ))
                return
            }
            let report = await handler.terminateAll(targets)
            await send(.terminateAllCompleted(report))
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
            let renderOutputs = RenderOutputsState(
                shader: (UserDefaults.standard.object(forKey: "renderOutput.shader") as? Bool) ?? true,
                mask: (UserDefaults.standard.object(forKey: "renderOutput.mask") as? Bool) ?? true,
                lyrics: (UserDefaults.standard.object(forKey: "renderOutput.lyrics") as? Bool) ?? true,
                refrain: (UserDefaults.standard.object(forKey: "renderOutput.refrain") as? Bool) ?? true,
                songInfo: (UserDefaults.standard.object(forKey: "renderOutput.songInfo") as? Bool) ?? true,
                image: (UserDefaults.standard.object(forKey: "renderOutput.image") as? Bool) ?? true
            )
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
            let shaderControlsByShader: [String: ShaderWorkspaceControls]
            if let controlsData = UserDefaults.standard.data(forKey: "shaderControlsByShader"),
               let decoded = try? JSONDecoder().decode([String: ShaderWorkspaceControls].self, from: controlsData) {
                shaderControlsByShader = decoded
            } else {
                shaderControlsByShader = [:]
            }
            let shaderPlaylistByPhase: [String: [String]]
            if let playlistData = UserDefaults.standard.data(forKey: "shaderPlaylistByPhase"),
               let decoded = try? JSONDecoder().decode([String: [String]].self, from: playlistData) {
                shaderPlaylistByPhase = decoded
            } else {
                shaderPlaylistByPhase = [:]
            }
            let maskPlaylistByPhase: [String: [String]]
            if let playlistData = UserDefaults.standard.data(forKey: "maskPlaylistByPhase"),
               let decoded = try? JSONDecoder().decode([String: [String]].self, from: playlistData) {
                maskPlaylistByPhase = decoded
            } else {
                maskPlaylistByPhase = [:]
            }
            let shaderPlaylistIndexByPhase: [String: Int]
            if let indexData = UserDefaults.standard.data(forKey: "shaderPlaylistIndexByPhase"),
               let decoded = try? JSONDecoder().decode([String: Int].self, from: indexData) {
                shaderPlaylistIndexByPhase = decoded
            } else {
                shaderPlaylistIndexByPhase = [:]
            }
            let maskPlaylistIndexByPhase: [String: Int]
            if let indexData = UserDefaults.standard.data(forKey: "maskPlaylistIndexByPhase"),
               let decoded = try? JSONDecoder().decode([String: Int].self, from: indexData) {
                maskPlaylistIndexByPhase = decoded
            } else {
                maskPlaylistIndexByPhase = [:]
            }
            let shaderAutoAdvanceOnSongChange = (UserDefaults.standard.object(forKey: "shaderAutoAdvanceOnSongChange") as? Bool) ?? false
            let maskAutoAdvanceOnSongChange = (UserDefaults.standard.object(forKey: "maskAutoAdvanceOnSongChange") as? Bool) ?? false
            let automationEnabled = (UserDefaults.standard.object(forKey: "automationEnabled") as? Bool) ?? true
            let automationAutoRecordEnabled = (UserDefaults.standard.object(forKey: "automationAutoRecordEnabled") as? Bool) ?? false
            let automationAutoRecordPrefixes: [String]
            if UserDefaults.standard.object(forKey: "automationAutoRecordPrefixes") != nil {
                automationAutoRecordPrefixes = UserDefaults.standard.stringArray(forKey: "automationAutoRecordPrefixes") ?? []
            } else {
                automationAutoRecordPrefixes = AutomationSubState().autoRecordPrefixes
            }
            let automationTimelinesBySongId: [String: SongAutomationTimeline]
            if let data = UserDefaults.standard.data(forKey: "automationTimelinesBySongId"),
               let decoded = try? JSONDecoder().decode([String: SongAutomationTimeline].self, from: data) {
                automationTimelinesBySongId = decoded
            } else {
                automationTimelinesBySongId = [:]
            }

            let persisted = PersistedState(
                renderEnabled: renderEnabled,
                renderOutputs: renderOutputs,
                shaderControlsByShader: shaderControlsByShader,
                shaderPlaylistByPhase: shaderPlaylistByPhase,
                maskPlaylistByPhase: maskPlaylistByPhase,
                shaderPlaylistIndexByPhase: shaderPlaylistIndexByPhase,
                maskPlaylistIndexByPhase: maskPlaylistIndexByPhase,
                shaderAutoAdvanceOnSongChange: shaderAutoAdvanceOnSongChange,
                maskAutoAdvanceOnSongChange: maskAutoAdvanceOnSongChange,
                selectedShader: shader,
                selectedMaskShader: maskShader,
                currentPhase: phase,
                playbackSource: source,
                launcherTargets: launcherTargets,
                automationEnabled: automationEnabled,
                automationAutoRecordEnabled: automationAutoRecordEnabled,
                automationAutoRecordPrefixes: automationAutoRecordPrefixes,
                automationTimelinesBySongId: automationTimelinesBySongId
            )

            await send(.persistedStateLoaded(persisted))
        }
    }

    public static func saveState(_ state: PersistedState) -> Effect<AppAction> {
        .fireAndForget {
            UserDefaults.standard.set(state.renderEnabled, forKey: "renderEnabled")
            UserDefaults.standard.set(state.renderOutputs.shader, forKey: "renderOutput.shader")
            UserDefaults.standard.set(state.renderOutputs.mask, forKey: "renderOutput.mask")
            UserDefaults.standard.set(state.renderOutputs.lyrics, forKey: "renderOutput.lyrics")
            UserDefaults.standard.set(state.renderOutputs.refrain, forKey: "renderOutput.refrain")
            UserDefaults.standard.set(state.renderOutputs.songInfo, forKey: "renderOutput.songInfo")
            UserDefaults.standard.set(state.renderOutputs.image, forKey: "renderOutput.image")
            if let controlsData = try? JSONEncoder().encode(state.shaderControlsByShader) {
                UserDefaults.standard.set(controlsData, forKey: "shaderControlsByShader")
            } else {
                UserDefaults.standard.removeObject(forKey: "shaderControlsByShader")
            }
            if let playlistData = try? JSONEncoder().encode(state.shaderPlaylistByPhase) {
                UserDefaults.standard.set(playlistData, forKey: "shaderPlaylistByPhase")
            } else {
                UserDefaults.standard.removeObject(forKey: "shaderPlaylistByPhase")
            }
            if let playlistData = try? JSONEncoder().encode(state.maskPlaylistByPhase) {
                UserDefaults.standard.set(playlistData, forKey: "maskPlaylistByPhase")
            } else {
                UserDefaults.standard.removeObject(forKey: "maskPlaylistByPhase")
            }
            if let indexData = try? JSONEncoder().encode(state.shaderPlaylistIndexByPhase) {
                UserDefaults.standard.set(indexData, forKey: "shaderPlaylistIndexByPhase")
            } else {
                UserDefaults.standard.removeObject(forKey: "shaderPlaylistIndexByPhase")
            }
            if let indexData = try? JSONEncoder().encode(state.maskPlaylistIndexByPhase) {
                UserDefaults.standard.set(indexData, forKey: "maskPlaylistIndexByPhase")
            } else {
                UserDefaults.standard.removeObject(forKey: "maskPlaylistIndexByPhase")
            }
            UserDefaults.standard.set(state.shaderAutoAdvanceOnSongChange, forKey: "shaderAutoAdvanceOnSongChange")
            UserDefaults.standard.set(state.maskAutoAdvanceOnSongChange, forKey: "maskAutoAdvanceOnSongChange")
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
            UserDefaults.standard.set(state.automationEnabled, forKey: "automationEnabled")
            UserDefaults.standard.set(state.automationAutoRecordEnabled, forKey: "automationAutoRecordEnabled")
            UserDefaults.standard.set(state.automationAutoRecordPrefixes, forKey: "automationAutoRecordPrefixes")
            if let automationData = try? JSONEncoder().encode(state.automationTimelinesBySongId) {
                UserDefaults.standard.set(automationData, forKey: "automationTimelinesBySongId")
            } else {
                UserDefaults.standard.removeObject(forKey: "automationTimelinesBySongId")
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
                    foundCount += 1
                    await send(.songs(.songDiscovered(artist: metadata.artist, title: metadata.title, audioFilePath: fileURL.path)))
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
    public static func addDiscoveredSong(artist: String, title: String, audioFilePath: String? = nil) -> Effect<AppAction> {
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
                audioFilePath: audioFilePath,
                incrementPlayCount: false
            )
        }
    }

    /// Update audio file path on an existing song
    public static func setAudioFilePath(songId: SongID, path: String) -> Effect<AppAction> {
        .run { send in
            guard let module = await EffectEnvironment.shared.songsModule else { return }
            await module.setAudioFilePath(path, for: songId)
            await send(.songs(.refreshList))
        }
    }
}

// MARK: - Preview Reducer

/// Reducer for song preview playback.
/// Pure state mutations + effects for audio playback.
public func previewReducer(
    state: inout PreviewSubState,
    action: PreviewAction,
    songs: SongsSubState
) -> Effect<AppAction> {
    switch action {
    case .play(let songId, let overrideAudioPath):
        // Resolve audio file path: override > Song lookup
        let song = songs.displayedSongs.first(where: { $0.id == songId })
        let filePath = overrideAudioPath ?? song?.audioFilePath
        guard let filePath, !filePath.isEmpty else {
            print("[Preview] No audio file for: \(song?.title ?? songId.rawValue) by \(song?.artist ?? "?")")
            return .none
        }

        let fileURL = URL(fileURLWithPath: filePath)
        let duration = song?.duration ?? 0
        // When duration is unknown (0), let the player start at previewStartSeconds anyway;
        // it will clamp internally. When known, cap to duration-1.
        let startSeconds = duration > 1
            ? min(Double(state.previewStartSeconds), duration - 1)
            : Double(state.previewStartSeconds)

        state.currentSongId = songId
        state.isPlaying = true
        state.currentPosition = startSeconds
        state.duration = duration
        state.audioFilePath = filePath

        return .fireAndForget {
            await EffectEnvironment.shared.playPreview?(fileURL, startSeconds)
        }

    case .pause:
        state.isPlaying = false
        return .fireAndForget {
            await EffectEnvironment.shared.pausePreview?()
        }

    case .resume:
        state.isPlaying = true
        return .fireAndForget {
            await EffectEnvironment.shared.resumePreview?()
        }

    case .stop:
        state.currentSongId = nil
        state.isPlaying = false
        state.currentPosition = 0
        state.duration = 0
        state.audioFilePath = nil
        return .fireAndForget {
            await EffectEnvironment.shared.stopPreview?()
        }

    case .seekTo(let position):
        state.currentPosition = position
        return .fireAndForget {
            await EffectEnvironment.shared.seekPreview?(position)
        }

    case .setPreviewStartSeconds(let seconds):
        state.previewStartSeconds = max(0, seconds)
        return .none

    case .positionUpdated(let position, let duration):
        state.currentPosition = position
        state.duration = duration
        return .none

    case .playbackFinished:
        state.isPlaying = false
        return .none
    }
}

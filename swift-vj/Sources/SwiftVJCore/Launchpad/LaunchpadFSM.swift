// LaunchpadFSM.swift - Pure Finite State Machine for Launchpad
// Phase 5: MIDI Controller
//
// All functions are pure: same input = same output, no side effects.
// Returns new state and list of effects to be executed by imperative shell.

import Foundation

// MARK: - Button Constants

/// Special button identifiers for Learn mode
public enum LaunchpadButton {
    /// Bottom-right scene button triggers learn mode
    public static let learn = ButtonId(x: 8, y: 0)
    
    /// Bottom row action buttons
    public static let save = ButtonId(x: 0, y: 0)
    public static let test = ButtonId(x: 1, y: 0)
    public static let cancel = ButtonId(x: 7, y: 0)
    
    /// Top row register selection
    public static let registerOsc = ButtonId(x: 0, y: 7)
    public static let registerMode = ButtonId(x: 1, y: 7)
    public static let registerColor = ButtonId(x: 2, y: 7)
    
    /// OSC pagination
    public static let oscPagePrev = ButtonId(x: 6, y: 7)
    public static let oscPageNext = ButtonId(x: 7, y: 7)
}

// MARK: - FSM Result Type

/// Result of an FSM transition
public struct FSMResult {
    public let state: ControllerState
    public let effects: [LaunchpadEffect]
    
    public init(state: ControllerState, effects: [LaunchpadEffect] = []) {
        self.state = state
        self.effects = effects
    }
}

// MARK: - Learn Mode Transitions

/// Enter learn mode - start waiting for pad selection
public func enterLearnMode(_ state: ControllerState) -> FSMResult {
    var newState = state
    newState.learnState = LearnState()
    newState.learnState.phase = .waitPad
    
    return FSMResult(
        state: newState,
        effects: [
            // Learn button blinks RED when recording
            .setLed(padId: LaunchpadButton.learn, color: LP.red, blink: true),
            .log(message: "Entered learn mode - press a pad to configure", level: .info)
        ]
    )
}

/// Exit learn mode - return to normal operation
public func exitLearnMode(_ state: ControllerState) -> FSMResult {
    var newState = state
    newState.learnState = LearnState()
    newState.learnState.phase = .idle
    
    return FSMResult(
        state: newState,
        effects: [
            // Learn button solid GREEN when idle (ready to learn)
            .setLed(padId: LaunchpadButton.learn, color: LP.greenDim, blink: false),
            .log(message: "Exited learn mode", level: .info)
        ]
    )
}

/// User selected a pad to configure - go directly to CONFIG with live capture
public func selectPadForConfig(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    var newState = state
    newState.learnState.phase = .config
    newState.learnState.selectedPad = padId
    newState.learnState.capturedOsc = []
    newState.learnState.activeRegister = .oscSelect
    
    return FSMResult(
        state: newState,
        effects: [.log(message: "Config mode for pad \(padId) - interact with Synesthesia", level: .info)]
    )
}

/// Capture an incoming OSC event during config phase (live capture)
public func captureOscEvent(_ state: ControllerState, event: OscEvent) -> FSMResult {
    guard state.learnState.phase == .config else {
        return FSMResult(state: state)
    }
    
    // Skip audio messages - never capture these
    if event.address.hasPrefix("/audio/") {
        return FSMResult(state: state)
    }
    
    // Skip non-controllable addresses
    guard event.toCommand().isControllable else {
        return FSMResult(state: state)
    }
    
    var newState = state
    
    // Check if already captured
    let existingIndex = newState.learnState.capturedOsc.firstIndex { $0.command.address == event.address }
    
    if existingIndex == nil {
        // New OSC - only enable if it's the first one (highest priority)
        // After sorting, check if this would become the first
        let isFirst = newState.learnState.capturedOsc.isEmpty
        
        let captured = CapturedOsc(
            command: event.toCommand(),
            priority: event.priority,
            isEnabled: isFirst  // Only first (highest priority) enabled by default
        )
        newState.learnState.capturedOsc.append(captured)
        
        // Sort by priority
        newState.learnState.capturedOsc.sort { $0.priority < $1.priority }
        
        // After sorting, ensure only the first one is enabled
        // (in case a higher priority one arrived later)
        if let firstIndex = newState.learnState.capturedOsc.indices.first {
            for i in newState.learnState.capturedOsc.indices {
                newState.learnState.capturedOsc[i].isEnabled = (i == firstIndex)
            }
        }
        
        // Auto-suggest mode from highest priority enabled
        if let primary = newState.learnState.primaryCommand, newState.learnState.selectedMode == nil {
            newState.learnState.selectedMode = categorizeOsc(primary.address).mode
        }
        
        return FSMResult(
            state: newState,
            effects: [.log(message: "Captured: \(event.address)", level: .info)]
        )
    }
    
    return FSMResult(state: state)
}

/// Toggle enable/disable for a captured OSC
public func toggleOscEnabled(_ state: ControllerState, index: Int) -> FSMResult {
    guard state.learnState.phase == .config,
          index >= 0 && index < state.learnState.capturedOsc.count else {
        return FSMResult(state: state)
    }
    
    var newState = state
    newState.learnState.capturedOsc[index].isEnabled.toggle()
    
    // Update suggested mode based on new primary
    if let primary = newState.learnState.primaryCommand {
        newState.learnState.selectedMode = categorizeOsc(primary.address).mode
    }
    
    let osc = newState.learnState.capturedOsc[index]
    let status = osc.isEnabled ? "enabled" : "disabled"
    return FSMResult(
        state: newState,
        effects: [.log(message: "\(osc.command.address) \(status)", level: .info)]
    )
}

// MARK: - Main Pad Press Handler

/// Main pad press handler - routes based on current phase
public func handlePadPress(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    let phase = state.learnState.phase
    
    // Learn button behavior depends on phase
    if padId == LaunchpadButton.learn {
        switch phase {
        case .idle:
            return enterLearnMode(state)
        case .waitPad:
            // Cancel - exit learn mode
            return exitLearnMode(state)
        case .config:
            // Exit config (cancel)
            return exitLearnMode(state)
        }
    }
    
    switch phase {
    case .idle:
        return handleNormalPress(state, padId: padId)
    case .waitPad:
        return padId.isGrid ? selectPadForConfig(state, padId: padId) : FSMResult(state: state)
    case .config:
        return handleConfigPadPress(state, padId: padId)
    }
}

/// Handle pad press during normal operation
public func handleNormalPress(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    guard let behavior = state.pads[padId] else {
        return FSMResult(state: state)
    }
    
    switch behavior.mode {
    case .selector:
        return handleSelectorPress(state, padId: padId, behavior: behavior)
    case .toggle:
        return handleTogglePress(state, padId: padId, behavior: behavior)
    case .oneShot:
        return handleOneShotPress(state, padId: padId, behavior: behavior)
    case .push:
        return handlePushPress(state, padId: padId, behavior: behavior)
    }
}

/// Handle pad release (for PUSH mode)
public func handlePadRelease(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    guard state.learnState.phase == .idle,
          let behavior = state.pads[padId],
          behavior.mode == .push else {
        return FSMResult(state: state)
    }
    
    var newState = state
    newState.padRuntime[padId] = PadRuntimeState(
        isActive: false,
        isOn: false,
        currentColor: behavior.idleColor
    )
    
    var effects: [LaunchpadEffect] = [
        .setLed(padId: padId, color: behavior.idleColor, blink: false)
    ]
    
    if let oscAction = behavior.oscAction {
        effects.append(.sendOsc(OscCommand(address: oscAction.address, args: [.float(0.0)])))
    }
    
    return FSMResult(state: newState, effects: effects)
}

// MARK: - Mode-Specific Handlers

private func handleSelectorPress(_ state: ControllerState, padId: ButtonId, behavior: PadBehavior) -> FSMResult {
    var effects: [LaunchpadEffect] = []
    var newState = state
    
    guard let group = behavior.group else {
        return FSMResult(state: state)
    }
    
    // Deactivate previous
    if let previousActive = state.activeSelectorByGroup[group],
       let prevPadId = previousActive,
       let prevBehavior = state.pads[prevPadId] {
        newState.padRuntime[prevPadId] = PadRuntimeState(
            isActive: false,
            currentColor: prevBehavior.idleColor
        )
        effects.append(.setLed(padId: prevPadId, color: prevBehavior.idleColor, blink: false))
    }
    
    // Activate new
    newState.padRuntime[padId] = PadRuntimeState(
        isActive: true,
        currentColor: behavior.activeColor
    )
    effects.append(.setLed(padId: padId, color: behavior.activeColor, blink: true))
    newState.activeSelectorByGroup[group] = padId
    
    if let oscAction = behavior.oscAction {
        effects.append(.sendOsc(oscAction))
    }
    
    return FSMResult(state: newState, effects: effects)
}

private func handleTogglePress(_ state: ControllerState, padId: ButtonId, behavior: PadBehavior) -> FSMResult {
    var effects: [LaunchpadEffect] = []
    var newState = state
    
    let currentRuntime = state.padRuntime[padId] ?? PadRuntimeState()
    let newIsOn = !currentRuntime.isOn
    let oscCmd = newIsOn ? behavior.oscOn : behavior.oscOff
    let newColor = newIsOn ? behavior.activeColor : behavior.idleColor
    
    newState.padRuntime[padId] = PadRuntimeState(
        isActive: newIsOn,
        isOn: newIsOn,
        currentColor: newColor
    )
    effects.append(.setLed(padId: padId, color: newColor, blink: false))
    
    if let cmd = oscCmd {
        effects.append(.sendOsc(cmd))
    }
    
    return FSMResult(state: newState, effects: effects)
}

private func handleOneShotPress(_ state: ControllerState, padId: ButtonId, behavior: PadBehavior) -> FSMResult {
    var effects: [LaunchpadEffect] = []
    var newState = state
    
    newState.padRuntime[padId] = PadRuntimeState(
        isActive: false,
        currentColor: behavior.activeColor
    )
    effects.append(.setLed(padId: padId, color: behavior.activeColor, blink: false))
    
    if let oscAction = behavior.oscAction {
        effects.append(.sendOsc(oscAction))
    }
    
    return FSMResult(state: newState, effects: effects)
}

private func handlePushPress(_ state: ControllerState, padId: ButtonId, behavior: PadBehavior) -> FSMResult {
    var effects: [LaunchpadEffect] = []
    var newState = state
    
    newState.padRuntime[padId] = PadRuntimeState(
        isActive: true,
        isOn: true,
        currentColor: behavior.activeColor
    )
    effects.append(.setLed(padId: padId, color: behavior.activeColor, blink: false))
    
    if let oscAction = behavior.oscAction {
        effects.append(.sendOsc(OscCommand(address: oscAction.address, args: [.float(1.0)])))
    }
    
    return FSMResult(state: newState, effects: effects)
}

// MARK: - Config Phase Handlers

private func handleConfigPadPress(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    let learn = state.learnState
    
    // Action buttons
    if padId == LaunchpadButton.save {
        return saveConfig(state)
    } else if padId == LaunchpadButton.test {
        return testConfig(state)
    } else if padId == LaunchpadButton.cancel {
        return exitLearnMode(state)
    }
    
    // Register selection
    if padId == LaunchpadButton.registerOsc {
        var newState = state
        newState.learnState.activeRegister = .oscSelect
        return FSMResult(state: newState)
    } else if padId == LaunchpadButton.registerMode {
        var newState = state
        newState.learnState.activeRegister = .modeSelect
        return FSMResult(state: newState)
    } else if padId == LaunchpadButton.registerColor {
        var newState = state
        newState.learnState.activeRegister = .colorSelect
        return FSMResult(state: newState)
    }
    
    // Register-specific input
    switch learn.activeRegister {
    case .oscSelect:
        return handleOscSelectInput(state, padId: padId)
    case .modeSelect:
        return handleModeSelectInput(state, padId: padId)
    case .colorSelect:
        return handleColorSelectInput(state, padId: padId)
    }
}

private func handleOscSelectInput(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    var newState = state
    let learn = state.learnState
    let slotsPerPage = 32  // 4 rows × 8 columns
    
    // Pagination
    if padId == LaunchpadButton.oscPagePrev && learn.oscPage > 0 {
        newState.learnState.oscPage -= 1
        return FSMResult(state: newState)
    }
    
    let maxPages = (learn.capturedOsc.count - 1) / slotsPerPage
    if padId == LaunchpadButton.oscPageNext && learn.oscPage < maxPages {
        newState.learnState.oscPage += 1
        return FSMResult(state: newState)
    }
    
    // OSC toggle (rows 5,4,3,2 top to bottom, columns 0-7) - toggle enable/disable
    if padId.y >= 2 && padId.y <= 5 && padId.x >= 0 && padId.x <= 7 {
        let rowOffset = 5 - padId.y  // row 5 = offset 0, row 4 = offset 1, etc.
        let index = learn.oscPage * slotsPerPage + rowOffset * 8 + padId.x
        return toggleOscEnabled(state, index: index)
    }
    
    return FSMResult(state: state)
}

private func handleModeSelectInput(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    // Mode buttons (row 3, cols 0-3)
    if padId.y == 3 && padId.x >= 0 && padId.x <= 3 {
        let modes: [PadMode] = [.toggle, .push, .oneShot, .selector]
        var newState = state
        newState.learnState.selectedMode = modes[padId.x]
        return FSMResult(state: newState)
    }
    return FSMResult(state: state)
}

private func handleColorSelectInput(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    var newState = state
    let colors = LaunchpadColor.allCases
    
    // Color grid: rows 0-3, cols 0-7 (32 colors)
    if padId.y >= 0 && padId.y <= 3 && padId.x >= 0 && padId.x <= 7 {
        let idx = padId.y * 8 + padId.x
        if idx < colors.count {
            newState.learnState.selectedColor = colors[idx].rawValue
            return FSMResult(state: newState)
        }
    }
    
    return FSMResult(state: state)
}

// MARK: - Save/Test Config

private func saveConfig(_ state: ControllerState) -> FSMResult {
    let learn = state.learnState
    guard let selectedPad = learn.selectedPad,
          let cmd = learn.primaryCommand else {
        return exitLearnMode(state)
    }
    
    let (_, _, group) = categorizeOsc(cmd.address)
    
    let behavior = createPadBehavior(
        padId: selectedPad,
        mode: learn.selectedMode ?? .toggle,
        oscCommand: cmd,
        idleColor: learn.selectedColor,
        activeColor: learn.selectedColor,  // Same color - active state shown via blinking
        label: cmd.address.components(separatedBy: "/").last ?? "",
        group: group
    )
    
    var newState = state
    newState.pads[selectedPad] = behavior
    newState.padRuntime[selectedPad] = PadRuntimeState(
        isActive: false,
        currentColor: learn.selectedColor
    )
    
    let result = exitLearnMode(newState)
    var effects = result.effects
    effects.append(.saveConfig)
    effects.append(.log(message: "Saved config for pad \(selectedPad)", level: .info))
    
    return FSMResult(state: result.state, effects: effects)
}

private func testConfig(_ state: ControllerState) -> FSMResult {
    let learn = state.learnState
    guard let cmd = learn.primaryCommand else {
        return FSMResult(state: state)
    }
    
    let testCmd: OscCommand
    
    if learn.selectedMode == .toggle || learn.selectedMode == .push {
        testCmd = OscCommand(address: cmd.address, args: [.float(1.0)])
    } else {
        testCmd = cmd
    }
    
    return FSMResult(
        state: state,
        effects: [
            .sendOsc(testCmd),
            .log(message: "Test: \(testCmd.address)", level: .info)
        ]
    )
}

private func createPadBehavior(
    padId: ButtonId,
    mode: PadMode,
    oscCommand: OscCommand,
    idleColor: Int,
    activeColor: Int,
    label: String,
    group: ButtonGroupType?
) -> PadBehavior {
    switch mode {
    case .toggle:
        return PadBehavior(
            padId: padId,
            mode: mode,
            idleColor: idleColor,
            activeColor: activeColor,
            label: label,
            oscOn: OscCommand(address: oscCommand.address, args: [.float(1.0)]),
            oscOff: OscCommand(address: oscCommand.address, args: [.float(0.0)])
        )
    case .selector:
        return PadBehavior(
            padId: padId,
            mode: mode,
            group: group ?? .custom,
            idleColor: idleColor,
            activeColor: activeColor,
            label: label,
            oscAction: oscCommand
        )
    default:
        return PadBehavior(
            padId: padId,
            mode: mode,
            idleColor: idleColor,
            activeColor: activeColor,
            label: label,
            oscAction: oscCommand
        )
    }
}

// MARK: - OSC Event Handling

/// Handle incoming OSC event (for sync with external changes)
public func handleOscEvent(_ state: ControllerState, event: OscEvent) -> FSMResult {
    var newState = state
    var effects: [LaunchpadEffect] = []
    
    // Handle beat events
    if event.address == "/audio/beat/onbeat" {
        if case .float(let val) = event.args.first {
            newState.beatPulse = val > 0.5
        }
    }
    
    // Handle scene/preset changes for selector sync
    if event.address.hasPrefix("/scenes/") {
        let sceneName = event.address.components(separatedBy: "/").last ?? ""
        newState.activeScene = sceneName
        let syncResult = activateMatchingSelector(newState, command: event.toCommand(), group: .scenes)
        newState = syncResult.state
        effects.append(contentsOf: syncResult.effects)
        
        // Reset subgroups
        let resetResult = resetSubgroup(newState, parentGroup: .scenes)
        newState = resetResult.state
        effects.append(contentsOf: resetResult.effects)
    }
    
    if event.address.hasPrefix("/presets/") {
        let presetName = event.address.components(separatedBy: "/").last ?? ""
        newState.activePreset = presetName
        let syncResult = activateMatchingSelector(newState, command: event.toCommand(), group: .presets)
        newState = syncResult.state
        effects.append(contentsOf: syncResult.effects)
    }
    
    return FSMResult(state: newState, effects: effects)
}

private func activateMatchingSelector(_ state: ControllerState, command: OscCommand, group: ButtonGroupType) -> FSMResult {
    var newState = state
    var effects: [LaunchpadEffect] = []
    
    // Find matching selector
    var matchingPad: ButtonId? = nil
    for (padId, behavior) in state.pads {
        if behavior.mode == .selector &&
           behavior.group == group &&
           behavior.oscAction?.address == command.address {
            matchingPad = padId
            break
        }
    }
    
    guard let matchingPad else {
        return FSMResult(state: state)
    }
    
    // Deactivate previous
    if let previousActive = state.activeSelectorByGroup[group],
       let prevPadId = previousActive,
       let prevBehavior = state.pads[prevPadId] {
        newState.padRuntime[prevPadId] = PadRuntimeState(
            isActive: false,
            currentColor: prevBehavior.idleColor
        )
        effects.append(.setLed(padId: prevPadId, color: prevBehavior.idleColor, blink: false))
    }
    
    // Activate matching
    if let behavior = state.pads[matchingPad] {
        newState.padRuntime[matchingPad] = PadRuntimeState(
            isActive: true,
            currentColor: behavior.activeColor
        )
        effects.append(.setLed(padId: matchingPad, color: behavior.activeColor, blink: true))
        newState.activeSelectorByGroup[group] = matchingPad
    }
    
    return FSMResult(state: newState, effects: effects)
}

private func resetSubgroup(_ state: ControllerState, parentGroup: ButtonGroupType) -> FSMResult {
    var newState = state
    var effects: [LaunchpadEffect] = []
    
    for groupType in ButtonGroupType.allCases {
        if groupType.parentGroup == parentGroup {
            if let previousActive = state.activeSelectorByGroup[groupType],
               let prevPadId = previousActive,
               let prevBehavior = state.pads[prevPadId] {
                newState.padRuntime[prevPadId] = PadRuntimeState(
                    isActive: false,
                    currentColor: prevBehavior.idleColor
                )
                effects.append(.setLed(padId: prevPadId, color: prevBehavior.idleColor, blink: false))
            }
            newState.activeSelectorByGroup[groupType] = nil
        }
    }
    
    return FSMResult(state: newState, effects: effects)
}

// MARK: - Utility Functions

// Priority levels for OSC recording (lower = higher priority)
public let PRIORITY_SCENE = 1       // Scenes - highest priority, stops recording immediately
public let PRIORITY_PRESET = 2      // Presets - high priority
public let PRIORITY_CONTROL = 3     // Toggle/Push controls
public let PRIORITY_NOISE = 99      // Ignore completely (audio levels, etc.)

/// Categorize an OSC address to determine suggested mode, group, and priority
/// Matches Python synesthesia_config.py categorize_osc()
public func categorizeOsc(_ address: String) -> (priority: Int, mode: PadMode, group: ButtonGroupType?) {
    // Scenes - highest priority, selector mode
    if address.hasPrefix("/scenes/") {
        return (PRIORITY_SCENE, .selector, .scenes)
    }
    
    // Presets - high priority, selector mode
    if address.hasPrefix("/presets/") {
        return (PRIORITY_PRESET, .selector, .presets)
    }
    
    // Favorite slots - similar to presets
    if address.hasPrefix("/favslots/") {
        return (PRIORITY_PRESET, .selector, .presets)
    }
    
    // Media selection - high priority selector (like scenes)
    if address.hasPrefix("/media/") {
        return (PRIORITY_SCENE, .selector, nil)
    }
    
    // Playlist controls - high priority one-shot
    if address.hasPrefix("/playlist/") {
        return (PRIORITY_PRESET, .oneShot, nil)
    }
    
    // Render settings - toggle
    if address.hasPrefix("/render/") {
        return (PRIORITY_CONTROL, .toggle, nil)
    }
    
    // Global controls - toggle
    if address.hasPrefix("/controls/global/") {
        return (PRIORITY_CONTROL, .toggle, nil)
    }
    
    // Meta controls - toggle (or selector for hue)
    if address.hasPrefix("/controls/meta/") {
        if address.contains("hue") {
            return (PRIORITY_CONTROL, .selector, .colors)
        }
        return (PRIORITY_CONTROL, .toggle, nil)
    }
    
    // General controls - toggle
    if address.hasPrefix("/controls/") {
        return (PRIORITY_CONTROL, .toggle, nil)
    }
    
    // Audio/beat messages - noise, ignore
    if address.hasPrefix("/audio/") {
        return (PRIORITY_NOISE, .oneShot, nil)
    }
    
    // Unknown - default to toggle
    return (50, .toggle, nil)
}

/// Check if receiving this address should stop OSC recording
public func shouldStopRecording(_ address: String) -> Bool {
    let (priority, _, _) = categorizeOsc(address)
    return priority <= PRIORITY_CONTROL
}

/// Check if an OSC address is noisy (high-frequency, should be filtered from UI)
public func isNoisyAudio(_ address: String) -> Bool {
    let noisyPrefixes = [
        "/audio/level",      // Audio levels (sent every frame)
        "/audio/fft/",       // FFT data (sent every frame)
        "/audio/timecode",   // Timecode (sent continuously)
    ]
    return noisyPrefixes.contains { address.hasPrefix($0) }
}

/// Get suggested LED colors for an OSC address category
public func suggestedColors(for address: String) -> (idle: Int, active: Int) {
    if address.hasPrefix("/scenes/") {
        return (LP.greenDim, LP.red)        // Green dim -> Red
    }
    if address.hasPrefix("/presets/") {
        return (LP.blue, LP.green)          // Blue -> Green
    }
    if address.hasPrefix("/favslots/") {
        return (LP.cyan, LP.green)          // Cyan -> Green
    }
    if address.hasPrefix("/playlist/") {
        return (LP.orange, LP.yellow)       // Orange -> Yellow
    }
    if address.hasPrefix("/controls/meta/") {
        return (LP.purple, LP.pink)         // Purple -> Pink
    }
    if address.hasPrefix("/controls/global/") {
        return (LP.yellow, LP.red)          // Yellow -> Red
    }
    return (LP.off, LP.red)                 // Default: off -> red
}

/// Toggle blink state for animations
public func toggleBlink(_ state: ControllerState) -> ControllerState {
    var newState = state
    newState.blinkOn = !state.blinkOn
    return newState
}

/// Generate effects to refresh all LEDs
public func refreshAllLeds(_ state: ControllerState) -> [LaunchpadEffect] {
    var effects: [LaunchpadEffect] = []
    
    // Configured pads
    for (padId, behavior) in state.pads {
        let runtime = state.padRuntime[padId] ?? PadRuntimeState()
        let blink = runtime.isActive && behavior.mode == .selector
        effects.append(.setLed(padId: padId, color: runtime.currentColor, blink: blink))
    }
    
    // Learn button (Scene 0) - RED when idle, blinking RED when in learn mode
    let isInLearnMode = state.learnState.phase != .idle
    effects.append(.setLed(
        padId: LaunchpadButton.learn,
        color: LP.red,
        blink: isInLearnMode
    ))
    
    return effects
}

/// Add a pad behavior
public func addPadBehavior(_ state: ControllerState, behavior: PadBehavior) -> FSMResult {
    var newState = state
    newState.pads[behavior.padId] = behavior
    newState.padRuntime[behavior.padId] = PadRuntimeState(
        isActive: false,
        currentColor: behavior.idleColor
    )
    
    return FSMResult(
        state: newState,
        effects: [
            .setLed(padId: behavior.padId, color: behavior.idleColor, blink: false),
            .log(message: "Added pad \(behavior.padId): \(behavior.mode)", level: .info)
        ]
    )
}

/// Remove a pad configuration
public func removePad(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    guard state.pads[padId] != nil else {
        return FSMResult(state: state)
    }
    
    var newState = state
    newState.pads.removeValue(forKey: padId)
    newState.padRuntime.removeValue(forKey: padId)
    
    // Remove from active selectors
    for (group, activePad) in state.activeSelectorByGroup {
        if activePad == padId {
            newState.activeSelectorByGroup[group] = nil
        }
    }
    
    return FSMResult(
        state: newState,
        effects: [
            .setLed(padId: padId, color: LP.off, blink: false),
            .log(message: "Removed pad \(padId)", level: .info)
        ]
    )
}

/// Clear all pad configurations
public func clearAllPads(_ state: ControllerState) -> FSMResult {
    var effects: [LaunchpadEffect] = state.pads.keys.map { padId in
        .setLed(padId: padId, color: LP.off, blink: false)
    }
    effects.append(.log(message: "Cleared all pads", level: .info))
    
    var newState = state
    newState.pads = [:]
    newState.padRuntime = [:]
    newState.activeSelectorByGroup = [:]
    
    return FSMResult(state: newState, effects: effects)
}

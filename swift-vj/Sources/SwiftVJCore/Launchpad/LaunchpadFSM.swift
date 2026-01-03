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
        effects: [.log(message: "Entered learn mode - press a pad to configure", level: .info)]
    )
}

/// Exit learn mode - return to normal operation
public func exitLearnMode(_ state: ControllerState) -> FSMResult {
    var newState = state
    newState.learnState = LearnState()
    newState.learnState.phase = .idle
    
    return FSMResult(
        state: newState,
        effects: [.log(message: "Exited learn mode", level: .info)]
    )
}

/// User selected a pad to configure - start recording OSC
public func selectPadForConfig(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    var newState = state
    newState.learnState.phase = .recordOsc
    newState.learnState.selectedPad = padId
    newState.learnState.recordedEvents = []
    
    return FSMResult(
        state: newState,
        effects: [.log(message: "Recording OSC for pad \(padId)", level: .info)]
    )
}

/// Record an incoming OSC event during recording phase
public func recordOscEvent(_ state: ControllerState, event: OscEvent) -> FSMResult {
    guard state.learnState.phase == .recordOsc else {
        return FSMResult(state: state)
    }
    
    // Skip non-controllable addresses
    guard event.toCommand().isControllable else {
        return FSMResult(state: state)
    }
    
    var newState = state
    newState.learnState.recordedEvents.append(event)
    
    let uniqueCount = Set(newState.learnState.recordedEvents.map { $0.address }).count
    return FSMResult(
        state: newState,
        effects: [.log(message: "Recorded (\(uniqueCount)): \(event.address)", level: .info)]
    )
}

/// Finish OSC recording and move to config phase
public func finishRecording(_ state: ControllerState) -> FSMResult {
    let events = state.learnState.recordedEvents
    
    if events.isEmpty {
        return exitLearnMode(state)
    }
    
    // Sort by priority and dedupe
    let sortedEvents = events.sorted { ($0.priority, $0.timestamp) < ($1.priority, $1.timestamp) }
    var seenAddresses = Set<String>()
    var uniqueCommands: [OscCommand] = []
    
    for event in sortedEvents {
        if !seenAddresses.contains(event.address) {
            seenAddresses.insert(event.address)
            uniqueCommands.append(event.toCommand())
        }
    }
    
    // Suggest mode based on first command
    let suggestedMode: PadMode = uniqueCommands.first.flatMap { categorizeOsc($0.address).mode } ?? .toggle
    
    var newState = state
    newState.learnState.phase = .config
    newState.learnState.candidateCommands = uniqueCommands
    newState.learnState.selectedOscIndex = 0
    newState.learnState.selectedMode = suggestedMode
    newState.learnState.activeRegister = .oscSelect
    
    return FSMResult(
        state: newState,
        effects: [.log(message: "Recorded \(uniqueCommands.count) unique commands", level: .info)]
    )
}

// MARK: - Main Pad Press Handler

/// Main pad press handler - routes based on current phase
public func handlePadPress(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    let phase = state.learnState.phase
    
    // Learn button toggles learn mode
    if padId == LaunchpadButton.learn {
        return phase == .idle ? enterLearnMode(state) : exitLearnMode(state)
    }
    
    switch phase {
    case .idle:
        return handleNormalPress(state, padId: padId)
    case .waitPad:
        return padId.isGrid ? selectPadForConfig(state, padId: padId) : FSMResult(state: state)
    case .recordOsc:
        if padId == LaunchpadButton.save {
            return saveFromRecording(state)
        } else if padId == LaunchpadButton.cancel {
            return exitLearnMode(state)
        }
        return FSMResult(state: state)
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
    
    // Pagination
    if padId == LaunchpadButton.oscPagePrev && learn.oscPage > 0 {
        newState.learnState.oscPage -= 1
        return FSMResult(state: newState)
    }
    
    let maxPages = (learn.candidateCommands.count - 1) / 8
    if padId == LaunchpadButton.oscPageNext && learn.oscPage < maxPages {
        newState.learnState.oscPage += 1
        return FSMResult(state: newState)
    }
    
    // OSC selection (row 3, columns 0-7)
    if padId.y == 3 && padId.x >= 0 && padId.x <= 7 {
        let index = learn.oscPage * 8 + padId.x
        if index < learn.candidateCommands.count {
            let cmd = learn.candidateCommands[index]
            let suggestedMode = categorizeOsc(cmd.address).mode
            newState.learnState.selectedOscIndex = index
            newState.learnState.selectedMode = suggestedMode
            return FSMResult(state: newState)
        }
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
    
    // Idle color grid (rows 2-3, cols 0-3)
    if padId.x >= 0 && padId.x <= 3 && padId.y >= 2 && padId.y <= 3 {
        let idx = (padId.y - 2) * 4 + padId.x
        if idx < colors.count {
            let brightness = state.learnState.idleBrightness
            newState.learnState.selectedIdleColor = colors[idx].velocity(at: brightness)
            return FSMResult(state: newState)
        }
    }
    
    // Active color grid (rows 2-3, cols 4-7)
    if padId.x >= 4 && padId.x <= 7 && padId.y >= 2 && padId.y <= 3 {
        let idx = (padId.y - 2) * 4 + (padId.x - 4)
        if idx < colors.count {
            let brightness = state.learnState.activeBrightness
            newState.learnState.selectedActiveColor = colors[idx].velocity(at: brightness)
            return FSMResult(state: newState)
        }
    }
    
    return FSMResult(state: state)
}

// MARK: - Save/Test Config

private func saveFromRecording(_ state: ControllerState) -> FSMResult {
    let learn = state.learnState
    guard let selectedPad = learn.selectedPad,
          let lastEvent = learn.recordedEvents.last else {
        return exitLearnMode(state)
    }
    
    let cmd = lastEvent.toCommand()
    let (_, suggestedMode, group) = categorizeOsc(cmd.address)
    
    let behavior = createPadBehavior(
        padId: selectedPad,
        mode: suggestedMode,
        oscCommand: cmd,
        idleColor: learn.selectedIdleColor,
        activeColor: learn.selectedActiveColor,
        label: cmd.address.components(separatedBy: "/").last ?? "",
        group: group
    )
    
    var newState = state
    newState.pads[selectedPad] = behavior
    newState.padRuntime[selectedPad] = PadRuntimeState(
        isActive: false,
        currentColor: learn.selectedIdleColor
    )
    
    let result = exitLearnMode(newState)
    var effects = result.effects
    effects.append(.saveConfig)
    effects.append(.log(message: "Saved: \(cmd.address) for pad \(selectedPad)", level: .info))
    
    return FSMResult(state: result.state, effects: effects)
}

private func saveConfig(_ state: ControllerState) -> FSMResult {
    let learn = state.learnState
    guard let selectedPad = learn.selectedPad,
          !learn.candidateCommands.isEmpty,
          learn.selectedOscIndex < learn.candidateCommands.count else {
        return exitLearnMode(state)
    }
    
    let cmd = learn.candidateCommands[learn.selectedOscIndex]
    let (_, _, group) = categorizeOsc(cmd.address)
    
    let behavior = createPadBehavior(
        padId: selectedPad,
        mode: learn.selectedMode ?? .toggle,
        oscCommand: cmd,
        idleColor: learn.selectedIdleColor,
        activeColor: learn.selectedActiveColor,
        label: cmd.address.components(separatedBy: "/").last ?? "",
        group: group
    )
    
    var newState = state
    newState.pads[selectedPad] = behavior
    newState.padRuntime[selectedPad] = PadRuntimeState(
        isActive: false,
        currentColor: learn.selectedIdleColor
    )
    
    let result = exitLearnMode(newState)
    var effects = result.effects
    effects.append(.saveConfig)
    effects.append(.log(message: "Saved config for pad \(selectedPad)", level: .info))
    
    return FSMResult(state: result.state, effects: effects)
}

private func testConfig(_ state: ControllerState) -> FSMResult {
    let learn = state.learnState
    guard !learn.candidateCommands.isEmpty,
          learn.selectedOscIndex < learn.candidateCommands.count else {
        return FSMResult(state: state)
    }
    
    let cmd = learn.candidateCommands[learn.selectedOscIndex]
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

/// Handle incoming OSC event
public func handleOscEvent(_ state: ControllerState, event: OscEvent) -> FSMResult {
    var newState = state
    var effects: [LaunchpadEffect] = []
    
    // Record during record phase
    if state.learnState.phase == .recordOsc {
        let result = recordOscEvent(state, event: event)
        newState = result.state
        effects.append(contentsOf: result.effects)
    }
    
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

/// Categorize an OSC address to determine suggested mode and group
public func categorizeOsc(_ address: String) -> (category: String, mode: PadMode, group: ButtonGroupType?) {
    if address.hasPrefix("/syn/scene/") || address.hasPrefix("/scenes/") {
        return ("scene", .selector, .scenes)
    }
    if address.hasPrefix("/syn/preset/") || address.hasPrefix("/presets/") {
        return ("preset", .selector, .presets)
    }
    if address.hasPrefix("/syn/control/") || address.hasPrefix("/controls/") {
        return ("control", .toggle, nil)
    }
    return ("other", .toggle, nil)
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
    
    for (padId, behavior) in state.pads {
        let runtime = state.padRuntime[padId] ?? PadRuntimeState()
        let blink = runtime.isActive && behavior.mode == .selector
        effects.append(.setLed(padId: padId, color: runtime.currentColor, blink: blink))
    }
    
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

// LaunchpadFSM.swift - Pure Finite State Machine for Launchpad
// Phase 5: MIDI Controller
//
// All functions are pure: same input = same output, no side effects.
// Returns new state and list of effects to be executed by imperative shell.

import Foundation

// MARK: - Button Constants

/// Special button identifiers for Learn mode and Banks
public enum LaunchpadButton {
    /// Bottom-right scene button triggers learn mode (ALWAYS, regardless of bank)
    public static let learn = ButtonId(x: 8, y: 0)
    
    /// Shift button - scene button y=5 (second from bottom)
    public static let shift = ButtonId(x: 8, y: 5)
    
    /// Page toggle button - scene button y=6 (third from bottom)
    public static let page = ButtonId(x: 8, y: 6)
    
    /// Record/Program button - scene button y=7 ("Stop/Solo/Mute" label)
    public static let record = ButtonId(x: 8, y: 7)
    
    /// Top row = Bank selection (cols 0-7, row -1)
    public static func bank(_ index: Int) -> ButtonId {
        ButtonId(x: index, y: -1)
    }
    
    /// Check if a button is a bank selector
    public static func isBankButton(_ id: ButtonId) -> Bool {
        id.y == -1 && id.x >= 0 && id.x < 8
    }
    
    /// Get bank index from button (nil if not a bank button)
    public static func bankIndex(from id: ButtonId) -> Int? {
        guard isBankButton(id) else { return nil }
        return id.x
    }
    
    /// Bottom row action buttons (during config)
    public static let save = ButtonId(x: 0, y: 0)
    public static let test = ButtonId(x: 1, y: 0)
    public static let cancel = ButtonId(x: 7, y: 0)
    
    /// Scene buttons (right column, except learn button)
    public static func isSceneButton(_ id: ButtonId) -> Bool {
        id.x == 8 && id.y > 0  // y=0 is learn button
    }
    
    /// Check if this is a special function scene button (shift, page, record)
    public static func isSpecialSceneButton(_ id: ButtonId) -> Bool {
        id == shift || id == page || id == record
    }
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
/// 
/// Strategy:
/// - `/scenes/*`: Keep the latest scene (replaces previous)
/// - `/controls/*`: Group by address, keep latest value per control
/// - All captured OSC enabled (they form complete state)
/// 
/// This way: scene + preset selection = scene + all final control values
public func captureOscEvent(_ state: ControllerState, event: OscEvent) -> FSMResult {
    guard state.learnState.phase == .config else {
        return FSMResult(state: state)
    }
    
    // Skip audio messages - never capture these
    if event.address.hasPrefix("/audio/") {
        return FSMResult(state: state)
    }
    
    // Only capture scenes and controls (what Synesthesia actually outputs)
    let isScene = event.address.hasPrefix("/scenes/")
    let isControl = event.address.hasPrefix("/controls/")
    
    guard isScene || isControl else {
        return FSMResult(state: state)
    }
    
    var newState = state
    
    if isScene {
        // Scene: remove any previous scene, keep only latest
        newState.learnState.capturedOsc.removeAll { $0.command.address.hasPrefix("/scenes/") }
        
        let captured = CapturedOsc(
            command: event.toCommand(),
            priority: PRIORITY_SCENE,
            isEnabled: true
        )
        newState.learnState.capturedOsc.append(captured)
        
        // Auto-suggest selector mode for scenes
        if newState.learnState.selectedMode == nil {
            newState.learnState.selectedMode = .selector
        }
        
        return FSMResult(
            state: newState,
            effects: [.log(message: "Scene: \(event.address)", level: .info)]
        )
    }
    
    if isControl {
        // Control: replace existing with same address (keep latest value)
        if let existingIndex = newState.learnState.capturedOsc.firstIndex(where: { $0.command.address == event.address }) {
            // Update existing control with new value
            newState.learnState.capturedOsc[existingIndex] = CapturedOsc(
                command: event.toCommand(),
                priority: PRIORITY_CONTROL,
                isEnabled: true
            )
        } else {
            // New control address
            let captured = CapturedOsc(
                command: event.toCommand(),
                priority: PRIORITY_CONTROL,
                isEnabled: true
            )
            newState.learnState.capturedOsc.append(captured)
        }
        
        return FSMResult(
            state: newState,
            effects: [.log(message: "Control: \(event.address)", level: .debug)]
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

// MARK: - Bank Switching

/// Switch to a different bank
public func switchBank(_ state: ControllerState, bankIndex: Int) -> FSMResult {
    guard bankIndex >= 0 && bankIndex < BankConfig.count else {
        return FSMResult(state: state)
    }
    
    guard bankIndex != state.activeBank else {
        return FSMResult(state: state)  // Already on this bank
    }
    
    var newState = state
    newState.activeBank = bankIndex
    
    var effects: [LaunchpadEffect] = [
        .log(message: "Switched to bank \(bankIndex)", level: .info)
    ]
    effects.append(contentsOf: renderState(newState))
    return FSMResult(state: newState, effects: effects)
}

// MARK: - Main Pad Press Handler

/// Main pad press handler - routes based on current phase
public func handlePadPress(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    let phase = state.learnState.phase
    
    // Learn button ALWAYS triggers learn mode (regardless of bank or phase)
    if padId == LaunchpadButton.learn {
        switch phase {
        case .idle:
            return enterLearnMode(state)
        case .waitPad:
            return exitLearnMode(state)
        case .config:
            return exitLearnMode(state)
        }
    }

    // Record button toggles learn mode for banks >=4
    if padId == LaunchpadButton.record, state.activeBank >= 4 {
        switch phase {
        case .idle:
            return enterLearnMode(state)
        case .waitPad, .config:
            return exitLearnMode(state)
        }
    }
    
    // Shift button - set shift held (momentary)
    if padId == LaunchpadButton.shift {
        var newState = state
        newState.isShiftHeld = true
        return FSMResult(
            state: newState,
            effects: [.setLed(padId: padId, color: LP.white, blink: false)]
        )
    }
    
    // Page button - advance page within bank pageCount
    if let pagingResult = handlePagingPress(state, padId: padId) {
        return pagingResult
    }
    
    // Bank buttons work in idle and config modes (for switching while configuring)
    if let bankIndex = LaunchpadButton.bankIndex(from: padId) {
        // In config mode, just switch bank (keep configuring)
        // In idle mode, switch bank
        return switchBank(state, bankIndex: bankIndex)
    }
    
    switch phase {
    case .idle:
        return handleNormalPress(state, padId: padId)
    case .waitPad:
        // Allow grid pads and scene buttons (except learn) for selection
        let layout = state.currentLayout
        let canSelect = padId.isGrid && layout.isRecordable(padId: padId)
        return canSelect ? selectPadForConfig(state, padId: padId) : FSMResult(state: state)
    case .config:
        return handleConfigPadPress(state, padId: padId)
    }
}

// MARK: - Paging

private func handlePagingPress(_ state: ControllerState, padId: ButtonId) -> FSMResult? {
    guard padId.isSceneButton else { return nil }
    let layout = state.currentLayout

    switch layout.paging {
    case .none:
        return nil
    case .nextButton(let row):
        guard padId.y == row else { return nil }
        var newState = state
        let pageCount = max(1, newState.currentPageCount)
        newState.currentPage = (state.currentPage + 1) % pageCount
        let effects = pagingIndicatorEffects(state: newState)
        return FSMResult(
            state: newState,
            effects: effects + [
                .log(message: "Page \(newState.currentPage + 1)/\(pageCount)", level: .info)
            ]
        )
    case .rowButtons(let rows):
        guard let pageIndex = rows.firstIndex(of: padId.y) else { return nil }
        var newState = state
        let pageCount = max(1, newState.currentPageCount)
        newState.currentPage = min(pageIndex, pageCount - 1)
        let effects = pagingIndicatorEffects(state: newState)
        return FSMResult(
            state: newState,
            effects: effects + [
                .log(message: "Page \(newState.currentPage + 1)/\(pageCount)", level: .info)
            ]
        )
    }
}

private func pagingIndicatorEffects(state: ControllerState) -> [LaunchpadEffect] {
    let layout = state.currentLayout
    let pageCount = max(1, state.currentPageCount)
    let activePage = min(state.currentPage, pageCount - 1)

    switch layout.paging {
    case .none:
        return []
    case .nextButton(let row):
        let color = activePage == 0 ? LP.purpleDim : LP.purple
        return [.setLed(padId: ButtonId(x: 8, y: row), color: color, blink: false)]
    case .rowButtons(let rows):
        var effects: [LaunchpadEffect] = []
        for (index, row) in rows.enumerated() {
            let color = index == activePage ? LP.purple : LP.purpleDim
            effects.append(.setLed(padId: ButtonId(x: 8, y: row), color: color, blink: false))
        }
        return effects
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
    case .increment:
        return handleIncrementPress(state, padId: padId, behavior: behavior, isIncrement: true)
    case .decrement:
        return handleIncrementPress(state, padId: padId, behavior: behavior, isIncrement: false)
    }
}

/// Handle pad release (for PUSH mode and shift)
public func handlePadRelease(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    // Shift release
    if padId == LaunchpadButton.shift {
        var newState = state
        newState.isShiftHeld = false
        return FSMResult(
            state: newState,
            effects: [.setLed(padId: padId, color: LP.purpleDim, blink: false)]
        )
    }
    
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
    
    // Send primary OSC action
    if let oscAction = behavior.oscAction {
        effects.append(.sendOsc(oscAction))
    }
    
    // Send additional OSC commands (e.g., control values after scene)
    for additionalCmd in behavior.additionalOsc {
        effects.append(.sendOsc(additionalCmd))
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
    
    // Send primary OSC command
    if let cmd = oscCmd {
        effects.append(.sendOsc(cmd))
    }
    
    // Send additional OSC commands only when turning ON
    if newIsOn {
        for additionalCmd in behavior.additionalOsc {
            effects.append(.sendOsc(additionalCmd))
        }
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
    
    // Send primary OSC action
    if let oscAction = behavior.oscAction {
        effects.append(.sendOsc(oscAction))
    }
    
    // Send additional OSC commands
    for additionalCmd in behavior.additionalOsc {
        effects.append(.sendOsc(additionalCmd))
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

/// Handle increment/decrement pad press
/// - Normal press: adjust by step (±0.1)
/// - Shift held: jump to min (decrement) or max (increment)
private func handleIncrementPress(_ state: ControllerState, padId: ButtonId, behavior: PadBehavior, isIncrement: Bool) -> FSMResult {
    var effects: [LaunchpadEffect] = []
    var newState = state
    
    guard let oscAction = behavior.oscAction else {
        return FSMResult(state: state)
    }
    
    // Get current value from runtime state, or start at middle
    let currentRuntime = state.padRuntime[padId] ?? PadRuntimeState(currentValue: 0.5)
    let currentValue = currentRuntime.currentValue
    
    // Calculate new value
    let newValue: Float
    if state.isShiftHeld {
        // Shift: jump to extreme
        newValue = isIncrement ? behavior.maxValue : behavior.minValue
    } else {
        // Normal: increment/decrement by step
        let delta = isIncrement ? behavior.step : -behavior.step
        newValue = max(behavior.minValue, min(behavior.maxValue, currentValue + delta))
    }
    
    // Update runtime state
    newState.padRuntime[padId] = PadRuntimeState(
        isActive: true,
        isOn: false,
        currentColor: behavior.activeColor,
        currentValue: newValue
    )
    
    // Flash the pad briefly
    effects.append(.setLed(padId: padId, color: behavior.activeColor, blink: false))
    
    // Send OSC with new value
    effects.append(.sendOsc(OscCommand(address: oscAction.address, args: [.float(newValue)])))
    effects.append(.log(message: "\(behavior.label): \(String(format: "%.2f", newValue))", level: .debug))
    
    return FSMResult(state: newState, effects: effects)
}

// MARK: - Config Phase Handlers

/// Scene button positions for register selection during config
private let registerOscButton = ButtonId(x: 8, y: 6)
private let registerModeButton = ButtonId(x: 8, y: 5)
private let registerColorButton = ButtonId(x: 8, y: 4)

private func handleConfigPadPress(_ state: ControllerState, padId: ButtonId) -> FSMResult {
    let learn = state.learnState
    
    // Action buttons (bottom row)
    if padId == LaunchpadButton.save {
        return saveConfig(state)
    } else if padId == LaunchpadButton.test {
        return testConfig(state)
    } else if padId == LaunchpadButton.cancel {
        return exitLearnMode(state)
    }
    
    // Register selection via scene buttons
    if padId == registerOscButton {
        var newState = state
        newState.learnState.activeRegister = .oscSelect
        return FSMResult(state: newState)
    } else if padId == registerModeButton {
        var newState = state
        newState.learnState.activeRegister = .modeSelect
        return FSMResult(state: newState)
    } else if padId == registerColorButton {
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
    
    // Pagination via scene buttons y=2 (prev) and y=3 (next)
    let oscPagePrev = ButtonId(x: 8, y: 2)
    let oscPageNext = ButtonId(x: 8, y: 3)
    
    if padId == oscPagePrev && learn.oscPage > 0 {
        newState.learnState.oscPage -= 1
        return FSMResult(state: newState)
    }
    
    let maxPages = max(0, (learn.capturedOsc.count - 1) / slotsPerPage)
    if padId == oscPageNext && learn.oscPage < maxPages {
        newState.learnState.oscPage += 1
        return FSMResult(state: newState)
    }
    
    // OSC toggle (rows 2-5 for content, cols 0-7) - toggle enable/disable
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
    guard let selectedPad = learn.selectedPad else {
        return exitLearnMode(state)
    }
    
    // Get all enabled captured OSC, sorted: scenes first, then controls
    let allCaptured = learn.capturedOsc.filter { $0.isEnabled }
    
    // Find the primary command (scene if present, otherwise first control)
    let sceneCmd = allCaptured.first { $0.command.address.hasPrefix("/scenes/") }?.command
    let controlCmds = allCaptured.filter { $0.command.address.hasPrefix("/controls/") }.map { $0.command }
    
    // Primary command determines the pad behavior
    guard let primaryCmd = sceneCmd ?? controlCmds.first else {
        return exitLearnMode(state)
    }
    
    let (_, _, group) = categorizeOsc(primaryCmd.address)
    
    // Additional OSC = all controls (sent after primary)
    let additionalOsc = sceneCmd != nil ? controlCmds : Array(controlCmds.dropFirst())
    
    let behavior = createPadBehavior(
        padId: selectedPad,
        mode: learn.selectedMode ?? .selector,
        oscCommand: primaryCmd,
        idleColor: learn.selectedColor,
        activeColor: learn.selectedColor,
        label: primaryCmd.address.components(separatedBy: "/").last ?? "",
        group: group,
        additionalOsc: additionalOsc
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
    
    let summary = sceneCmd != nil 
        ? "1 scene + \(controlCmds.count) controls"
        : "\(controlCmds.count) controls"
    effects.append(.log(message: "Saved pad \(selectedPad): \(summary)", level: .info))
    
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
    group: ButtonGroupType?,
    additionalOsc: [OscCommand] = []
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
            oscOff: OscCommand(address: oscCommand.address, args: [.float(0.0)]),
            additionalOsc: additionalOsc
        )
    case .selector:
        return PadBehavior(
            padId: padId,
            mode: mode,
            group: group ?? .custom,
            idleColor: idleColor,
            activeColor: activeColor,
            label: label,
            oscAction: oscCommand,
            additionalOsc: additionalOsc
        )
    default:
        return PadBehavior(
            padId: padId,
            mode: mode,
            idleColor: idleColor,
            activeColor: activeColor,
            label: label,
            oscAction: oscCommand,
            additionalOsc: additionalOsc
        )
    }
}

// MARK: - OSC Event Handling

/// Handle incoming OSC event (for sync with external changes)
public func handleOscEvent(_ state: ControllerState, event: OscEvent) -> FSMResult {
    var newState = state
    var effects: [LaunchpadEffect] = []
    
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

/// Generate effects to refresh all LEDs
public func refreshAllLeds(_ state: ControllerState) -> [LaunchpadEffect] {
    renderState(state)
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

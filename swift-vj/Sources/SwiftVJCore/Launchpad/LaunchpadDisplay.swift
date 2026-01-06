// LaunchpadDisplay.swift - LED Display Renderer
//
// Pure functions that render application state to LED effects.
// No side effects - just converts state to a list of LedEffect.
// Matches Python display.py

import Foundation

// MARK: - Main Render Function

/// Main render dispatch - renders current state to LED effects
/// Pure function: state in, effects out
public func renderState(_ state: ControllerState) -> [LaunchpadEffect] {
    switch state.learnState.phase {
    case .idle:
        return renderIdle(state)
    case .waitPad:
        return renderWaitPad(state)
    case .config:
        return renderConfig(state)
    }
}

// MARK: - Idle Phase

/// Render normal operation state (show configured pad colors)
private func renderIdle(_ state: ControllerState) -> [LaunchpadEffect] {
    var effects: [LaunchpadEffect] = []
    
    // Top row (y=7) = Bank buttons
    for i in 0..<BankConfig.count {
        let isActive = (i == state.activeBank)
        let color = isActive ? BankConfig.color(for: i) : BankConfig.dimColor(for: i)
        effects.append(.setLed(padId: LaunchpadButton.bank(i), color: color, blink: false))
    }
    
    // Grid pads (rows 0-6) - clear then render configured
    for y in 0..<7 {  // Skip row 7 (bank buttons)
        for x in 0..<8 {
            effects.append(.setLed(padId: ButtonId(x: x, y: y), color: LP.off, blink: false))
        }
    }
    
    // Clear scene buttons (right column, except learn)
    for y in 1..<8 {
        effects.append(.setLed(padId: ButtonId(x: 8, y: y), color: LP.off, blink: false))
    }
    
    // Then render configured pads with their current color
    for (padId, behavior) in state.pads {
        // Skip bank row for pad rendering
        if padId.y == 7 && padId.x < 8 { continue }
        
        let runtime = state.padRuntime[padId] ?? PadRuntimeState()
        let color = runtime.isActive ? behavior.activeColor : behavior.idleColor
        let blink = runtime.isActive && behavior.mode == .selector
        effects.append(.setLed(padId: padId, color: color, blink: blink))
    }
    
    // Learn button GREEN (ready to enter learn mode)
    effects.append(.setLed(padId: LaunchpadButton.learn, color: LP.greenDim, blink: false))
    
    return effects
}

// MARK: - Wait Pad Phase

/// Render 'waiting for pad selection' phase
/// - Top row: Bank buttons (can switch banks while selecting)
/// - Unconfigured pads pulse red (available for recording)
/// - Configured pads show their idle color (already assigned)
/// - Scene buttons also selectable
private func renderWaitPad(_ state: ControllerState) -> [LaunchpadEffect] {
    var effects: [LaunchpadEffect] = []
    
    // Top row (y=7) = Bank buttons (still active during wait)
    for i in 0..<BankConfig.count {
        let isActive = (i == state.activeBank)
        let color = isActive ? BankConfig.color(for: i) : BankConfig.dimColor(for: i)
        effects.append(.setLed(padId: LaunchpadButton.bank(i), color: color, blink: false))
    }
    
    // Grid pads (rows 0-6)
    for y in 0..<7 {  // Skip row 7 (bank buttons)
        for x in 0..<8 {
            let padId = ButtonId(x: x, y: y)
            if let behavior = state.pads[padId] {
                // Already configured - show idle color
                effects.append(.setLed(padId: padId, color: behavior.idleColor, blink: false))
            } else {
                // Available for configuration - blink red
                effects.append(.setLed(padId: padId, color: LP.red, blink: true))
            }
        }
    }
    
    // Scene buttons (right column, except learn button at y=0)
    for y in 1..<8 {
        let padId = ButtonId(x: 8, y: y)
        if let behavior = state.pads[padId] {
            effects.append(.setLed(padId: padId, color: behavior.idleColor, blink: false))
        } else {
            effects.append(.setLed(padId: padId, color: LP.red, blink: true))
        }
    }
    
    // Learn button ORANGE (in learn mode, press to cancel)
    effects.append(.setLed(padId: LaunchpadButton.learn, color: LP.orange, blink: false))
    
    return effects
}

// MARK: - Config Phase

/// Render configuration phase with live OSC capture
/// Layout:
/// - Top row (y=7): Bank buttons (can switch during config)
/// - Scene buttons: OSC (y=6), Mode (y=5), Color (y=4) registers
/// - Rows 0-6: Content based on active register
/// - Row 0: Save (green), Test (blue), Cancel (red)
private func renderConfig(_ state: ControllerState) -> [LaunchpadEffect] {
    var effects: [LaunchpadEffect] = []
    let learn = state.learnState
    
    // Clear grid pads (rows 0-6)
    for y in 0..<7 {
        for x in 0..<8 {
            effects.append(.setLed(padId: ButtonId(x: x, y: y), color: LP.off, blink: false))
        }
    }
    
    // Top row (y=7) = Bank buttons (active during config too)
    for i in 0..<BankConfig.count {
        let isActive = (i == state.activeBank)
        let color = isActive ? BankConfig.color(for: i) : BankConfig.dimColor(for: i)
        effects.append(.setLed(padId: LaunchpadButton.bank(i), color: color, blink: false))
    }
    
    // Scene buttons = Register selection (right column)
    // y=6: OSC, y=5: Mode, y=4: Color
    let oscRegColor = learn.activeRegister == .oscSelect ? LP.orange : LP.yellow
    let modeRegColor = learn.activeRegister == .modeSelect ? LP.orange : LP.yellow
    let colorRegColor = learn.activeRegister == .colorSelect ? LP.orange : LP.yellow
    
    effects.append(.setLed(padId: ButtonId(x: 8, y: 6), color: oscRegColor, blink: false))
    effects.append(.setLed(padId: ButtonId(x: 8, y: 5), color: modeRegColor, blink: false))
    effects.append(.setLed(padId: ButtonId(x: 8, y: 4), color: colorRegColor, blink: false))
    
    // Clear other scene buttons
    for y in [1, 2, 3, 7] {
        effects.append(.setLed(padId: ButtonId(x: 8, y: y), color: LP.off, blink: false))
    }
    
    // Show selected pad blinking (if within grid, not top row)
    if let selectedPad = learn.selectedPad, selectedPad.y < 7 {
        effects.append(.setLed(padId: selectedPad, color: LP.orange, blink: true))
    }
    
    // ---- Content area based on register ----
    switch learn.activeRegister {
    case .oscSelect:
        effects.append(contentsOf: renderOscSelect(learn))
    case .modeSelect:
        effects.append(contentsOf: renderModeSelect(learn))
    case .colorSelect:
        effects.append(contentsOf: renderColorSelect(learn))
    }
    
    // ---- Bottom row: Action buttons ----
    // Save only enabled if we have at least one enabled OSC
    let canSave = learn.primaryCommand != nil
    effects.append(.setLed(padId: LaunchpadButton.save, color: canSave ? LP.green : LP.greenDim, blink: false))
    effects.append(.setLed(padId: LaunchpadButton.test, color: canSave ? LP.blue : LP.blueDim, blink: false))
    effects.append(.setLed(padId: LaunchpadButton.cancel, color: LP.red, blink: false))
    
    // Learn button RED dim (can exit)
    effects.append(.setLed(padId: LaunchpadButton.learn, color: LP.redDim, blink: false))
    
    return effects
}

// MARK: - Register Renderers

/// Render OSC command selection with enable/disable (rows 2-5 = 32 slots)
/// - Enabled: WHITE (will be bound)
/// - Disabled: DIM color (ignored)
/// - Primary (first enabled): blinking
private func renderOscSelect(_ learn: LearnState) -> [LaunchpadEffect] {
    var effects: [LaunchpadEffect] = []
    
    // Use 4 rows (rows 2-5) × 8 columns = 32 slots per page
    let slotsPerPage = 32
    let pageStart = learn.oscPage * slotsPerPage
    let captured = Array(learn.capturedOsc.dropFirst(pageStart).prefix(slotsPerPage))
    
    // Determine primary index (first enabled across all pages)
    let primaryIndex = learn.capturedOsc.firstIndex { $0.isEnabled }
    
    for (i, osc) in captured.enumerated() {
        let globalIndex = pageStart + i
        let isPrimary = globalIndex == primaryIndex
        
        // Grid position: rows 5,4,3,2 (top to bottom), col 0-7
        let col = i % 8
        let row = 5 - (i / 8)  // rows 5, 4, 3, 2 (first item at top)
        
        // Priority-based color when disabled
        let priorityColor: Int
        switch osc.priority {
        case 1: priorityColor = LP.greenDim    // Scene
        case 2: priorityColor = LP.cyanDim     // Preset  
        case 3: priorityColor = LP.blueDim     // Control
        default: priorityColor = LP.purpleDim  // Other
        }
        
        let color = osc.isEnabled ? LP.white : priorityColor
        effects.append(.setLed(padId: ButtonId(x: col, y: row), color: color, blink: isPrimary))
    }
    
    // Page indicators via scene buttons (y=2 prev, y=3 next)
    let oscPagePrev = ButtonId(x: 8, y: 2)
    let oscPageNext = ButtonId(x: 8, y: 3)
    
    if learn.oscPage > 0 {
        effects.append(.setLed(padId: oscPagePrev, color: LP.blue, blink: false))
    }
    if pageStart + slotsPerPage < learn.capturedOsc.count {
        effects.append(.setLed(padId: oscPageNext, color: LP.blue, blink: false))
    }
    
    // Show "waiting for OSC" indicator if no captures yet
    if learn.capturedOsc.isEmpty {
        // Pulse rows 2-5 (content area) dimly to indicate waiting
        for row in 2...5 {
            for col in 0..<8 {
                effects.append(.setLed(padId: ButtonId(x: col, y: row), color: LP.yellowDim, blink: true))
            }
        }
    }
    
    return effects
}

/// Render mode selection (row 3, cols 0-3)
private func renderModeSelect(_ learn: LearnState) -> [LaunchpadEffect] {
    var effects: [LaunchpadEffect] = []
    
    // Time-based pulse patterns for mode preview
    // selector: always on
    // toggle: 2s on, 2s dim (4s cycle)
    // oneShot: 1s on, 4s dim (5s cycle)
    // push: like toggle (2s/2s)
    let now = Date().timeIntervalSinceReferenceDate
    
    let modes: [(PadMode, Int, Int, Int)] = [
        // (mode, x position, bright color, dim color)
        (.toggle, 0, LP.purple, LP.purpleDim),
        (.push, 1, LP.cyan, LP.cyanDim),
        (.oneShot, 2, LP.orange, LP.orangeDim),
        (.selector, 3, LP.green, LP.greenDim),
    ]
    
    for (mode, x, brightColor, dimColor) in modes {
        let isSelected = learn.selectedMode == mode
        
        // If selected, always white
        if isSelected {
            effects.append(.setLed(padId: ButtonId(x: x, y: 3), color: LP.white, blink: false))
            continue
        }
        
        // Time-based pulse pattern to preview the mode behavior
        let color: Int
        switch mode {
        case .selector:
            // Always on (steady)
            color = brightColor
        case .toggle, .push:
            // 2s on, 2s dim (4s cycle)
            let phase = now.truncatingRemainder(dividingBy: 4.0)
            color = phase < 2.0 ? brightColor : dimColor
        case .oneShot:
            // 1s on, 4s dim (5s cycle)
            let phase = now.truncatingRemainder(dividingBy: 5.0)
            color = phase < 1.0 ? brightColor : dimColor
        }
        
        effects.append(.setLed(padId: ButtonId(x: x, y: 3), color: color, blink: false))
    }
    
    return effects
}

/// Render color selection - 32 colors in 4 rows x 8 columns (rows 0-3)
/// Simple single color selection - selected shown with white, others show their color
private func renderColorSelect(_ learn: LearnState) -> [LaunchpadEffect] {
    var effects: [LaunchpadEffect] = []
    let colors = LaunchpadColor.allCases
    
    // 32 colors in 4 rows (rows 0-3) x 8 columns
    for (i, color) in colors.prefix(32).enumerated() {
        let x = i % 8
        let y = i / 8  // rows 0, 1, 2, 3
        let colorVel = color.rawValue
        let isSelected = colorVel == learn.selectedColor
        effects.append(.setLed(padId: ButtonId(x: x, y: y), color: isSelected ? LP.white : colorVel, blink: false))
    }
    
    return effects
}

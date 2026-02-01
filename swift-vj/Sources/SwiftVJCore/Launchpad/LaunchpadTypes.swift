// LaunchpadTypes.swift - Core types for Launchpad MIDI controller
// Phase 5: MIDI Controller (Launchpad Mini MK3)
//
// Immutable data structures following Grokking Simplicity

import Foundation

// MARK: - Button Identification

/// Type-safe button identifier using (x, y) coordinates
/// Coordinate System:
/// - Main 8x8 grid: x=0-7, y=0-7
/// - Top row buttons: x=0-7, y=-1 (Up, Down, Left, Right, Session, Drums, Keys, User)
/// - Right column buttons (scene launch): x=8, y=0-7
public struct ButtonId: Hashable, Codable, Sendable {
    public let x: Int
    public let y: Int
    
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
    
    /// Create from MIDI note number (Launchpad Mini MK3 Programmer mode)
    /// Notes 11-88: note = (row+1)*10 + (col+1)
    public init?(midiNote: Int) {
        let col = (midiNote % 10) - 1
        let row = (midiNote / 10) - 1
        guard col >= 0, col <= 8, row >= 0, row <= 7 else { return nil }
        self.x = col
        self.y = row
    }
    
    /// Convert to MIDI note for Programmer mode
    public var midiNote: Int {
        (y + 1) * 10 + (x + 1)
    }
    
    /// Check if this is a main grid pad (8x8)
    public var isGrid: Bool {
        x >= 0 && x <= 7 && y >= 0 && y <= 7
    }
    
    /// Check if this is a top row button
    public var isTopRow: Bool {
        x >= 0 && x <= 7 && y == -1
    }
    
    /// Check if this is a right column button (scene buttons)
    public var isSceneButton: Bool {
        x == 8 && y >= 0 && y <= 7
    }
}

extension ButtonId: CustomStringConvertible {
    public var description: String {
        if isTopRow {
            return "Top\(x)"
        } else if isSceneButton {
            return "Scene\(y)"
        } else {
            return "(\(x),\(y))"
        }
    }
}

// MARK: - LED Colors

/// Base colors with 3 brightness levels: [DIM, NORMAL, BRIGHT]
/// Extended color palette for Launchpad Mini Mk3
/// 32 colors arranged in 4 rows x 8 columns
public enum LaunchpadColor: Int, CaseIterable, Sendable {
    // Row 1: Warm colors
    case red = 5
    case redBright = 6
    case orange = 9
    case orangeBright = 10
    case amber = 96
    case yellow = 13
    case yellowBright = 14
    case lime = 17
    
    // Row 2: Cool greens
    case green = 21
    case greenBright = 22
    case mint = 29
    case teal = 33
    case cyan = 37
    case cyanBright = 38
    case sky = 40
    case azure = 44
    
    // Row 3: Blues and purples
    case blue = 45
    case blueBright = 46
    case indigo = 50
    case purple = 53
    case purpleBright = 54
    case violet = 48
    case magenta = 57
    case pink = 58
    
    // Row 4: Special colors
    case hotPink = 56
    case coral = 4
    case peach = 8
    case gold = 12
    case spring = 16
    case aqua = 36
    case lavender = 52
    case white = 3
}

/// LED display mode
public enum LedMode: Sendable {
    case `static`
    case pulse
    case flash
}

// Common color shortcuts
public enum LP {
    public static let off = 0
    public static let red = 5
    public static let redDim = 1
    public static let orange = 9
    public static let orangeDim = 10
    public static let yellow = 13
    public static let yellowDim = 14
    public static let green = 21
    public static let greenDim = 19
    public static let cyan = 37
    public static let cyanDim = 35
    public static let blue = 45
    public static let blueDim = 41
    public static let purple = 53
    public static let purpleDim = 51
    public static let pink = 57
    public static let pinkDim = 55
    public static let white = 3
    public static let whiteDim = 2
}

// MARK: - Pad Mode

/// Pad interaction mode
public enum PadMode: String, Codable, CaseIterable, Sendable {
    /// Radio button behavior within a group (only one active at a time)
    case selector
    /// On/Off toggle - alternates between osc_on and osc_off commands
    case toggle
    /// Single action on press only - sends osc_action once
    case oneShot
    /// Momentary - sends 1.0 on press, 0.0 on release (like sustain pedal)
    case push
    /// Increment value by step (normal: +step, shift: set to max)
    case increment
    /// Decrement value by step (normal: -step, shift: set to min)
    case decrement
}

// MARK: - Button Group

/// Predefined button group types for radio-button behavior
public enum ButtonGroupType: String, Codable, CaseIterable, Sendable {
    case scenes
    case presets   // Subgroup: resets when SCENES changes
    case colors
    case custom
    
    /// Get parent group if this is a subgroup
    public var parentGroup: ButtonGroupType? {
        switch self {
        case .presets: return .scenes
        default: return nil
        }
    }
    
    /// Whether this group resets when parent group changes
    public var resetsOnParentChange: Bool {
        parentGroup != nil
    }
}

// MARK: - Bank Roles

/// High-level bank roles for auto-layout
public enum BankRole: String, Codable, CaseIterable, Sendable {
    case basic        // Hand-authored controls
    case scenes       // Scene selection (dynamic)
    case scenes2      // Additional scene page (dynamic, legacy)
    case presets      // Preset selection (dynamic)
    case params       // Dynamic control parameters (auto populated)
    case global       // Global parameters
    case favorites    // Favorites/quick actions
    case shaders      // VJUniverse shader selection
    case audio        // Audio bindings/controls
    case visual       // Visual controls
    case custom       // User/learn
}

// MARK: - Bank Layout Policy

/// Paging behavior for right-column buttons
public enum PagingPolicy: Sendable, Equatable {
    case none
    /// Map right-column rows to absolute page indices (in order)
    case rowButtons(rows: [Int])
    /// Single button cycles pages (row index for the button)
    case nextButton(row: Int)
}

/// Per-bank layout rules (recordable rows, paging, presets row)
public struct BankLayoutPolicy: Sendable, Equatable {
    public let recordableRows: [Int]
    public let paging: PagingPolicy
    public let presetsRow: Int?

    public init(
        recordableRows: [Int] = Array(0...7),
        paging: PagingPolicy = .rowButtons(rows: [1, 2, 3, 4, 5, 6]),
        presetsRow: Int? = nil
    ) {
        self.recordableRows = recordableRows
        self.paging = paging
        self.presetsRow = presetsRow
    }

    public func isRecordable(padId: ButtonId) -> Bool {
        guard padId.isGrid else { return false }
        return recordableRows.contains(padId.y)
    }
}

// MARK: - OSC Command

/// OSC command to send
public struct OscCommand: Hashable, Codable, Sendable {
    public let address: String
    public let args: [OscArg]
    
    public init(address: String, args: [OscArg] = []) {
        self.address = address
        self.args = args
    }
    
    /// Check if this OSC address is controllable (can be mapped to pads)
    public var isControllable: Bool {
        // Controllable addresses for Synesthesia (matches Python synesthesia_config.py)
        let controllablePrefixes = [
            "/scenes/",
            "/presets/",
            "/favslots/",
            "/playlist/",
            "/media/",
            "/render/",
            "/controls/",  // All controls (meta, global, etc.)
        ]
        return controllablePrefixes.contains { address.hasPrefix($0) }
    }
}

/// Type-safe OSC argument
public enum OscArg: Hashable, Codable, Sendable {
    case int(Int)
    case float(Float)
    case string(String)
    case bool(Bool)
    
    public var description: String {
        switch self {
        case .int(let v): return "\(v)"
        case .float(let v): return "\(v)"
        case .string(let v): return v
        case .bool(let v): return v ? "true" : "false"
        }
    }
}

// MARK: - Pad Behavior Configuration

/// Configuration for how a pad behaves
public struct PadBehavior: Codable, Sendable {
    public let padId: ButtonId
    public let mode: PadMode
    public let group: ButtonGroupType?
    public let idleColor: Int
    public let activeColor: Int
    public let label: String
    
    // Toggle-specific
    public let oscOn: OscCommand?
    public let oscOff: OscCommand?
    
    // Selector/One-shot specific
    public let oscAction: OscCommand?
    
    // Additional OSC commands to send (e.g., control values after scene)
    public let additionalOsc: [OscCommand]
    
    // Increment/Decrement mode: step size and value range
    public let step: Float
    public let minValue: Float
    public let maxValue: Float

    enum CodingKeys: String, CodingKey {
        case padId, mode, group, idleColor, activeColor, label, oscOn, oscOff, oscAction, additionalOsc, step, minValue, maxValue
    }
    
    public init(
        padId: ButtonId,
        mode: PadMode,
        group: ButtonGroupType? = nil,
        idleColor: Int = LP.off,
        activeColor: Int = LP.green,
        label: String = "",
        oscOn: OscCommand? = nil,
        oscOff: OscCommand? = nil,
        oscAction: OscCommand? = nil,
        additionalOsc: [OscCommand] = [],
        step: Float = 0.1,
        minValue: Float = 0.0,
        maxValue: Float = 1.0
    ) {
        self.padId = padId
        self.mode = mode
        self.group = group
        self.idleColor = idleColor
        self.activeColor = activeColor
        self.label = label
        self.oscOn = oscOn
        self.oscOff = oscOff
        self.oscAction = oscAction
        self.additionalOsc = additionalOsc
        self.step = step
        self.minValue = minValue
        self.maxValue = maxValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        padId = try container.decode(ButtonId.self, forKey: .padId)
        mode = try container.decode(PadMode.self, forKey: .mode)
        group = try container.decodeIfPresent(ButtonGroupType.self, forKey: .group)
        idleColor = try container.decodeIfPresent(Int.self, forKey: .idleColor) ?? LP.off
        activeColor = try container.decodeIfPresent(Int.self, forKey: .activeColor) ?? LP.green
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        oscOn = try container.decodeIfPresent(OscCommand.self, forKey: .oscOn)
        oscOff = try container.decodeIfPresent(OscCommand.self, forKey: .oscOff)
        oscAction = try container.decodeIfPresent(OscCommand.self, forKey: .oscAction)
        additionalOsc = try container.decodeIfPresent([OscCommand].self, forKey: .additionalOsc) ?? []
        step = try container.decodeIfPresent(Float.self, forKey: .step) ?? 0.1
        minValue = try container.decodeIfPresent(Float.self, forKey: .minValue) ?? 0.0
        maxValue = try container.decodeIfPresent(Float.self, forKey: .maxValue) ?? 1.0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(padId, forKey: .padId)
        try container.encode(mode, forKey: .mode)
        try container.encodeIfPresent(group, forKey: .group)
        try container.encode(idleColor, forKey: .idleColor)
        try container.encode(activeColor, forKey: .activeColor)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(oscOn, forKey: .oscOn)
        try container.encodeIfPresent(oscOff, forKey: .oscOff)
        try container.encodeIfPresent(oscAction, forKey: .oscAction)
        if !additionalOsc.isEmpty { try container.encode(additionalOsc, forKey: .additionalOsc) }
        try container.encode(step, forKey: .step)
        try container.encode(minValue, forKey: .minValue)
        try container.encode(maxValue, forKey: .maxValue)
    }
}

// MARK: - Pad Runtime State

/// Runtime state of a pad (changes during operation)
public struct PadRuntimeState: Sendable {
    public var isActive: Bool
    public var isOn: Bool
    public var currentColor: Int
    public var blinkEnabled: Bool
    public var ledMode: LedMode
    /// Current value for increment/decrement controls (0.0-1.0)
    public var currentValue: Float
    
    public init(
        isActive: Bool = false,
        isOn: Bool = false,
        currentColor: Int = LP.off,
        blinkEnabled: Bool = false,
        ledMode: LedMode = .static,
        currentValue: Float = 0.5
    ) {
        self.isActive = isActive
        self.isOn = isOn
        self.currentColor = currentColor
        self.blinkEnabled = blinkEnabled
        self.ledMode = ledMode
        self.currentValue = currentValue
    }
}

// MARK: - Learn Mode State

/// Phases within learn mode
public enum LearnPhase: Sendable {
    /// Normal operation - pads execute their configured behaviors
    case idle
    /// Blinking all pads, waiting for user to press a pad to configure
    case waitPad
    /// Configuration phase - live capture + selecting OSC/mode/colors
    case config
}

/// Register (configuration section) in learn config phase
public enum LearnRegister: Sendable {
    case oscSelect
    case modeSelect
    case colorSelect
}

/// Captured OSC command with enabled state
public struct CapturedOsc: Sendable, Hashable {
    public let command: OscCommand
    public let priority: Int
    public var isEnabled: Bool
    
    public init(command: OscCommand, priority: Int, isEnabled: Bool = true) {
        self.command = command
        self.priority = priority
        self.isEnabled = isEnabled
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(command.address)
    }
    
    public static func == (lhs: CapturedOsc, rhs: CapturedOsc) -> Bool {
        lhs.command.address == rhs.command.address
    }
}

/// Received OSC event with timestamp
public struct OscEvent: Sendable {
    public let timestamp: Date
    public let address: String
    public let args: [OscArg]
    public let priority: Int  // Lower = higher priority
    
    public init(timestamp: Date = Date(), address: String, args: [OscArg] = [], priority: Int = 99) {
        self.timestamp = timestamp
        self.address = address
        self.args = args
        self.priority = priority
    }
    
    /// Convert to OscCommand
    public func toCommand() -> OscCommand {
        OscCommand(address: address, args: args)
    }
}

/// State for Learn Mode FSM
public struct LearnState: Sendable {
    public var phase: LearnPhase
    public var selectedPad: ButtonId?
    public var capturedOsc: [CapturedOsc]  // Live-captured with enable/disable
    
    // CONFIG phase state
    public var activeRegister: LearnRegister
    public var selectedMode: PadMode?
    public var selectedGroup: ButtonGroupType?
    public var selectedColor: Int  // Single color - blinks on active/pressed=white
    public var oscPage: Int
    
    public init() {
        self.phase = .idle
        self.selectedPad = nil
        self.capturedOsc = []
        self.activeRegister = .oscSelect
        self.selectedMode = nil
        self.selectedGroup = nil
        self.selectedColor = LP.green
        self.oscPage = 0
    }
    
    /// Get enabled commands sorted by priority
    public var enabledCommands: [OscCommand] {
        capturedOsc
            .filter { $0.isEnabled }
            .sorted { $0.priority < $1.priority }
            .map { $0.command }
    }
    
    /// Get primary (first enabled, highest priority) command
    public var primaryCommand: OscCommand? {
        enabledCommands.first
    }
}

// MARK: - Bank System

/// Bank configuration - 8 banks, each with distinct color
public struct BankConfig: Sendable {
    public static let count = 8
    
    /// Colors for each bank (top row buttons)
    public static let colors: [Int] = [
        LP.red,      // Bank 0
        LP.orange,   // Bank 1
        LP.yellow,   // Bank 2
        LP.green,    // Bank 3
        LP.cyan,     // Bank 4
        LP.blue,     // Bank 5
        LP.purple,   // Bank 6
        LP.pink      // Bank 7
    ]
    
    /// Get color for bank index
    public static func color(for bank: Int) -> Int {
        guard bank >= 0 && bank < colors.count else { return LP.white }
        return colors[bank]
    }
    
    /// Dim version of bank color (for inactive banks)
    public static func dimColor(for bank: Int) -> Int {
        // Return a dimmer version - use offset in Launchpad palette
        let baseColor = color(for: bank)
        // Launchpad colors: bright versions are typically +2 from dim
        // We'll use a simple mapping for common colors
        switch baseColor {
        case LP.red: return LP.redDim
        case LP.green: return LP.greenDim
        case LP.blue: return LP.blueDim
        default: return baseColor  // No dim version, use same
        }
    }
}

// MARK: - Controller State

/// Complete controller state (immutable pattern - create new instance for updates)
public struct ControllerState: Sendable {
    /// Active bank (0-7)
    public var activeBank: Int
    
    /// Pad configurations per bank: [bankIndex: [ButtonId: PadBehavior]]
    public var bankPads: [Int: [ButtonId: PadBehavior]]
    
    /// Runtime state per bank: [bankIndex: [ButtonId: PadRuntimeState]]
    public var bankPadRuntime: [Int: [ButtonId: PadRuntimeState]]
    
    /// Active selector per group per bank
    public var bankActiveSelectorByGroup: [Int: [ButtonGroupType: ButtonId?]]
    
    // Convenience accessors for current bank
    public var pads: [ButtonId: PadBehavior] {
        get { bankPads[activeBank] ?? [:] }
        set { bankPads[activeBank] = newValue }
    }
    
    public var padRuntime: [ButtonId: PadRuntimeState] {
        get { bankPadRuntime[activeBank] ?? [:] }
        set { bankPadRuntime[activeBank] = newValue }
    }
    
    public var activeSelectorByGroup: [ButtonGroupType: ButtonId?] {
        get { bankActiveSelectorByGroup[activeBank] ?? [:] }
        set { bankActiveSelectorByGroup[activeBank] = newValue }
    }
    
    // Synesthesia state
    public var activeScene: String?
    public var activePreset: String?
    public var activeColorHue: Float?
    
    // Audio/beat state
    public var beatPhase: Float
    public var beatPulse: Bool
    
    // FSM state
    public var learnState: LearnState
    
    // Animation state
    public var blinkOn: Bool
    
    // Modifier keys
    /// Shift button held (scene button y=5)
    public var isShiftHeld: Bool

    /// Page counts per bank and current page per bank
    public var bankPageCount: [Int: Int]
    public var bankCurrentPage: [Int: Int]

    /// Layout policy per bank
    public var bankLayout: [Int: BankLayoutPolicy]

    /// Current page for active bank
    public var currentPage: Int {
        get { bankCurrentPage[activeBank] ?? 0 }
        set { bankCurrentPage[activeBank] = newValue }
    }
    /// Page count for active bank
    public var currentPageCount: Int { bankPageCount[activeBank] ?? 1 }
    
    public init() {
        self.activeBank = 0
        self.bankPads = [:]
        self.bankPadRuntime = [:]
        self.bankActiveSelectorByGroup = [:]
        
        // Initialize empty banks
        for i in 0..<BankConfig.count {
            self.bankPads[i] = [:]
            self.bankPadRuntime[i] = [:]
            self.bankActiveSelectorByGroup[i] = [:]
        }
        
        self.activeScene = nil
        self.activePreset = nil
        self.activeColorHue = nil
        self.beatPhase = 0
        self.beatPulse = false
        self.learnState = LearnState()
        self.blinkOn = false
        self.isShiftHeld = false
        self.bankPageCount = [:]
        self.bankCurrentPage = [:]
        self.bankLayout = [:]
        for i in 0..<BankConfig.count {
            self.bankPageCount[i] = 1
            self.bankCurrentPage[i] = 0
            self.bankLayout[i] = BankLayoutPolicy()
        }
    }

    /// Layout policy for active bank
    public var currentLayout: BankLayoutPolicy {
        bankLayout[activeBank] ?? BankLayoutPolicy()
    }
}

// MARK: - Effects (Side effect descriptions)

/// Log level for effects
public enum LogLevel: String, Sendable {
    case debug, info, warning, error
}

/// Side effects produced by FSM transitions
public enum LaunchpadEffect: Sendable {
    /// Send an OSC command
    case sendOsc(OscCommand)
    /// Set a Launchpad LED
    case setLed(padId: ButtonId, color: Int, blink: Bool)
    /// Save configuration to disk
    case saveConfig
    /// Log a message
    case log(message: String, level: LogLevel)
}

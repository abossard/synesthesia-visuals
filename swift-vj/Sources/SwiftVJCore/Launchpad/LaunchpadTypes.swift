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
public enum LaunchpadColor: String, CaseIterable, Sendable {
    case red, orange, yellow, lime, green, cyan, blue, purple, pink, white
    
    /// Velocity values for each brightness level
    public var velocities: (dim: Int, normal: Int, bright: Int) {
        switch self {
        case .red:    return (1, 5, 6)
        case .orange: return (7, 9, 10)
        case .yellow: return (11, 13, 14)
        case .lime:   return (15, 17, 18)
        case .green:  return (19, 21, 22)
        case .cyan:   return (33, 37, 38)
        case .blue:   return (41, 45, 46)
        case .purple: return (49, 53, 54)
        case .pink:   return (55, 57, 58)
        case .white:  return (1, 3, 119)
        }
    }
    
    /// Get velocity for a brightness level
    public func velocity(at brightness: BrightnessLevel) -> Int {
        switch brightness {
        case .dim:    return velocities.dim
        case .normal: return velocities.normal
        case .bright: return velocities.bright
        }
    }
}

/// Brightness levels for Launchpad LEDs
public enum BrightnessLevel: Int, Sendable {
    case dim = 0      // ~33% brightness
    case normal = 1   // ~66% brightness
    case bright = 2   // 100% brightness
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
    public static let yellow = 13
    public static let green = 21
    public static let greenDim = 19
    public static let cyan = 37
    public static let blue = 45
    public static let blueDim = 41
    public static let purple = 53
    public static let pink = 57
    public static let white = 3
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
        // Controllable addresses for Synesthesia
        let controllablePrefixes = [
            "/syn/scene/",
            "/syn/preset/",
            "/syn/control/",
            "/shader/",
            "/image/",
            "/midi/"
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
    
    public init(
        padId: ButtonId,
        mode: PadMode,
        group: ButtonGroupType? = nil,
        idleColor: Int = LP.off,
        activeColor: Int = LP.green,
        label: String = "",
        oscOn: OscCommand? = nil,
        oscOff: OscCommand? = nil,
        oscAction: OscCommand? = nil
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
    
    public init(
        isActive: Bool = false,
        isOn: Bool = false,
        currentColor: Int = LP.off,
        blinkEnabled: Bool = false,
        ledMode: LedMode = .static
    ) {
        self.isActive = isActive
        self.isOn = isOn
        self.currentColor = currentColor
        self.blinkEnabled = blinkEnabled
        self.ledMode = ledMode
    }
}

// MARK: - Learn Mode State

/// Phases within learn mode
public enum LearnPhase: Sendable {
    /// Normal operation - pads execute their configured behaviors
    case idle
    /// Blinking all pads, waiting for user to press a pad to configure
    case waitPad
    /// Recording OSC messages after pad selected
    case recordOsc
    /// Configuration phase - selecting OSC/mode/colors
    case config
}

/// Register (configuration section) in learn config phase
public enum LearnRegister: Sendable {
    case oscSelect
    case modeSelect
    case colorSelect
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
    public var recordedEvents: [OscEvent]
    public var candidateCommands: [OscCommand]
    
    // CONFIG phase state
    public var activeRegister: LearnRegister
    public var selectedOscIndex: Int
    public var selectedMode: PadMode?
    public var selectedGroup: ButtonGroupType?
    public var selectedIdleColor: Int
    public var selectedActiveColor: Int
    public var idleBrightness: BrightnessLevel
    public var activeBrightness: BrightnessLevel
    public var oscPage: Int
    
    public init() {
        self.phase = .idle
        self.selectedPad = nil
        self.recordedEvents = []
        self.candidateCommands = []
        self.activeRegister = .oscSelect
        self.selectedOscIndex = 0
        self.selectedMode = nil
        self.selectedGroup = nil
        self.selectedIdleColor = LP.greenDim
        self.selectedActiveColor = LP.green
        self.idleBrightness = .normal
        self.activeBrightness = .bright
        self.oscPage = 0
    }
}

// MARK: - Controller State

/// Complete controller state (immutable pattern - create new instance for updates)
public struct ControllerState: Sendable {
    public var pads: [ButtonId: PadBehavior]
    public var padRuntime: [ButtonId: PadRuntimeState]
    public var activeSelectorByGroup: [ButtonGroupType: ButtonId?]
    
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
    
    public init() {
        self.pads = [:]
        self.padRuntime = [:]
        self.activeSelectorByGroup = [:]
        self.activeScene = nil
        self.activePreset = nil
        self.activeColorHue = nil
        self.beatPhase = 0
        self.beatPulse = false
        self.learnState = LearnState()
        self.blinkOn = false
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

// LaunchpadYAMLConfig.swift - Type-safe YAML configuration for Launchpad
//
// Loads launchpad-config.yaml and provides strongly-typed access to all settings.
// Includes validation with detailed error messages.

import Foundation
import Yams

// MARK: - Root Config

/// Top-level configuration loaded from launchpad-config.yaml
public struct LaunchpadYAMLConfig: Codable, Sendable {
    public let version: Int
    public let colors: [String: Int]
    public let groups: [String: GroupConfig]
    public let global: GlobalYAMLConfig
    public let bank0: BankYAMLConfig
    public let bank1: BankYAMLConfig
    public let bank2: BankYAMLConfig
    public let bank3: BankYAMLConfig
    public let bank4: BankYAMLConfig
    public let bank5: BankYAMLConfig
    public let bank6: BankYAMLConfig
    public let bank7: BankYAMLConfig
    
    /// Get bank config by index (0-7)
    public func bank(_ index: Int) -> BankYAMLConfig? {
        switch index {
        case 0: return bank0
        case 1: return bank1
        case 2: return bank2
        case 3: return bank3
        case 4: return bank4
        case 5: return bank5
        case 6: return bank6
        case 7: return bank7
        default: return nil
        }
    }
    
    /// Resolve a color name to its index (0 if not found)
    public func color(_ name: String) -> Int {
        colors[name] ?? 0
    }
    
    /// Get items for a group (resolves static items, dynamic from cache)
    public func groupItems(_ groupName: String) -> [String] {
        guard let group = groups[groupName] else { return [] }
        if group.type == "static" {
            return group.items ?? []
        }
        // Dynamic groups - return empty, use groupItemsAsync for runtime resolution
        return []
    }
    
    /// Get items for a group with async dynamic resolution
    public func groupItemsAsync(_ groupName: String) async -> [String] {
        guard let group = groups[groupName] else { return [] }
        if group.type == "static" {
            return group.items ?? []
        }
        // Dynamic groups - fetch from shared store
        if let source = group.source {
            return await DynamicGroupStore.shared.items(for: source)
        }
        return []
    }
}

// MARK: - Group Config

public struct GroupConfig: Codable, Sendable {
    public let type: String  // "static" or "dynamic"
    public let items: [String]?  // For static groups
    public let source: String?   // For dynamic groups (e.g., "$synesthesia/scenes")
    public let parent: String?   // Parent group name (resets when parent changes)
}

// MARK: - Global Config

public struct GlobalYAMLConfig: Codable, Sendable {
    public let bankButtons: [BankButtonYAMLConfig]
    public let sceneButtons: [SceneButtonYAMLConfig]
}

public struct BankButtonYAMLConfig: Codable, Sendable {
    public let cc: Int
    public let bank: Int
    public let name: String
    public let idleColor: String
    public let activeColor: String
}

public struct SceneButtonYAMLConfig: Codable, Sendable {
    public let note: Int
    public let function: String  // "record", "shift"
    public let label: String
    public let idleColor: String
    public let activeColor: String
}

// MARK: - Bank Config

public struct BankYAMLConfig: Codable, Sendable {
    public let name: String
    public let purpose: String
    public let pads: [PadYAMLConfig]
    public let programmableRows: [Int]
    
    /// Check if a row is programmable
    public func isRowProgrammable(_ row: Int) -> Bool {
        programmableRows.contains(row)
    }
    
    /// Check if a pad position is fixed (defined in pads array)
    public func isFixed(x: Int, y: Int) -> Bool {
        pads.contains { $0.x == x && $0.y == y }
    }
}

// MARK: - Pad Config

public struct PadYAMLConfig: Codable, Sendable {
    public let x: Int
    public let y: Int
    public let mode: String  // "oneShot", "toggle", "selector", "push", "increment", "decrement"
    public let label: String?
    public let group: String?      // For selector mode
    public let index: Int?         // For selector mode - index into group items
    public let idleColor: String?
    public let activeColor: String?
    
    // OSC commands
    public let osc: OscYAMLConfig?     // For oneShot/push/increment/decrement
    public let oscOn: OscYAMLConfig?   // For toggle
    public let oscOff: OscYAMLConfig?  // For toggle
    
    // Increment/Decrement mode settings
    public let step: Double?       // Step size (default 0.1)
    public let minValue: Double?   // Minimum value (default 0.0)
    public let maxValue: Double?   // Maximum value (default 1.0)
}

public struct OscYAMLConfig: Codable, Sendable {
    public let address: String
    public let args: [YAMLArg]?
    
    public init(address: String, args: [YAMLArg]? = nil) {
        self.address = address
        self.args = args
    }
}

// MARK: - YAML Argument (flexible type)

/// Flexible YAML argument that can be int, float, string, or bool
public enum YAMLArg: Codable, Sendable, Equatable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        // Try types in order: bool first (before int), then int, float, string
        if let boolVal = try? container.decode(Bool.self) {
            self = .bool(boolVal)
        } else if let intVal = try? container.decode(Int.self) {
            self = .int(intVal)
        } else if let doubleVal = try? container.decode(Double.self) {
            self = .float(doubleVal)
        } else if let stringVal = try? container.decode(String.self) {
            self = .string(stringVal)
        } else {
            throw DecodingError.typeMismatch(
                YAMLArg.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected int, float, string, or bool"
                )
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let v): try container.encode(v)
        case .float(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        }
    }
    
    /// Convert to runtime OscArg
    public func toOscArg() -> OscArg {
        switch self {
        case .int(let v): return .int(v)
        case .float(let v): return .float(Float(v))
        case .string(let v): return .string(v)
        case .bool(let v): return .bool(v)
        }
    }
}

// MARK: - YAML Loader

public enum LaunchpadConfigLoader {
    
    /// Load config from bundled YAML file
    public static func loadBundled() throws -> LaunchpadYAMLConfig {
        guard let url = Bundle.module.url(forResource: "launchpad-config", withExtension: "yaml") else {
            throw ConfigError.fileNotFound("launchpad-config.yaml not in bundle")
        }
        return try load(from: url)
    }
    
    /// Load config from URL
    public static func load(from url: URL) throws -> LaunchpadYAMLConfig {
        let data = try Data(contentsOf: url)
        return try parse(data, source: url.path)
    }
    
    /// Load config from string
    public static func load(from yamlString: String) throws -> LaunchpadYAMLConfig {
        guard let data = yamlString.data(using: .utf8) else {
            throw ConfigError.invalidEncoding
        }
        return try parse(data, source: "<string>")
    }
    
    /// Parse YAML data with detailed error messages
    private static func parse(_ data: Data, source: String) throws -> LaunchpadYAMLConfig {
        do {
            let decoder = YAMLDecoder()
            let config = try decoder.decode(LaunchpadYAMLConfig.self, from: data)
            
            // Validate the config
            try validate(config, source: source)
            
            return config
        } catch let error as DecodingError {
            throw ConfigError.parseError(formatDecodingError(error, source: source))
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.parseError("Failed to parse YAML: \(error.localizedDescription)")
        }
    }
    
    /// Validate loaded config
    private static func validate(_ config: LaunchpadYAMLConfig, source: String) throws {
        var errors: [String] = []
        
        // Validate version
        if config.version < 1 {
            errors.append("Invalid version: \(config.version) (expected >= 1)")
        }
        
        // Validate colors referenced in pads exist
        for bankIndex in 0..<8 {
            guard let bank = config.bank(bankIndex) else { continue }
            for pad in bank.pads {
                if let color = pad.idleColor, config.colors[color] == nil {
                    errors.append("Bank \(bankIndex) pad (\(pad.x),\(pad.y)): unknown idleColor '\(color)'")
                }
                if let color = pad.activeColor, config.colors[color] == nil {
                    errors.append("Bank \(bankIndex) pad (\(pad.x),\(pad.y)): unknown activeColor '\(color)'")
                }
                
                // Validate mode-specific requirements
                switch pad.mode {
                case "selector":
                    if pad.group == nil {
                        errors.append("Bank \(bankIndex) pad (\(pad.x),\(pad.y)): selector mode requires 'group'")
                    } else if config.groups[pad.group!] == nil {
                        errors.append("Bank \(bankIndex) pad (\(pad.x),\(pad.y)): unknown group '\(pad.group!)'")
                    }
                    if pad.index == nil {
                        errors.append("Bank \(bankIndex) pad (\(pad.x),\(pad.y)): selector mode requires 'index'")
                    }
                case "toggle":
                    if pad.oscOn == nil || pad.oscOff == nil {
                        errors.append("Bank \(bankIndex) pad (\(pad.x),\(pad.y)): toggle mode requires 'oscOn' and 'oscOff'")
                    }
                case "oneShot", "push":
                    // osc is optional for these modes (may just be visual indicator)
                    break
                default:
                    errors.append("Bank \(bankIndex) pad (\(pad.x),\(pad.y)): unknown mode '\(pad.mode)'")
                }
            }
        }
        
        // Validate global button colors
        for btn in config.global.bankButtons {
            if config.colors[btn.idleColor] == nil {
                errors.append("Bank button CC \(btn.cc): unknown idleColor '\(btn.idleColor)'")
            }
            if config.colors[btn.activeColor] == nil {
                errors.append("Bank button CC \(btn.cc): unknown activeColor '\(btn.activeColor)'")
            }
        }
        
        if !errors.isEmpty {
            throw ConfigError.validationFailed(errors)
        }
    }
    
    /// Format decoding error with line information
    private static func formatDecodingError(_ error: DecodingError, source: String) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(source): Missing required key '\(key.stringValue)' at path '\(path)'"
            
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(source): Type mismatch at '\(path)': expected \(type)"
            
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(source): Missing value at '\(path)': expected \(type)"
            
        case .dataCorrupted(let context):
            let path = context.codingPath.map { $0.stringValue }.joined(separator: ".")
            return "\(source): Data corrupted at '\(path)': \(context.debugDescription)"
            
        @unknown default:
            return "\(source): Unknown decoding error: \(error)"
        }
    }
    
    public enum ConfigError: Error, LocalizedError {
        case fileNotFound(String)
        case invalidEncoding
        case parseError(String)
        case validationFailed([String])
        
        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "Config file not found: \(path)"
            case .invalidEncoding:
                return "Invalid UTF-8 encoding in YAML file"
            case .parseError(let msg):
                return "YAML parse error: \(msg)"
            case .validationFailed(let errors):
                return "Config validation failed:\n  - " + errors.joined(separator: "\n  - ")
            }
        }
    }
}

// MARK: - Global Layout Helpers

public extension LaunchpadYAMLConfig {
    
    /// Get all bank button CCs
    var bankButtonCCs: [Int] {
        global.bankButtons.map { $0.cc }
    }
    
    /// Check if a CC is a bank button
    func isBankCC(_ cc: Int) -> Bool {
        global.bankButtons.contains { $0.cc == cc }
    }
    
    /// Get bank index from CC (0-7), or nil if not a bank CC
    func bankIndex(fromCC cc: Int) -> Int? {
        global.bankButtons.first { $0.cc == cc }?.bank
    }
    
    /// Check if a MIDI note is a fixed global scene button
    func isFixedSceneNote(_ note: Int) -> Bool {
        global.sceneButtons.contains { $0.note == note }
    }
    
    /// Get scene button function ("record", "shift") from note
    func sceneButtonFunction(_ note: Int) -> String? {
        global.sceneButtons.first { $0.note == note }?.function
    }
    
    /// Get bank name by index
    func bankName(_ index: Int) -> String {
        bank(index)?.name ?? "Bank \(index)"
    }
    
    /// Get bank purpose by index
    func bankPurpose(_ index: Int) -> String {
        bank(index)?.purpose ?? ""
    }
}

// MARK: - Dynamic Group Resolution

/// Protocol for resolving dynamic groups at runtime
public protocol DynamicGroupResolver: Sendable {
    /// Resolve items for a dynamic group source (e.g., "$synesthesia/scenes")
    func resolveItems(source: String) async -> [String]
}

/// Default resolver that returns empty arrays (used when no external data source)
public struct EmptyGroupResolver: DynamicGroupResolver {
    public init() {}
    public func resolveItems(source: String) async -> [String] {
        return []
    }
}

/// Mutable group data store for dynamic groups
public actor DynamicGroupStore {
    public static let shared = DynamicGroupStore()
    
    private var cache: [String: [String]] = [:]
    
    public init() {}
    
    /// Update items for a dynamic source
    public func update(source: String, items: [String]) {
        cache[source] = items
    }
    
    /// Get cached items for a source
    public func items(for source: String) -> [String] {
        cache[source] ?? []
    }
    
    /// Clear all cached data
    public func clear() {
        cache.removeAll()
    }
}

// MARK: - Config to Runtime Conversion

public extension LaunchpadYAMLConfig {
    
    /// Convert a pad config to runtime PadBehavior
    func toBehavior(pad: PadYAMLConfig) -> PadBehavior {
        let padId = ButtonId(x: pad.x, y: pad.y)
        
        // Resolve colors
        let idleColor = pad.idleColor.flatMap { color($0) } ?? LP.off
        let activeColor = pad.activeColor.flatMap { color($0) } ?? LP.green
        
        // Resolve mode
        let mode = PadMode(rawValue: pad.mode) ?? .oneShot
        
        // Resolve group
        let groupType: ButtonGroupType?
        if let groupName = pad.group {
            groupType = ButtonGroupType(rawValue: groupName) ?? .custom
        } else {
            groupType = nil
        }
        
        // Resolve OSC commands
        var oscAction: OscCommand? = nil
        var oscOn: OscCommand? = nil
        var oscOff: OscCommand? = nil
        
        if mode == .selector, let groupName = pad.group, let index = pad.index {
            // Selector: generate OSC from group items
            let items = groupItems(groupName)
            let itemName = index < items.count ? items[index] : "Item \(index)"
            
            // Generate appropriate OSC based on group type
            let address: String
            switch groupName {
            case "playlists": address = "/playlist/select"
            case "scenes": address = "/scenes/select"
            case "presets": address = "/presets/select"
            default: address = "/\(groupName)/select"
            }
            
            oscAction = OscCommand(address: address, args: [.string(itemName)])
        } else if let osc = pad.osc {
            oscAction = OscCommand(
                address: osc.address,
                args: osc.args?.map { $0.toOscArg() } ?? []
            )
        }
        
        if let on = pad.oscOn {
            oscOn = OscCommand(
                address: on.address,
                args: on.args?.map { $0.toOscArg() } ?? []
            )
        }
        
        if let off = pad.oscOff {
            oscOff = OscCommand(
                address: off.address,
                args: off.args?.map { $0.toOscArg() } ?? []
            )
        }
        
        // Determine label
        let label: String
        if let padLabel = pad.label {
            label = padLabel
        } else if mode == .selector, let groupName = pad.group, let index = pad.index {
            let items = groupItems(groupName)
            label = index < items.count ? items[index] : "Item \(index)"
        } else {
            label = ""
        }
        
        return PadBehavior(
            padId: padId,
            mode: mode,
            group: groupType,
            idleColor: idleColor,
            activeColor: activeColor,
            label: label,
            oscOn: oscOn,
            oscOff: oscOff,
            oscAction: oscAction,
            step: Float(pad.step ?? 0.1),
            minValue: Float(pad.minValue ?? 0.0),
            maxValue: Float(pad.maxValue ?? 1.0)
        )
    }
    
    /// Get all behaviors for a bank
    func bankBehaviors(_ bankIndex: Int) -> [ButtonId: PadBehavior] {
        guard let bank = bank(bankIndex) else { return [:] }
        
        var result: [ButtonId: PadBehavior] = [:]
        for pad in bank.pads {
            let behavior = toBehavior(pad: pad)
            result[behavior.padId] = behavior
        }
        return result
    }
    
    /// Check if a pad is fixed in a bank
    func isFixed(bank: Int, x: Int, y: Int) -> Bool {
        guard let bankConfig = self.bank(bank) else { return false }
        return bankConfig.isFixed(x: x, y: y)
    }
    
    /// Get all fixed pad IDs for a bank
    func fixedPadIds(bank: Int) -> Set<ButtonId> {
        guard let bankConfig = self.bank(bank) else { return [] }
        return Set(bankConfig.pads.map { ButtonId(x: $0.x, y: $0.y) })
    }
}

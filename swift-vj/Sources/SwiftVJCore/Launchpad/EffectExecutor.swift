// EffectExecutor.swift - Imperative shell for LaunchpadEffect
// Phase 5: MIDI Controller
//
// Executes effects returned by the pure FSM

import Foundation

// MARK: - Config File Format

/// Top-level config file structure (versioned for future migrations)
public struct LaunchpadConfigFile: Codable, Sendable {
    public static let currentVersion = 2
    
    public let version: Int
    public let banks: [String: [String: PadBehavior]]  // "0".."7" → "x,y" → behavior
    
    public init(version: Int = LaunchpadConfigFile.currentVersion, banks: [String: [String: PadBehavior]] = [:]) {
        self.version = version
        self.banks = banks
    }
    
    /// Create from in-memory bank configs
    public init(from bankConfigs: [Int: [ButtonId: PadBehavior]]) {
        self.version = Self.currentVersion
        var banks: [String: [String: PadBehavior]] = [:]
        for (bankIndex, pads) in bankConfigs {
            var padDict: [String: PadBehavior] = [:]
            for (padId, behavior) in pads {
                padDict["\(padId.x),\(padId.y)"] = behavior
            }
            banks["\(bankIndex)"] = padDict
        }
        self.banks = banks
    }
    
    /// Convert to in-memory format
    public func toBankConfigs() -> [Int: [ButtonId: PadBehavior]] {
        var result: [Int: [ButtonId: PadBehavior]] = [:]
        for (bankKey, pads) in banks {
            guard let bankIndex = Int(bankKey) else { continue }
            var padDict: [ButtonId: PadBehavior] = [:]
            for (padKey, behavior) in pads {
                let parts = padKey.split(separator: ",")
                if parts.count == 2,
                   let x = Int(parts[0]),
                   let y = Int(parts[1]) {
                    padDict[ButtonId(x: x, y: y)] = behavior
                }
            }
            result[bankIndex] = padDict
        }
        return result
    }
}

/// Executes LaunchpadEffect cases (imperative shell)
public final class EffectExecutor {
    
    // MARK: - Dependencies
    
    private let midi: MIDIManager
    private let oscSender: ((OscCommand) -> Void)?
    private let configPath: URL
    
    // MARK: - State (per-bank storage)
    
    private var bankConfigs: [Int: [ButtonId: PadBehavior]] = [:]
    private var activeBank: Int = 0
    
    /// YAML config (fixed layouts + settings)
    public private(set) var yamlConfig: LaunchpadYAMLConfig?
    
    // MARK: - Init
    
    public init(
        midi: MIDIManager,
        oscSender: ((OscCommand) -> Void)? = nil,
        configPath: URL? = nil
    ) {
        self.midi = midi
        self.oscSender = oscSender
        self.configPath = configPath ?? Self.defaultConfigPath
        
        // Load YAML config
        do {
            self.yamlConfig = try LaunchpadConfigLoader.loadBundled()
        } catch {
            print("[Config] Failed to load YAML config: \(error)")
        }
    }
    
    public static var defaultConfigPath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("SwiftVJ/launchpad-config.json")
    }
    
    // MARK: - Execute
    
    /// Execute a single effect
    public func execute(_ effect: LaunchpadEffect) {
        switch effect {
        case .sendOsc(let command):
            executeOsc(command)
            
        case .setLed(let padId, let color, let blink):
            executeLed(padId: padId, color: color, blink: blink)
            
        case .saveConfig:
            executeSaveConfig()
            
        case .log(let message, let level):
            executeLog(message: message, level: level)
        }
    }
    
    /// Execute multiple effects
    public func executeAll(_ effects: [LaunchpadEffect]) {
        for effect in effects {
            execute(effect)
        }
    }
    
    // MARK: - Effect Handlers
    
    private func executeOsc(_ command: OscCommand) {
        oscSender?(command)
    }
    
    private func executeLed(padId: ButtonId, color: Int, blink: Bool) {
        // Use native Launchpad pulsing for blink mode
        if blink {
            midi.setLed(padId: padId, color: color, mode: .pulse)
        } else {
            midi.setLed(padId: padId, color: color, mode: .solid)
        }
    }
    
    private func executeSaveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            let configFile = LaunchpadConfigFile(from: bankConfigs)
            let data = try encoder.encode(configFile)
            
            // Ensure directory exists
            try FileManager.default.createDirectory(
                at: configPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            try data.write(to: configPath)
            let totalPads = bankConfigs.values.reduce(0) { $0 + $1.count }
            print("[Config] Saved \(totalPads) pad configs across \(bankConfigs.count) banks to \(configPath.path)")
            
        } catch {
            print("[Config] Save failed: \(error)")
        }
    }
    
    private func executeLog(message: String, level: LogLevel) {
        let prefix: String
        switch level {
        case .debug: prefix = "[DEBUG]"
        case .info: prefix = "[INFO]"
        case .warning: prefix = "[WARN]"
        case .error: prefix = "[ERROR]"
        }
        print("\(prefix) \(message)")
    }
    
    // MARK: - Bank Management
    
    /// Set active bank
    public func setActiveBank(_ bank: Int) {
        activeBank = max(0, min(7, bank))
    }
    
    /// Get active bank
    public var currentBank: Int { activeBank }
    
    // MARK: - Config Management
    
    /// Check if a pad can be reprogrammed (not fixed in YAML config)
    public func canReprogram(bank: Int, padId: ButtonId) -> Bool {
        guard let yaml = yamlConfig else { return true }
        return !yaml.isFixed(bank: bank, x: padId.x, y: padId.y)
    }
    
    /// Update stored config for current bank (respects fixed pads)
    public func updateConfig(padId: ButtonId, behavior: PadBehavior) {
        guard canReprogram(bank: activeBank, padId: padId) else {
            print("[Config] Cannot reprogram fixed pad \(padId) in bank \(activeBank)")
            return
        }
        if bankConfigs[activeBank] == nil {
            bankConfigs[activeBank] = [:]
        }
        bankConfigs[activeBank]?[padId] = behavior
    }
    
    /// Update stored config for specific bank (respects fixed pads)
    public func updateConfig(bank: Int, padId: ButtonId, behavior: PadBehavior) {
        guard canReprogram(bank: bank, padId: padId) else {
            print("[Config] Cannot reprogram fixed pad \(padId) in bank \(bank)")
            return
        }
        if bankConfigs[bank] == nil {
            bankConfigs[bank] = [:]
        }
        bankConfigs[bank]?[padId] = behavior
    }
    
    /// Remove a config from current bank
    public func removeConfig(padId: ButtonId) {
        bankConfigs[activeBank]?[padId] = nil
    }
    
    /// Load configs from disk
    public func loadConfig() {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            print("[Config] No saved config at \(configPath.path)")
            return
        }
        
        do {
            let data = try Data(contentsOf: configPath)
            let decoder = JSONDecoder()
            
            // Try v2 format first
            if let configFile = try? decoder.decode(LaunchpadConfigFile.self, from: data) {
                bankConfigs = configFile.toBankConfigs()
                let totalPads = bankConfigs.values.reduce(0) { $0 + $1.count }
                print("[Config] Loaded \(totalPads) pad configs across \(bankConfigs.count) banks (v\(configFile.version))")
                return
            }
            
            // Fall back to v1 format (flat dict, assign to bank 0)
            let legacyDict = try decoder.decode([String: PadBehavior].self, from: data)
            var bank0: [ButtonId: PadBehavior] = [:]
            for (key, behavior) in legacyDict {
                let parts = key.split(separator: ",")
                if parts.count == 2,
                   let x = Int(parts[0]),
                   let y = Int(parts[1]) {
                    bank0[ButtonId(x: x, y: y)] = behavior
                }
            }
            bankConfigs[0] = bank0
            print("[Config] Migrated \(bank0.count) pad configs from v1 format to bank 0")
            
            // Auto-save in v2 format
            executeSaveConfig()
            
        } catch {
            print("[Config] Load failed: \(error)")
        }
    }
    
    /// Get stored config for a pad in current bank (includes YAML fixed pads)
    public func getConfig(padId: ButtonId) -> PadBehavior? {
        // Check YAML fixed pads first
        if let yaml = yamlConfig, yaml.isFixed(bank: activeBank, x: padId.x, y: padId.y) {
            if let pad = yaml.bank(activeBank)?.pads.first(where: { $0.x == padId.x && $0.y == padId.y }) {
                return yaml.toBehavior(pad: pad)
            }
        }
        return bankConfigs[activeBank]?[padId]
    }
    
    /// Get stored config for a pad in specific bank (includes YAML fixed pads)
    public func getConfig(bank: Int, padId: ButtonId) -> PadBehavior? {
        // Check YAML fixed pads first
        if let yaml = yamlConfig, yaml.isFixed(bank: bank, x: padId.x, y: padId.y) {
            if let pad = yaml.bank(bank)?.pads.first(where: { $0.x == padId.x && $0.y == padId.y }) {
                return yaml.toBehavior(pad: pad)
            }
        }
        return bankConfigs[bank]?[padId]
    }
    
    /// Get all stored configs for current bank (includes YAML fixed pads)
    public var allConfigs: [ButtonId: PadBehavior] {
        var result = bankConfigs[activeBank] ?? [:]
        // Merge YAML fixed pads
        if let yaml = yamlConfig {
            for (padId, behavior) in yaml.bankBehaviors(activeBank) {
                result[padId] = behavior
            }
        }
        return result
    }
    
    /// Get all stored configs for specific bank (includes YAML fixed pads)
    public func allConfigs(bank: Int) -> [ButtonId: PadBehavior] {
        var result = bankConfigs[bank] ?? [:]
        // Merge YAML fixed pads
        if let yaml = yamlConfig {
            for (padId, behavior) in yaml.bankBehaviors(bank) {
                result[padId] = behavior
            }
        }
        return result
    }
    
    /// Get all bank configs (for testing/debugging)
    public var allBankConfigs: [Int: [ButtonId: PadBehavior]] {
        bankConfigs
    }
}

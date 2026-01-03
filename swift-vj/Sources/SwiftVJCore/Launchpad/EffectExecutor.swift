// EffectExecutor.swift - Imperative shell for LaunchpadEffect
// Phase 5: MIDI Controller
//
// Executes effects returned by the pure FSM

import Foundation

/// Executes LaunchpadEffect cases (imperative shell)
public final class EffectExecutor {
    
    // MARK: - Dependencies
    
    private let midi: MIDIManager
    private let oscSender: ((OscCommand) -> Void)?
    private let configPath: URL
    
    // MARK: - State
    
    private var savedConfigs: [ButtonId: PadBehavior] = [:]
    
    // MARK: - Init
    
    public init(
        midi: MIDIManager,
        oscSender: ((OscCommand) -> Void)? = nil,
        configPath: URL? = nil
    ) {
        self.midi = midi
        self.oscSender = oscSender
        self.configPath = configPath ?? Self.defaultConfigPath
    }
    
    static var defaultConfigPath: URL {
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
        if let sender = oscSender {
            sender(command)
            print("[OSC] → \(command.address) \(command.args)")
        } else {
            print("[OSC] (no sender) \(command.address) \(command.args)")
        }
    }
    
    private func executeLed(padId: ButtonId, color: Int, blink: Bool) {
        midi.setLed(padId: padId, color: color)
        // TODO: Handle blink mode (requires SysEx for Launchpad)
        if blink {
            print("[LED] Blink not yet implemented for \(padId)")
        }
    }
    
    private func executeSaveConfig() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            
            // Convert to serializable format (keyed by "x,y" string)
            var configDict: [String: PadBehavior] = [:]
            for (padId, behavior) in savedConfigs {
                let key = "\(padId.x),\(padId.y)"
                configDict[key] = behavior
            }
            
            let data = try encoder.encode(configDict)
            
            // Ensure directory exists
            try FileManager.default.createDirectory(
                at: configPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            try data.write(to: configPath)
            print("[Config] Saved \(savedConfigs.count) pad configs to \(configPath.path)")
            
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
    
    // MARK: - Config Management
    
    /// Update stored config (called when FSM saves)
    public func updateConfig(padId: ButtonId, behavior: PadBehavior) {
        savedConfigs[padId] = behavior
    }
    
    /// Remove a config
    public func removeConfig(padId: ButtonId) {
        savedConfigs.removeValue(forKey: padId)
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
            let configDict = try decoder.decode([String: PadBehavior].self, from: data)
            
            savedConfigs.removeAll()
            for (key, behavior) in configDict {
                let parts = key.split(separator: ",")
                if parts.count == 2,
                   let x = Int(parts[0]),
                   let y = Int(parts[1]) {
                    let padId = ButtonId(x: x, y: y)
                    savedConfigs[padId] = behavior
                }
            }
            
            print("[Config] Loaded \(savedConfigs.count) pad configs")
            
        } catch {
            print("[Config] Load failed: \(error)")
        }
    }
    
    /// Get stored config for a pad
    public func getConfig(padId: ButtonId) -> PadBehavior? {
        savedConfigs[padId]
    }
    
    /// Get all stored configs
    public var allConfigs: [ButtonId: PadBehavior] {
        savedConfigs
    }
}

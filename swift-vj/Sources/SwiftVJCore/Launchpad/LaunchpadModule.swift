// LaunchpadModule.swift - Top-level Launchpad controller
// Phase 5: MIDI Controller
//
// Wires: MIDIManager → FSM → EffectExecutor

import Foundation

/// Status of the Launchpad module
public struct LaunchpadStatus: Sendable {
    public let isConnected: Bool
    public let deviceName: String?
    public let isLearnMode: Bool
    public let configuredPadCount: Int
}

/// Launchpad controller module
public final class LaunchpadModule: @unchecked Sendable {
    
    // MARK: - Components
    
    private let midi: MIDIManager
    private let executor: EffectExecutor
    private var state: ControllerState
    
    // MARK: - State
    
    private var isRunning = false
    private let lock = NSLock()
    
    // MARK: - Init
    
    public init(
        midi: MIDIManager? = nil,
        oscSender: ((OscCommand) -> Void)? = nil,
        configPath: URL? = nil
    ) {
        self.midi = midi ?? MIDIManager()
        self.executor = EffectExecutor(
            midi: self.midi,
            oscSender: oscSender,
            configPath: configPath
        )
        self.state = ControllerState()
    }
    
    // MARK: - Lifecycle
    
    /// Start the Launchpad module
    public func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard !isRunning else { return true }
        
        // Load saved config
        executor.loadConfig()
        
        // Apply saved configs to state
        for (padId, behavior) in executor.allConfigs {
            state.pads[padId] = behavior
            state.padRuntime[padId] = PadRuntimeState(currentColor: behavior.idleColor)
        }
        
        // Connect to Launchpad
        let connected = midi.connectToLaunchpad { [weak self] message in
            self?.handleMIDIMessage(message)
        }
        
        if connected {
            isRunning = true
            refreshLeds()
            print("[Launchpad] Started - connected to \(midi.connectedDeviceName ?? "unknown")")
        } else {
            print("[Launchpad] Started in offline mode (no device)")
            isRunning = true
        }
        
        return connected
    }
    
    /// Stop the Launchpad module
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        guard isRunning else { return }
        
        midi.clearAllLeds()
        midi.disconnect()
        isRunning = false
        print("[Launchpad] Stopped")
    }
    
    /// Get current status
    public func getStatus() -> LaunchpadStatus {
        lock.lock()
        defer { lock.unlock() }
        
        return LaunchpadStatus(
            isConnected: midi.isConnected,
            deviceName: midi.connectedDeviceName,
            isLearnMode: state.learnState.phase != .idle,
            configuredPadCount: state.pads.count
        )
    }
    
    // MARK: - MIDI Handling
    
    private func handleMIDIMessage(_ message: MIDIMessage) {
        guard let padId = message.buttonId else { return }
        
        lock.lock()
        
        let result: FSMResult
        if message.isPress {
            result = handlePadPress(state, padId: padId)
        } else if message.isRelease {
            result = handlePadRelease(state, padId: padId)
        } else {
            lock.unlock()
            return
        }
        
        // Update state
        state = result.state
        
        // Update executor configs if save happened
        let needsSave = result.effects.contains { effect in
            if case .saveConfig = effect { return true }
            return false
        }
        if needsSave {
            for (padId, behavior) in state.pads {
                executor.updateConfig(padId: padId, behavior: behavior)
            }
        }
        
        lock.unlock()
        
        // Execute effects outside lock
        executor.executeAll(result.effects)
    }
    
    // MARK: - Learn Mode
    
    /// Enter learn mode
    public func startLearnMode() {
        lock.lock()
        let result = enterLearnMode(state)
        state = result.state
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    /// Exit learn mode
    public func stopLearnMode() {
        lock.lock()
        let result = exitLearnMode(state)
        state = result.state
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    /// Handle incoming OSC event for recording
    public func receiveOscEvent(_ event: OscEvent) {
        lock.lock()
        let result = handleOscEvent(state, event: event)
        state = result.state
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    // MARK: - Manual Pad Config
    
    /// Manually configure a pad
    public func configurePad(_ padId: ButtonId, behavior: PadBehavior) {
        lock.lock()
        let result = addPadBehavior(state, behavior: behavior)
        state = result.state
        executor.updateConfig(padId: padId, behavior: behavior)
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    /// Clear a pad's configuration
    public func clearPad(_ padId: ButtonId) {
        lock.lock()
        let result = removePad(state, padId: padId)
        state = result.state
        executor.removeConfig(padId: padId)
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    // MARK: - LED Control
    
    private func refreshLeds() {
        midi.clearAllLeds()
        let effects = refreshAllLeds(state)
        executor.executeAll(effects)
    }
    
    // MARK: - Direct LED Access
    
    /// Set LED directly (bypasses config)
    public func setLed(_ padId: ButtonId, color: Int) {
        midi.setLed(padId: padId, color: color)
    }
    
    /// Set multiple LEDs
    public func setLeds(_ updates: [(ButtonId, Int)]) {
        for (padId, color) in updates {
            midi.setLed(padId: padId, color: color)
        }
    }
}

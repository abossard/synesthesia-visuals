// LaunchpadModule.swift - Top-level Launchpad controller
// Phase 5: MIDI Controller
//
// Wires: MIDIManager → FSM → EffectExecutor
// Auto-connects to real hardware - disabled when no device connected
// NO MOCKING - requires real Launchpad hardware

import Foundation

/// Status of the Launchpad module
public struct LaunchpadStatus: Sendable {
    public let isEnabled: Bool         // True only when real device connected
    public let isConnected: Bool       // Alias for isEnabled
    public let deviceName: String?
    public let isLearnMode: Bool
    public let configuredPadCount: Int
    public let currentBpm: Float
}

/// Launchpad controller module - requires real hardware
/// Auto-enables when Launchpad connected, auto-disables when disconnected
public final class LaunchpadModule: @unchecked Sendable {
    
    // MARK: - Components
    
    private let midi: MIDIManager
    private let executor: EffectExecutor
    private var state: ControllerState
    
    /// Public access to effect executor (for YAML config access)
    public var effectExecutor: EffectExecutor { executor }
    
    // MARK: - State
    
    /// Module is enabled only when real device is connected
    private(set) var isEnabled = false
    private let lock = NSLock()
    
    /// Connection state change callback
    public var onConnectionChange: ((Bool, String?) -> Void)?
    
    /// State change callback for UI observability
    public var onStateChange: ((ControllerState) -> Void)?
    
    // BPM tracking (throttled updates)
    private var currentBpm: Float = 120.0
    private var lastBpmUpdate: Date = .distantPast
    private let bpmUpdateInterval: TimeInterval = 4.0  // Max every 4 seconds
    
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
        print("[Launchpad] Module initialized - waiting for device")
    }
    
    // MARK: - Lifecycle
    
    /// Start the Launchpad module - enables auto-reconnect, connects if device available
    /// Returns true if device was immediately connected
    @discardableResult
    public func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // Load saved config (ready for when device connects)
        executor.loadConfig()
        
        // Apply saved configs to state
        for (padId, behavior) in executor.allConfigs {
            state.pads[padId] = behavior
            state.padRuntime[padId] = PadRuntimeState(currentColor: behavior.idleColor)
        }
        
        // Enable auto-reconnect - will connect if device present, or wait for it
        midi.enableAutoReconnect(
            messageCallback: { [weak self] message in
                self?.handleMIDIMessage(message)
            },
            connectionCallback: { [weak self] connected, deviceName in
                self?.handleConnectionChange(connected: connected, deviceName: deviceName)
            }
        )
        
        return midi.isConnected
    }
    
    /// Stop the Launchpad module - disconnect and disable auto-reconnect
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        
        midi.stopMidiClock()
        midi.disableAutoReconnect()
        if isEnabled {
            midi.clearAllLeds()
        }
        midi.disconnect()
        isEnabled = false
        print("[Launchpad] Stopped")
    }
    
    /// Get current status
    public func getStatus() -> LaunchpadStatus {
        lock.lock()
        defer { lock.unlock() }
        
        return LaunchpadStatus(
            isEnabled: isEnabled,
            isConnected: midi.isConnected,
            deviceName: midi.connectedDeviceName,
            isLearnMode: state.learnState.phase != .idle,
            configuredPadCount: state.pads.count,
            currentBpm: currentBpm
        )
    }
    
    // MARK: - Connection Handling
    
    private func handleConnectionChange(connected: Bool, deviceName: String?) {
        lock.lock()
        
        if connected {
            isEnabled = true
            print("[Launchpad] ✓ Enabled - connected to \(deviceName ?? "device")")
            lock.unlock()
            
            // Force Programmer Mode immediately
            forceProgrammerMode()
            
            // Start MIDI clock for flash sync (default 120 BPM until OSC updates it)
            midi.startMidiClock(bpm: currentBpm)
            
            // Refresh LEDs now that we're connected
            refreshLeds()
            
            // Notify UI of initial state
            let currentState = state
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(currentState)
            }
        } else {
            isEnabled = false
            midi.stopMidiClock()
            print("[Launchpad] ○ Disabled - device disconnected")
            lock.unlock()
        }
        
        // Notify callback on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChange?(connected, deviceName)
        }
    }
    
    // MARK: - MIDI Handling
    
    private func handleMIDIMessage(_ message: MIDIMessage) {
        guard isEnabled else { return }  // Only process when enabled
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
        
        // Notify UI
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(currentState)
        }
        
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
        
        // Update LED display to reflect new state
        updateDisplay()
    }
    
    // MARK: - Learn Mode
    
    /// Enter learn mode (requires device connected)
    public func startLearnMode() {
        guard isEnabled else {
            print("[Launchpad] Cannot enter learn mode - no device connected")
            return
        }
        
        lock.lock()
        let result = enterLearnMode(state)
        state = result.state
        
        // Notify UI
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(currentState)
        }
        
        lock.unlock()
        executor.executeAll(result.effects)
        
        // Update LED display to show learn mode
        updateDisplay()
    }
    
    /// Exit learn mode
    public func stopLearnMode() {
        lock.lock()
        let result = exitLearnMode(state)
        state = result.state
        
        // Notify UI
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(currentState)
        }
        
        lock.unlock()
        executor.executeAll(result.effects)
        
        // Update LED display to show normal mode
        updateDisplay()
    }
    
    /// Handle incoming OSC event for live capture during config phase
    public func receiveOscEvent(_ event: OscEvent) {
        guard isEnabled else { return }
        
        // Handle BPM updates (throttled, for status display only)
        if event.address == "/audio/bpm/bpm" {
            if case .float(let bpm) = event.args.first, bpm > 0 {
                updateBpm(bpm)
            }
            return  // Don't forward to FSM
        }
        
        // Ignore beat pulses - native Launchpad pulse handles timing
        if event.address == "/audio/beat/onbeat" {
            return  // Don't forward to FSM
        }
        
        lock.lock()
        
        // During config phase, capture OSC live
        if state.learnState.phase == .config {
            let result = captureOscEvent(state, event: event)
            let capturedCountBefore = state.learnState.capturedOsc.count
            let capturedCountAfter = result.state.learnState.capturedOsc.count
            state = result.state
            
            // Notify UI
            let currentState = state
            DispatchQueue.main.async { [weak self] in
                self?.onStateChange?(currentState)
            }
            
            lock.unlock()
            executor.executeAll(result.effects)
            
            // Update LED display if new OSC was captured
            if capturedCountAfter > capturedCountBefore {
                updateDisplay()
            }
        } else {
            lock.unlock()
        }
    }
    
    // MARK: - Manual Pad Config
    
    /// Manually configure a pad (requires device connected for LED update)
    public func configurePad(_ padId: ButtonId, behavior: PadBehavior) {
        lock.lock()
        let result = addPadBehavior(state, behavior: behavior)
        state = result.state
        executor.updateConfig(padId: padId, behavior: behavior)
        
        // Notify UI
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(currentState)
        }
        
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    /// Clear a pad's configuration
    public func clearPad(_ padId: ButtonId) {
        lock.lock()
        let result = removePad(state, padId: padId)
        state = result.state
        executor.removeConfig(padId: padId)
        
        // Notify UI
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(currentState)
        }
        
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    // MARK: - LED Control
    
    private func refreshLeds() {
        guard isEnabled else { return }
        
        // Use display renderer to get all LED effects for current state
        let effects = renderState(state)
        executor.executeAll(effects)
    }
    
    /// Full display refresh - renders all LEDs based on current FSM state
    /// Called after state transitions to update Launchpad display
    private func updateDisplay() {
        guard isEnabled else { return }
        
        let effects = renderState(state)
        executor.executeAll(effects)
    }
    
    // MARK: - Direct LED Access
    
    /// Set LED directly (requires device connected)
    public func setLed(_ padId: ButtonId, color: Int) {
        guard isEnabled else { return }
        midi.setLed(padId: padId, color: color)
    }
    
    /// Set multiple LEDs (requires device connected)
    public func setLeds(_ updates: [(ButtonId, Int)]) {
        guard isEnabled else {
            print("[Launchpad] setLeds ignored - module disabled")
            return
        }
        print("[Launchpad] setLeds: updating \(updates.count) pads")
        for (padId, color) in updates {
            midi.setLed(padId: padId, color: color)
        }
    }
    
    // MARK: - Device Info
    
    /// Check if any Launchpad is currently available (even if not connected yet)
    public var isLaunchpadAvailable: Bool {
        midi.isLaunchpadAvailable
    }
    
    /// Force Programmer Mode (send SysEx sequence)
    public func forceProgrammerMode() {
        guard isEnabled else { return }
        midi.sendDAWModeSysEx()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.midi.sendProgrammerModeSysEx()
        }
    }
    
    // MARK: - BPM Tracking
    
    /// Update BPM (throttled to max every 4 seconds)
    public func updateBpm(_ bpm: Float) {
        guard bpm > 20 && bpm < 300 else { return }  // Sanity check
        
        // Throttle updates
        let now = Date()
        guard now.timeIntervalSince(lastBpmUpdate) >= bpmUpdateInterval else { return }
        
        let bpmChanged = abs(currentBpm - bpm) > 1.0
        if bpmChanged {
            currentBpm = bpm
            lastBpmUpdate = now
            
            // Update MIDI clock tempo for flash sync
            midi.updateMidiClockBpm(bpm)
            print("[Launchpad] BPM updated to \(bpm)")
        }
    }
    
    // MARK: - Native LED Pulse/Flash
    
    /// Set LED with native Launchpad pulsing (hardware-driven, no timer needed)
    public func setLedPulsing(_ padId: ButtonId, color: Int) {
        guard isEnabled else { return }
        midi.setLed(padId: padId, color: color, mode: .pulse)
    }
    
    /// Set LED with native Launchpad flashing (hardware-driven, alternates with off)
    public func setLedFlashing(_ padId: ButtonId, color: Int) {
        guard isEnabled else { return }
        midi.setLed(padId: padId, color: color, mode: .flash)
    }
    
    /// Set LED to solid (static, no animation)
    public func setLedSolid(_ padId: ButtonId, color: Int) {
        guard isEnabled else { return }
        midi.setLed(padId: padId, color: color, mode: .solid)
    }
}

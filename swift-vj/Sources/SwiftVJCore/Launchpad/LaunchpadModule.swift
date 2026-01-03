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
}

/// Launchpad controller module - requires real hardware
/// Auto-enables when Launchpad connected, auto-disables when disconnected
public final class LaunchpadModule: @unchecked Sendable {
    
    // MARK: - Components
    
    private let midi: MIDIManager
    private let executor: EffectExecutor
    private var state: ControllerState
    
    // MARK: - State
    
    /// Module is enabled only when real device is connected
    private(set) var isEnabled = false
    private let lock = NSLock()
    
    /// Connection state change callback
    public var onConnectionChange: ((Bool, String?) -> Void)?
    
    // Beat-sync blinking
    private var blinkTimer: Timer?
    private var blinkEnabled = true  // User preference
    private var currentBpm: Float = 120.0
    
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
        
        stopBlinkTimer()
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
            configuredPadCount: state.pads.count
        )
    }
    
    // MARK: - Connection Handling
    
    private func handleConnectionChange(connected: Bool, deviceName: String?) {
        lock.lock()
        
        if connected {
            isEnabled = true
            print("[Launchpad] ✓ Enabled - connected to \(deviceName ?? "device")")
            lock.unlock()
            
            // Refresh LEDs now that we're connected
            refreshLeds()
            
            // Start beat-sync blink timer
            startBlinkTimer()
        } else {
            isEnabled = false
            stopBlinkTimer()
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
    
    /// Enter learn mode (requires device connected)
    public func startLearnMode() {
        guard isEnabled else {
            print("[Launchpad] Cannot enter learn mode - no device connected")
            return
        }
        
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
        guard isEnabled else { return }
        
        // Handle BPM updates for beat-sync blinking
        if event.address == "/audio/bpm/bpm" || event.address == "/syn/bpm" {
            if case .float(let bpm) = event.args.first, bpm > 0 {
                updateBpm(bpm)
            }
        }
        
        // Handle beat pulse for immediate blink toggle
        if event.address == "/audio/beat/onbeat" {
            if case .float(let val) = event.args.first, val > 0.5 {
                handleBeatPulse()
            }
        }
        
        lock.lock()
        let result = handleOscEvent(state, event: event)
        state = result.state
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    // MARK: - Manual Pad Config
    
    /// Manually configure a pad (requires device connected for LED update)
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
        guard isEnabled else { return }
        
        midi.clearAllLeds()
        let effects = refreshAllLeds(state)
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
        guard isEnabled else { return }
        for (padId, color) in updates {
            midi.setLed(padId: padId, color: color)
        }
    }
    
    // MARK: - Device Info
    
    /// Check if any Launchpad is currently available (even if not connected yet)
    public var isLaunchpadAvailable: Bool {
        midi.isLaunchpadAvailable
    }
    
    // MARK: - Beat-Sync Blinking
    
    /// Enable or disable beat-sync LED blinking
    public func setBlinkEnabled(_ enabled: Bool) {
        blinkEnabled = enabled
        if !enabled {
            // Reset all blinking pads to steady state
            refreshLeds()
        }
    }
    
    private func startBlinkTimer() {
        stopBlinkTimer()
        
        // Default to 120 BPM = 500ms per beat = 250ms per half-beat (blink rate)
        let interval = 60.0 / Double(currentBpm) / 2.0
        
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.handleBlinkTick()
        }
        
        print("[Launchpad] Beat-sync blink timer started at \(currentBpm) BPM")
    }
    
    private func stopBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }
    
    private func updateBpm(_ bpm: Float) {
        guard bpm > 20 && bpm < 300 else { return }  // Sanity check
        
        let bpmChanged = abs(currentBpm - bpm) > 1.0
        currentBpm = bpm
        
        // Restart timer with new BPM if significantly changed
        if bpmChanged && blinkTimer != nil {
            startBlinkTimer()
        }
    }
    
    private func handleBeatPulse() {
        // Immediate blink toggle on beat (more responsive than timer)
        handleBlinkTick()
    }
    
    private func handleBlinkTick() {
        guard isEnabled && blinkEnabled else { return }
        
        lock.lock()
        
        // Toggle blink state
        state = toggleBlink(state)
        let blinkOn = state.blinkOn
        
        // Update LEDs for pads that should blink (active selectors)
        for (padId, behavior) in state.pads {
            guard behavior.mode == .selector else { continue }
            
            let runtime = state.padRuntime[padId] ?? PadRuntimeState()
            guard runtime.isActive else { continue }
            
            // Alternate between active and dimmed color
            let color = blinkOn ? behavior.activeColor : behavior.idleColor
            midi.setLed(padId: padId, color: color)
        }
        
        lock.unlock()
    }
}

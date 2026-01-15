// LaunchpadModule.swift - Top-level Launchpad controller
// Phase 5: MIDI Controller
// Unidirectional Data Flow: dispatches actions instead of callbacks
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
    
    public init(
        isEnabled: Bool,
        isConnected: Bool,
        deviceName: String?,
        isLearnMode: Bool,
        configuredPadCount: Int,
        currentBpm: Float
    ) {
        self.isEnabled = isEnabled
        self.isConnected = isConnected
        self.deviceName = deviceName
        self.isLearnMode = isLearnMode
        self.configuredPadCount = configuredPadCount
        self.currentBpm = currentBpm
    }
}

/// Launchpad controller module - requires real hardware
/// Auto-enables when Launchpad connected, auto-disables when disconnected
public final class LaunchpadModule: @unchecked Sendable {
    
    // MARK: - Components
    
    private let midi: MIDIManager
    private let executor: EffectExecutor
    private var state: ControllerState
    private var rolesByBank: [Int: BankRole] = [:]
    
    // MARK: - State

    /// Module is enabled only when real device is connected
    private(set) var isEnabled = false
    private let lock = NSLock()

    // MARK: - Action Dispatcher (Unidirectional Data Flow)

    /// Action dispatcher - set this to integrate with Store
    public var dispatch: ((AppAction) -> Void)?
    
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

        // Roles from YAML config
        if let yaml = executor.yamlConfig {
            for bank in 0..<8 { rolesByBank[bank] = yaml.bankRole(bank) }
            // Prefill state with YAML fixed pads
            for bank in 0..<8 {
                let behaviors = yaml.bankBehaviors(bank)
                if !behaviors.isEmpty {
                    state.bankPads[bank] = behaviors
                    state.bankPadRuntime[bank] = behaviors.mapValues { PadRuntimeState(currentColor: $0.idleColor) }
                }
            }
        }
        
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
            configuredPadCount: state.pads.count,
            currentBpm: currentBpm
        )
    }

    /// Get full controller state (for views that need detailed pad info)
    public func getFullState() -> ControllerState {
        lock.lock()
        defer { lock.unlock() }
        return state
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

            // Refresh LEDs now that we're connected
            refreshLeds()

            // Refresh dynamic banks (scenes/params)
            refreshDynamicBanks()

            // Start beat-sync blink timer
            startBlinkTimer()

            // Dispatch connection and initial state
            let currentState = state
            DispatchQueue.main.async { [weak self] in
                self?.dispatch?(.launchpad(.connected(deviceName ?? "Launchpad")))
                self?.dispatch?(.launchpad(.stateUpdated(ControllerStateSnapshot(from: currentState))))
            }
        } else {
            isEnabled = false
            stopBlinkTimer()
            print("[Launchpad] ○ Disabled - device disconnected")
            lock.unlock()

            // Dispatch disconnection
            DispatchQueue.main.async { [weak self] in
                self?.dispatch?(.launchpad(.disconnected))
            }
        }
    }
    
    // MARK: - MIDI Handling
    
    private func handleMIDIMessage(_ message: MIDIMessage) {
        guard isEnabled else { return }  // Only process when enabled
        guard let padId = message.buttonId else { return }
        
        lock.lock()
        
        let oldBank = state.activeBank
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

        // Dispatch state update
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.dispatch?(.launchpad(.stateUpdated(ControllerStateSnapshot(from: currentState))))
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

        // If bank changed and role is dynamic, refresh that bank
        if oldBank != state.activeBank, let role = rolesByBank[state.activeBank], role == .scenes || role == .scenes2 || role == .params {
            refreshDynamicBanks(for: [state.activeBank])
        }
    }

    // MARK: - Dynamic Banks

    private func refreshDynamicBanks(for banks: [Int]? = nil) {
        let banksToRefresh = banks ?? Array(rolesByBank.keys)
        Task {
            // Fetch dynamic sources
            let scenes = await DynamicGroupStore.shared.items(for: "$synesthesia/scenes")
            let controls = await DynamicControlStore.shared.items()

            // Build behaviors per bank
            var updates: [Int: [ButtonId: PadBehavior]] = [:]
            var pageCounts: [Int: Int] = [:]

            for bank in banksToRefresh {
                guard let role = rolesByBank[bank] else { continue }
                switch role {
                case .scenes:
                    updates[bank] = generateSceneBehaviors(scenes: scenes, offset: 0)
                case .scenes2:
                    updates[bank] = generateSceneBehaviors(scenes: scenes, offset: 8)
                case .params:
                    let pageSize = 64
                    let totalPages = max(1, Int(ceil(Double(controls.count) / Double(pageSize))))
                    pageCounts[bank] = totalPages
                    let currentPage: Int = {
                        lock.lock(); defer { lock.unlock() }
                        return min(state.bankCurrentPage[bank] ?? 0, totalPages - 1)
                    }()
                    let start = currentPage * pageSize
                    let end = min(start + pageSize, controls.count)
                    let pageControls = Array(controls[start..<end])
                    updates[bank] = generateParamBehaviors(addresses: pageControls)
                default:
                    break
                }
            }

            lock.lock()
            for (bank, pads) in updates {
                state.bankPads[bank] = pads
                state.bankPadRuntime[bank] = pads.mapValues { PadRuntimeState(currentColor: $0.idleColor) }
            }
            for (bank, pages) in pageCounts {
                state.bankPageCount[bank] = pages
                if (state.bankCurrentPage[bank] ?? 0) >= pages { state.bankCurrentPage[bank] = 0 }
            }
            lock.unlock()

            refreshLeds()
            let refreshed = updates.keys.sorted()
            if !refreshed.isEmpty {
                print("[Dynamic] Refreshed banks \(refreshed) scenes=\(scenes.count) controls=\(controls.count)")
            }
        }
    }

    private func generateSceneBehaviors(scenes: [String], offset: Int) -> [ButtonId: PadBehavior] {
        var result: [ButtonId: PadBehavior] = [:]
        let palette = LaunchpadColor.allCases.map { $0.rawValue }
        for i in 0..<8 {
            let idx = offset + i
            guard idx < scenes.count else { continue }
            let padId = ButtonId(x: i, y: 7)
            let sceneName = scenes[idx]
            let color = palette[idx % palette.count]
            result[padId] = PadBehavior(
                padId: padId,
                mode: .selector,
                group: .scenes,
                idleColor: color,
                activeColor: color,
                label: sceneName,
                oscOn: nil,
                oscOff: nil,
                oscAction: OscCommand(address: "/scenes/select", args: [.string(sceneName)])
            )
        }
        return result
    }

    private func generateParamBehaviors(addresses: [String]) -> [ButtonId: PadBehavior] {
        var result: [ButtonId: PadBehavior] = [:]
        for (idx, address) in addresses.enumerated() {
            let x = idx % 8
            let y = idx / 8
            let padId = ButtonId(x: x, y: y)
            let label = address.split(separator: "/").last.map(String.init) ?? address
            let args = (awaitDynamicControlValue(address: address)) ?? []
            let behavior = PadBehavior(
                padId: padId,
                mode: .push,
                group: .custom,
                idleColor: LP.blueDim,
                activeColor: LP.blue,
                label: label,
                oscOn: nil,
                oscOff: nil,
                oscAction: OscCommand(address: address, args: args)
            )
            result[padId] = behavior
        }
        return result
    }

    private func awaitDynamicControlValue(address: String) -> [OscArg]? {
        var value: [OscArg]? = nil
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            value = await DynamicControlStore.shared.value(address: address)
            semaphore.signal()
        }
        semaphore.wait()
        return value
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
            self?.dispatch?(.launchpad(.stateUpdated(ControllerStateSnapshot(from: currentState))))
        }
        
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    /// Exit learn mode
    public func stopLearnMode() {
        lock.lock()
        let result = exitLearnMode(state)
        state = result.state
        
        // Notify UI
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.dispatch?(.launchpad(.stateUpdated(ControllerStateSnapshot(from: currentState))))
        }
        
        lock.unlock()
        executor.executeAll(result.effects)
    }
    
    /// Handle incoming OSC event for recording
    public func receiveOscEvent(_ event: OscEvent) {
        guard isEnabled else { return }
        
        // Handle BPM updates for beat-sync blinking (Synesthesia control messages only)
        if event.address == "/syn/bpm" || event.address == "/controls/meta/bpm" {
            if case .float(let bpm) = event.args.first, bpm > 0 {
                updateBpm(bpm)
            }
        }
        
        // Handle beat pulse for immediate blink toggle (Synesthesia control messages only)
        if event.address == "/syn/beat" || event.address == "/controls/meta/onbeat" {
            if case .float(let val) = event.args.first, val > 0.5 {
                handleBeatPulse()
            }
        }
        
        // Capture dynamic scenes/controls
        if event.address.hasPrefix("/controls/") {
            Task {
                let isNew = await DynamicControlStore.shared.update(address: event.address, args: event.args)
                if isNew { print("[OSC] +control \(event.address)") }
            }
            let paramsBanks = rolesByBank.filter { $0.value == .params }.map { $0.key }
            if !paramsBanks.isEmpty { refreshDynamicBanks(for: paramsBanks) }
        }
        if event.address.hasPrefix("/scenes/") {
            let name = event.address.components(separatedBy: "/").last ?? ""
            if !name.isEmpty {
                Task {
                    var items = await DynamicGroupStore.shared.items(for: "$synesthesia/scenes")
                    if !items.contains(name) { items.append(name) }
                    await DynamicGroupStore.shared.update(source: "$synesthesia/scenes", items: items)
                    let sceneBanks = rolesByBank.filter { $0.value == .scenes || $0.value == .scenes2 }.map { $0.key }
                    if !sceneBanks.isEmpty { refreshDynamicBanks(for: sceneBanks) }
                }
            }
        }

        lock.lock()
        let result = handleOscEvent(state, event: event)
        state = result.state
        
        // Notify UI
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.dispatch?(.launchpad(.stateUpdated(ControllerStateSnapshot(from: currentState))))
        }
        
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
        
        // Notify UI
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.dispatch?(.launchpad(.stateUpdated(ControllerStateSnapshot(from: currentState))))
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
            self?.dispatch?(.launchpad(.stateUpdated(ControllerStateSnapshot(from: currentState))))
        }
        
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
    
    /// YAML configuration for bank names/colors (if loaded)
    public var yamlConfig: LaunchpadYAMLConfig? {
        executor.yamlConfig
    }
    
    /// Force Programmer Mode (send SysEx sequence)
    public func forceProgrammerMode() {
        guard isEnabled else { return }
        midi.sendDAWModeSysEx()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.midi.sendProgrammerModeSysEx()
        }
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
    
    public func updateBpm(_ bpm: Float) {
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
        
        // Notify UI (for blink visualization)
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.dispatch?(.launchpad(.stateUpdated(ControllerStateSnapshot(from: currentState))))
        }
        
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

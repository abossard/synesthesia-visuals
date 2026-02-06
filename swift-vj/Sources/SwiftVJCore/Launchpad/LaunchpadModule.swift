// LaunchpadModule.swift - Top-level Launchpad controller
// Phase 5: MIDI Controller
// Unidirectional Data Flow: dispatches actions instead of callbacks
//
// Wires: MIDIManager → FSM → EffectExecutor
// Auto-connects to real hardware - disabled when no device connected
// NO MOCKING - requires real Launchpad hardware

import Foundation

/// Status of the Launchpad module
public struct LaunchpadStatus: Sendable, Equatable {
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
    private var dynamicRefreshEpochByBank: [Int: Int] = [:]
    private let stateQueue = DispatchQueue(label: "swiftvj.launchpad.state", qos: .userInitiated)
    private let stateQueueKey = DispatchSpecificKey<UInt8>()
    
    // MARK: - State

    /// Module is enabled only when real device is connected
    private(set) var isEnabled = false

    // MARK: - Action Dispatcher (Unidirectional Data Flow)

    /// Action dispatcher - set this to integrate with Store
    public var dispatch: ((AppAction) -> Void)?
    
    // Beat-sync blinking
    private var blinkTimer: DispatchSourceTimer?
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
        self.stateQueue.setSpecific(key: stateQueueKey, value: 1)
        print("[Launchpad] Module initialized - waiting for device")
    }
    
    // MARK: - Lifecycle
    
    /// Start the Launchpad module - enables auto-reconnect, connects if device available
    /// Returns true if device was immediately connected
    @discardableResult
    public func start() -> Bool {
        let (currentState, connected): (ControllerState, Bool) = withStateSync {
            // Load saved config (ready for when device connects)
            executor.loadConfig()

            // Roles from YAML config
            if let yaml = executor.yamlConfig {
                for bank in 0..<8 {
                    rolesByBank[bank] = yaml.bankRole(bank)
                    state.bankLayout[bank] = yaml.bankLayoutPolicy(bank)
                }
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

            // Prime runtime colors for UI twin (top row + scene buttons).
            let initialEffects = renderState(state)
            applyLedEffectsToRuntime(initialEffects, state: &state)

            // Enable auto-reconnect - will connect if device present, or wait for it
            midi.enableAutoReconnect(
                messageCallback: { [weak self] message in
                    self?.handleMIDIMessage(message)
                },
                connectionCallback: { [weak self] connected, deviceName in
                    self?.handleConnectionChange(connected: connected, deviceName: deviceName)
                }
            )

            return (state, midi.isConnected)
        }

        // Publish initial state/status so UI can act as a twin even without hardware.
        publishState(currentState, includeStatus: true)
        return connected
    }
    
    /// Stop the Launchpad module - disconnect and disable auto-reconnect
    public func stop() {
        withStateSync {
            stopBlinkTimer()
            midi.disableAutoReconnect()
            if isEnabled {
                midi.clearAllLeds()
            }
            midi.disconnect()
            isEnabled = false
            print("[Launchpad] Stopped")
        }
    }
    
    /// Get current status
    public func getStatus() -> LaunchpadStatus {
        withStateSync {
            LaunchpadStatus(
                isEnabled: isEnabled,
                isConnected: midi.isConnected,
                deviceName: midi.connectedDeviceName,
                isLearnMode: state.learnState.phase != .idle,
                configuredPadCount: state.pads.count,
                currentBpm: currentBpm
            )
        }
    }

    /// Get full controller state (for views that need detailed pad info)
    public func getFullState() -> ControllerState {
        withStateSync { state }
    }
    
    // MARK: - Connection Handling
    
    private func handleConnectionChange(connected: Bool, deviceName: String?) {
        onStateQueue { [weak self] in
            guard let self else { return }

            if connected {
                self.isEnabled = true
                print("[Launchpad] ✓ Enabled - connected to \(deviceName ?? "device")")

                // Force Programmer Mode immediately
                self.forceProgrammerMode()

                // Refresh LEDs now that we're connected
                self.refreshLeds()

                // Refresh dynamic banks (scenes/params)
                self.refreshDynamicBanks()

                // Start beat-sync blink timer
                self.startBlinkTimer()

                // Dispatch connection and initial state
                let currentState = self.state
                let statusSnapshot = self.makeStatusSnapshot(from: currentState)
                DispatchQueue.main.async { [weak self] in
                    self?.dispatch?(.launchpad(.connected(deviceName ?? "Launchpad")))
                    self?.dispatch?(.launchpad(.stateUpdated(currentState)))
                    self?.dispatch?(.launchpad(.statusUpdated(statusSnapshot)))
                }
            } else {
                self.isEnabled = false
                self.stopBlinkTimer()
                print("[Launchpad] ○ Disabled - device disconnected")

                // Dispatch disconnection
                let currentState = self.state
                let statusSnapshot = self.makeStatusSnapshot(from: currentState)
                DispatchQueue.main.async { [weak self] in
                    self?.dispatch?(.launchpad(.disconnected))
                    self?.dispatch?(.launchpad(.statusUpdated(statusSnapshot)))
                }
            }
        }
    }
    
    // MARK: - MIDI Handling
    
    private func handleMIDIMessage(_ message: MIDIMessage) {
        guard let padId = message.buttonId else { return }
        let isPress = message.isPress
        let isRelease = message.isRelease
        guard isPress || isRelease else { return }
        handlePadInput(padId: padId, isPress: isPress, allowWhenDisabled: false)
    }

    // MARK: - UI Twin Input

    /// Simulate a pad press from the UI twin (works without hardware)
    public func handleVirtualPadPress(_ padId: ButtonId) {
        handlePadInput(padId: padId, isPress: true, allowWhenDisabled: true)
    }

    /// Simulate a pad release from the UI twin (works without hardware)
    public func handleVirtualPadRelease(_ padId: ButtonId) {
        handlePadInput(padId: padId, isPress: false, allowWhenDisabled: true)
    }

    private func handlePadInput(padId: ButtonId, isPress: Bool, allowWhenDisabled: Bool) {
        onStateQueue { [weak self] in
            guard let self else { return }
            if !allowWhenDisabled && !self.isEnabled { return }  // Hardware input only when enabled

            let oldBank = self.state.activeBank
            let oldPage = self.state.currentPage
            let result: FSMResult
            if isPress {
                result = handlePadPress(self.state, padId: padId)
            } else {
                result = handlePadRelease(self.state, padId: padId)
            }

            // Update state
            self.state = result.state
            let activeBank = self.state.activeBank
            let activePage = self.state.currentPage
            if oldBank != activeBank {
                self.executor.setActiveBank(activeBank)
            }

            // Update executor configs if save happened
            let needsSave = result.effects.contains { effect in
                if case .saveConfig = effect { return true }
                return false
            }
            if needsSave {
                for (padId, behavior) in self.state.pads {
                    self.executor.updateConfig(padId: padId, behavior: behavior)
                }
            }

            // Unidirectional render: LEDs are always derived from current state.
            let effectsToExecute = self.mergedEffectsWithRender(from: result.effects)
            let currentState = self.state
            let activeRole = self.rolesByBank[activeBank]

            // Publish snapshot + execute effects
            self.publishState(currentState, includeStatus: true)
            self.executor.executeAll(effectsToExecute)

            // If bank/page changed and role is dynamic, refresh that bank
            if oldBank != activeBank,
               let role = activeRole,
               self.isDynamicRole(role) {
                self.refreshDynamicBanks(for: [activeBank])
            } else if oldPage != activePage,
                      let role = activeRole,
                      self.isDynamicRole(role) {
                self.refreshDynamicBanks(for: [activeBank])
            }
        }
    }

    private func applyLedEffectsToRuntime(_ effects: [LaunchpadEffect], state: inout ControllerState) {
        for effect in effects {
            guard case .setLed(let padId, let color, let blink) = effect else { continue }
            var runtime = state.padRuntime[padId] ?? PadRuntimeState()
            runtime.currentColor = color
            runtime.blinkEnabled = blink
            runtime.ledMode = blink ? .pulse : .static
            state.padRuntime[padId] = runtime
        }
    }

    private func mergedEffectsWithRender(from effects: [LaunchpadEffect]) -> [LaunchpadEffect] {
        let nonLedEffects = effects.filter { effect in
            if case .setLed = effect { return false }
            return true
        }
        let renderEffects = renderState(state)
        applyLedEffectsToRuntime(renderEffects, state: &state)
        return nonLedEffects + renderEffects
    }

    private func isOnStateQueue() -> Bool {
        DispatchQueue.getSpecific(key: stateQueueKey) != nil
    }

    private func onStateQueue(_ body: @escaping @Sendable () -> Void) {
        if isOnStateQueue() {
            body()
        } else {
            stateQueue.async(execute: body)
        }
    }

    private func withStateSync<T>(_ body: () -> T) -> T {
        if isOnStateQueue() {
            return body()
        }
        return stateQueue.sync(execute: body)
    }

    private func publishState(_ snapshot: ControllerState, includeStatus: Bool) {
        let statusSnapshot = includeStatus ? withStateSync { makeStatusSnapshot(from: snapshot) } : nil
        DispatchQueue.main.async { [weak self] in
            self?.dispatch?(.launchpad(.stateUpdated(snapshot)))
            guard let statusSnapshot else { return }
            self?.dispatch?(.launchpad(.statusUpdated(statusSnapshot)))
        }
    }

    private func makeStatusSnapshot(from snapshot: ControllerState) -> LaunchpadStatusSnapshot {
        LaunchpadStatusSnapshot(
            isConnected: midi.isConnected,
            deviceName: midi.connectedDeviceName,
            activeBank: snapshot.activeBank,
            padCount: snapshot.pads.count,
            isLearnMode: snapshot.learnState.phase != .idle,
            currentBpm: currentBpm
        )
    }

    private func isDynamicRole(_ role: BankRole) -> Bool {
        role == .scenes || role == .scenes2 || role == .presets || role == .params
    }

    // MARK: - Dynamic Banks

    private func refreshDynamicBanks(for banks: [Int]? = nil) {
        // Keep offline UI twin deterministic: dynamic bank materialization only
        // runs when hardware is connected/enabled.
        guard withStateSync({ isEnabled }) else { return }

        let refreshRequests: [Int: (epoch: Int, page: Int, role: BankRole)] = withStateSync {
            let banksToRefresh = banks ?? Array(rolesByBank.keys)
            var requests: [Int: (epoch: Int, page: Int, role: BankRole)] = [:]
            for bank in banksToRefresh {
                guard let role = rolesByBank[bank], isDynamicRole(role) else { continue }
                let nextEpoch = (dynamicRefreshEpochByBank[bank] ?? 0) + 1
                dynamicRefreshEpochByBank[bank] = nextEpoch
                let currentPage = state.bankCurrentPage[bank] ?? 0
                requests[bank] = (nextEpoch, currentPage, role)
            }
            return requests
        }
        guard !refreshRequests.isEmpty else { return }

        Task { [weak self] in
            guard let self else { return }
            // Fetch dynamic sources
            let scenes = await DynamicGroupStore.shared.items(for: "$synesthesia/scenes")
            let controls = await DynamicControlStore.shared.items()
            let presets = await DynamicGroupStore.shared.items(for: "$synesthesia/presets")

            // Build behaviors per bank
            var updates: [Int: [ButtonId: PadBehavior]] = [:]
            var pageCounts: [Int: Int] = [:]

            for (bank, request) in refreshRequests {
                let role = request.role

                switch role {
                case .scenes:
                    let pageSize = 64
                    let totalPages = max(1, Int(ceil(Double(scenes.count) / Double(pageSize))))
                    pageCounts[bank] = totalPages
                    let currentPage = min(request.page, totalPages - 1)
                    let dynamicPads = generateSceneBehaviors(scenes: scenes, page: currentPage)
                    updates[bank] = dynamicPads
                case .scenes2:
                    let pageSize = 64
                    let totalPages = max(1, Int(ceil(Double(scenes.count) / Double(pageSize))))
                    pageCounts[bank] = totalPages
                    let currentPage = min(request.page + 1, totalPages - 1)
                    let dynamicPads = generateSceneBehaviors(scenes: scenes, page: currentPage)
                    updates[bank] = dynamicPads
                case .presets:
                    let pageSize = 64
                    let totalPages = max(1, Int(ceil(Double(presets.count) / Double(pageSize))))
                    pageCounts[bank] = totalPages
                    let currentPage = min(request.page, totalPages - 1)
                    let dynamicPads = generatePresetBehaviors(presets: presets, page: currentPage)
                    updates[bank] = dynamicPads
                case .params:
                    let pageSize = 64
                    let totalPages = max(1, Int(ceil(Double(controls.count) / Double(pageSize))))
                    pageCounts[bank] = totalPages
                    let currentPage = min(request.page, totalPages - 1)
                    let start = currentPage * pageSize
                    let end = min(start + pageSize, controls.count)
                    let pageControls = start < end ? Array(controls[start..<end]) : []
                    let dynamicPads = await generateParamBehaviors(addresses: pageControls)
                    updates[bank] = dynamicPads
                default:
                    break
                }
            }

            let finalUpdates = updates
            let finalPageCounts = pageCounts
            self.onStateQueue {
                guard self.isEnabled else { return }
                var appliedBanks: [Int] = []
                for (bank, request) in refreshRequests {
                    guard self.dynamicRefreshEpochByBank[bank] == request.epoch else {
                        continue  // stale refresh
                    }

                    if let pages = finalPageCounts[bank] {
                        self.state.bankPageCount[bank] = pages
                        let currentPage = min(self.state.bankCurrentPage[bank] ?? 0, max(0, pages - 1))
                        self.state.bankCurrentPage[bank] = currentPage
                    }

                    let pads = finalUpdates[bank] ?? [:]
                    // Always apply, even if empty, to avoid stale pads from older refreshes.
                    self.state.bankPads[bank] = pads
                    self.state.bankPadRuntime[bank] = pads.mapValues { PadRuntimeState(currentColor: $0.idleColor) }
                    appliedBanks.append(bank)
                }

                let effectsToExecute = self.mergedEffectsWithRender(from: [])
                let currentState = self.state
                self.executor.executeAll(effectsToExecute)
                self.publishState(currentState, includeStatus: false)

                if !appliedBanks.isEmpty {
                    print("[Dynamic] Refreshed banks \(appliedBanks.sorted()) scenes=\(scenes.count) controls=\(controls.count)")
                }
            }
        }
    }

    private func generateSceneBehaviors(scenes: [String], page: Int) -> [ButtonId: PadBehavior] {
        var result: [ButtonId: PadBehavior] = [:]
        let palette = LaunchpadColor.allCases.map { $0.rawValue }
        let pageSize = 64
        let start = page * pageSize
        let end = min(start + pageSize, scenes.count)
        for idx in start..<end {
            let local = idx - start
            let x = local % 8
            let y = local / 8
            let padId = ButtonId(x: x, y: y)
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

    private func generatePresetBehaviors(presets: [String], page: Int) -> [ButtonId: PadBehavior] {
        var result: [ButtonId: PadBehavior] = [:]
        let pageSize = 64
        let start = page * pageSize
        let end = min(start + pageSize, presets.count)
        for idx in start..<end {
            let local = idx - start
            let x = local % 8
            let y = local / 8
            let padId = ButtonId(x: x, y: y)
            let name = presets[idx]
            result[padId] = PadBehavior(
                padId: padId,
                mode: .selector,
                group: .presets,
                idleColor: LP.cyanDim,
                activeColor: LP.cyan,
                label: name,
                oscOn: nil,
                oscOff: nil,
                oscAction: OscCommand(address: "/presets/select", args: [.string(name)])
            )
        }
        return result
    }

    private func generateParamBehaviors(addresses: [String]) async -> [ButtonId: PadBehavior] {
        var result: [ButtonId: PadBehavior] = [:]
        for (idx, address) in addresses.enumerated() {
            let x = idx % 8
            let y = idx / 8
            let padId = ButtonId(x: x, y: y)
            let label = address.split(separator: "/").last.map(String.init) ?? address
            let args = (await awaitDynamicControlValue(address: address)) ?? []
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

    private func awaitDynamicControlValue(address: String) async -> [OscArg]? {
        await DynamicControlStore.shared.value(address: address)
    }
    
    // MARK: - Learn Mode
    
    /// Enter learn mode (requires device connected)
    public func startLearnMode() {
        onStateQueue { [weak self] in
            guard let self else { return }
            let result = enterLearnMode(self.state)
            self.state = result.state
            let effectsToExecute = self.mergedEffectsWithRender(from: result.effects)
            let currentState = self.state
            self.publishState(currentState, includeStatus: true)
            self.executor.executeAll(effectsToExecute)
        }
    }
    
    /// Exit learn mode
    public func stopLearnMode() {
        onStateQueue { [weak self] in
            guard let self else { return }
            let result = exitLearnMode(self.state)
            self.state = result.state
            let effectsToExecute = self.mergedEffectsWithRender(from: result.effects)
            let currentState = self.state
            self.publishState(currentState, includeStatus: true)
            self.executor.executeAll(effectsToExecute)
        }
    }
    
    /// Handle incoming OSC event for recording
    public func receiveOscEvent(_ event: OscEvent) {
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
                await DynamicControlStore.shared.update(address: event.address, args: event.args)
            }
            let paramsBanks = withStateSync { rolesByBank.filter { $0.value == .params }.map { $0.key } }
            if !paramsBanks.isEmpty { refreshDynamicBanks(for: paramsBanks) }
        }
        if event.address.hasPrefix("/scenes/") {
            let name = event.address.components(separatedBy: "/").last ?? ""
            if !name.isEmpty {
                Task {
                    var items = await DynamicGroupStore.shared.items(for: "$synesthesia/scenes")
                    if !items.contains(name) { items.append(name) }
                    await DynamicGroupStore.shared.update(source: "$synesthesia/scenes", items: items)
                    let sceneBanks = self.withStateSync { self.rolesByBank.filter { $0.value == .scenes || $0.value == .scenes2 }.map { $0.key } }
                    if !sceneBanks.isEmpty { refreshDynamicBanks(for: sceneBanks) }
                }
            }
        }
        if event.address.hasPrefix("/presets/") {
            let name = event.address.components(separatedBy: "/").last ?? ""
            if !name.isEmpty {
                Task {
                    var items = await DynamicGroupStore.shared.items(for: "$synesthesia/presets")
                    if !items.contains(name) { items.append(name) }
                    await DynamicGroupStore.shared.update(source: "$synesthesia/presets", items: items)
                    let presetBanks = self.withStateSync { self.rolesByBank.filter { $0.value == .presets }.map { $0.key } }
                    if !presetBanks.isEmpty { refreshDynamicBanks(for: presetBanks) }
                }
            }
        }

        onStateQueue { [weak self] in
            guard let self else { return }
            let result = handleOscEvent(self.state, event: event)
            self.state = result.state
            let effectsToExecute = self.mergedEffectsWithRender(from: result.effects)
            let currentState = self.state
            self.publishState(currentState, includeStatus: false)
            self.executor.executeAll(effectsToExecute)
        }
    }

    
    // MARK: - Manual Pad Config
    
    /// Manually configure a pad (requires device connected for LED update)
    public func configurePad(_ padId: ButtonId, behavior: PadBehavior) {
        onStateQueue { [weak self] in
            guard let self else { return }
            let result = addPadBehavior(self.state, behavior: behavior)
            self.state = result.state
            self.executor.updateConfig(padId: padId, behavior: behavior)
            let effectsToExecute = self.mergedEffectsWithRender(from: result.effects)
            let currentState = self.state
            self.publishState(currentState, includeStatus: false)
            self.executor.executeAll(effectsToExecute)
        }
    }
    
    /// Clear a pad's configuration
    public func clearPad(_ padId: ButtonId) {
        onStateQueue { [weak self] in
            guard let self else { return }
            let result = removePad(self.state, padId: padId)
            self.state = result.state
            self.executor.removeConfig(padId: padId)
            let effectsToExecute = self.mergedEffectsWithRender(from: result.effects)
            let currentState = self.state
            self.publishState(currentState, includeStatus: false)
            self.executor.executeAll(effectsToExecute)
        }
    }
    
    // MARK: - LED Control
    
    private func refreshLeds() {
        let effectsToExecute = withStateSync { mergedEffectsWithRender(from: []) }
        guard isEnabled else { return }
        executor.executeAll(effectsToExecute)
    }
    
    // MARK: - Direct LED Access
    
    /// Set LED directly (requires device connected)
    public func setLed(_ padId: ButtonId, color: Int) {
        guard withStateSync({ isEnabled }) else { return }
        midi.setLed(padId: padId, color: color)
    }
    
    /// Set multiple LEDs (requires device connected)
    public func setLeds(_ updates: [(ButtonId, Int)]) {
        guard withStateSync({ isEnabled }) else {
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
        guard withStateSync({ isEnabled }) else { return }
        midi.sendDAWModeSysEx()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.midi.sendProgrammerModeSysEx()
        }
    }
    
    // MARK: - Beat-Sync Blinking
    
    /// Enable or disable beat-sync LED blinking
    public func setBlinkEnabled(_ enabled: Bool) {
        onStateQueue { [weak self] in
            guard let self else { return }
            self.blinkEnabled = enabled
            if !enabled {
                // Reset all blinking pads to steady state
                self.refreshLeds()
            }
        }
    }
    
    private func startBlinkTimer() {
        stopBlinkTimer()
        
        // Default to 120 BPM = 500ms per beat = 250ms per half-beat (blink rate)
        let interval = 60.0 / Double(currentBpm) / 2.0

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.handleBlinkTickOnQueue()
        }
        timer.resume()
        blinkTimer = timer
        
        print("[Launchpad] Beat-sync blink timer started at \(currentBpm) BPM")
    }
    
    private func stopBlinkTimer() {
        blinkTimer?.setEventHandler {}
        blinkTimer?.cancel()
        blinkTimer = nil
    }
    
    public func updateBpm(_ bpm: Float) {
        onStateQueue { [weak self] in
            guard let self else { return }
            guard bpm > 20 && bpm < 300 else { return }  // Sanity check

            let bpmChanged = abs(self.currentBpm - bpm) > 1.0
            self.currentBpm = bpm

            // Restart timer with new BPM if significantly changed
            if bpmChanged && self.blinkTimer != nil {
                self.startBlinkTimer()
            }

            if bpmChanged {
                let statusSnapshot = self.makeStatusSnapshot(from: self.state)
                DispatchQueue.main.async { [weak self] in
                    self?.dispatch?(.launchpad(.statusUpdated(statusSnapshot)))
                }
            }
        }
    }
    
    private func handleBeatPulse() {
        // Immediate blink toggle on beat (more responsive than timer)
        onStateQueue { [weak self] in
            self?.handleBlinkTickOnQueue()
        }
    }
    
    private func handleBlinkTickOnQueue() {
        guard isEnabled && blinkEnabled else { return }

        // Toggle blink state
        state = toggleBlink(state)
        let blinkOn = state.blinkOn
        
        // Notify UI (for blink visualization)
        let currentState = state
        DispatchQueue.main.async { [weak self] in
            self?.dispatch?(.launchpad(.stateUpdated(currentState)))
        }
        
        // Update LEDs for pads that should blink (active selectors)
        var blinkEffects: [LaunchpadEffect] = []
        for (padId, behavior) in state.pads {
            guard behavior.mode == .selector else { continue }
            
            let runtime = state.padRuntime[padId] ?? PadRuntimeState()
            guard runtime.isActive else { continue }
            
            // Alternate between active and dimmed color
            let color = blinkOn ? behavior.activeColor : behavior.idleColor
            blinkEffects.append(.setLed(padId: padId, color: color, blink: false))
        }

        executor.executeAll(blinkEffects)
    }
}

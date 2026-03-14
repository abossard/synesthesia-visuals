// LaunchpadModule.swift - Top-level Launchpad controller
// Phase 5: MIDI Controller
// Unidirectional Data Flow: dispatches actions instead of callbacks
//
// Wires: MIDIManager → FSM → EffectExecutor
// Auto-connects to real hardware and keeps a UI simulation twin active.

import Foundation

/// Status of the Launchpad module
public struct LaunchpadStatus: Sendable, Equatable {
    public let isEnabled: Bool         // True only when real device connected
    public let isConnected: Bool       // True when hardware is connected or simulation twin is active
    public let deviceName: String?
    public let isLearnMode: Bool
    public let configuredPadCount: Int
    
    public init(
        isEnabled: Bool,
        isConnected: Bool,
        deviceName: String?,
        isLearnMode: Bool,
        configuredPadCount: Int
    ) {
        self.isEnabled = isEnabled
        self.isConnected = isConnected
        self.deviceName = deviceName
        self.isLearnMode = isLearnMode
        self.configuredPadCount = configuredPadCount
    }
}

/// Launchpad controller module with shared state/effect path for hardware + UI simulation
public final class LaunchpadModule: @unchecked Sendable {
    
    // MARK: - Components
    
    private let midi: MIDIManager
    private let executor: EffectExecutor
    private var state: ControllerState
    private var rolesByBank: [Int: BankRole] = [:]
    private var dynamicRefreshEpochByBank: [Int: Int] = [:]
    private var activeDynamicSceneName: String?
    private let stateQueue = DispatchQueue(label: "swiftvj.launchpad.state", qos: .userInitiated)
    private let stateQueueKey = DispatchSpecificKey<UInt8>()
    
    // MARK: - State

    /// Module is enabled only when real device is connected
    private(set) var isEnabled = false
    private var simulationTwinActive = false

    // MARK: - Action Dispatcher (Unidirectional Data Flow)

    /// Action dispatcher - set this to integrate with Store
    public var dispatch: ((AppAction) -> Void)?
    
    private static let verboseRuntimeLogs = ProcessInfo.processInfo.environment["SWIFTVJ_VERBOSE_LAUNCHPAD"] == "1"
    
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
            simulationTwinActive = true
            activeDynamicSceneName = nil

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
        refreshDynamicBanks()
        return connected
    }
    
    /// Stop the Launchpad module - disconnect and disable auto-reconnect
    public func stop() {
        withStateSync {
            simulationTwinActive = false
            activeDynamicSceneName = nil
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
            let connection = effectiveConnectionStatus()
            return LaunchpadStatus(
                isEnabled: isEnabled,
                isConnected: connection.isConnected,
                deviceName: connection.deviceName,
                isLearnMode: state.learnState.phase != .idle,
                configuredPadCount: state.pads.count
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
                print("[Launchpad] ○ Disabled - device disconnected")

                // Dispatch disconnection
                let currentState = self.state
                let statusSnapshot = self.makeStatusSnapshot(from: currentState)
                let shouldEmitDisconnected = !self.simulationTwinActive
                DispatchQueue.main.async { [weak self] in
                    if shouldEmitDisconnected {
                        self?.dispatch?(.launchpad(.disconnected))
                    }
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
        let connection = effectiveConnectionStatus()
        return LaunchpadStatusSnapshot(
            isConnected: connection.isConnected,
            deviceName: connection.deviceName,
            activeBank: snapshot.activeBank,
            padCount: snapshot.pads.count,
            isLearnMode: snapshot.learnState.phase != .idle
        )
    }

    private func effectiveConnectionStatus() -> (isConnected: Bool, deviceName: String?) {
        let hardwareConnected = midi.isConnected
        if hardwareConnected {
            return (true, midi.connectedDeviceName)
        }
        if simulationTwinActive {
            return (true, "Launchpad Simulator")
        }
        return (false, nil)
    }

    private func isDynamicRole(_ role: BankRole) -> Bool {
        role == .scenes || role == .scenes2 || role == .presets || role == .params || role == .meta
    }

    // MARK: - Dynamic Banks

    private func refreshDynamicBanks(for banks: [Int]? = nil) {
        // Dynamic bank materialization feeds the shared state path for hardware + UI twin.
        guard withStateSync({ isEnabled || simulationTwinActive }) else { return }

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
            let activeScene = self.withStateSync { self.activeDynamicSceneName }
            let sceneControls = self.sceneScopedControlAddresses(controls, activeScene: activeScene).sorted()
            let metaControls = self.metaControlAddresses(controls).sorted()
            let sceneTargets = self.collapseColorControls(in: sceneControls)
            let metaTargets = self.collapseColorControls(in: metaControls)

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
                    let totalPages = max(1, Int(ceil(Double(sceneTargets.count) / Double(pageSize))))
                    pageCounts[bank] = totalPages
                    let currentPage = min(request.page, totalPages - 1)
                    let start = currentPage * pageSize
                    let end = min(start + pageSize, sceneTargets.count)
                    let pageControls = start < end ? Array(sceneTargets[start..<end]) : []
                    let dynamicPads = await generateParamBehaviors(targets: pageControls)
                    updates[bank] = dynamicPads
                case .meta:
                    let pageSize = 64
                    let totalPages = max(1, Int(ceil(Double(metaTargets.count) / Double(pageSize))))
                    pageCounts[bank] = totalPages
                    let currentPage = min(request.page, totalPages - 1)
                    let start = currentPage * pageSize
                    let end = min(start + pageSize, metaTargets.count)
                    let pageControls = start < end ? Array(metaTargets[start..<end]) : []
                    let dynamicPads = await generateParamBehaviors(targets: pageControls)
                    updates[bank] = dynamicPads
                default:
                    break
                }
            }

            let finalUpdates = updates
            let finalPageCounts = pageCounts
            self.onStateQueue {
                guard self.isEnabled || self.simulationTwinActive else { return }
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
                    self.state.bankPadRuntime[bank] = pads.mapValues { self.initialRuntimeState(for: $0) }
                    if let activeVectorPad = self.state.bankActiveVectorPad[bank] ?? nil,
                       let activeBehavior = pads[activeVectorPad],
                       activeBehavior.mode == .vector2 {
                        var runtime = self.state.bankPadRuntime[bank]?[activeVectorPad] ?? self.initialRuntimeState(for: activeBehavior)
                        runtime.isActive = true
                        runtime.currentColor = activeBehavior.activeColor
                        self.state.bankPadRuntime[bank]?[activeVectorPad] = runtime
                    } else {
                        self.state.bankActiveVectorPad[bank] = nil
                    }
                    appliedBanks.append(bank)
                }

                let effectsToExecute = self.mergedEffectsWithRender(from: [])
                let currentState = self.state
                self.executor.executeAll(effectsToExecute)
                self.publishState(currentState, includeStatus: false)

                if Self.verboseRuntimeLogs && !appliedBanks.isEmpty {
                    print("[Dynamic] Refreshed banks \(appliedBanks.sorted()) scenes=\(scenes.count) controls=\(controls.count)")
                }
            }
        }
    }

    private func generateSceneBehaviors(scenes: [String], page: Int) -> [ButtonId: PadBehavior] {
        var result: [ButtonId: PadBehavior] = [:]
        let palette = LaunchpadColor.pickerColors
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

    private enum DynamicControlTarget: Sendable {
        case scalar(address: String)
        case color(base: String, channels: [String])
        case vector2(base: String, xAddress: String, yAddress: String)
    }

    private struct DynamicColorPaletteEntry: Sendable {
        let rgb: [Float]
        let ledColor: LaunchpadColor
    }

    private func generateParamBehaviors(targets: [DynamicControlTarget]) async -> [ButtonId: PadBehavior] {
        var result: [ButtonId: PadBehavior] = [:]
        let palette = configuredColorCyclePalette()
        for (idx, target) in targets.enumerated() {
            let x = idx % 8
            let y = idx / 8
            let padId = ButtonId(x: x, y: y)

            let behavior: PadBehavior
            switch target {
            case .scalar(let address):
                let args = (await awaitDynamicControlValue(address: address)) ?? []
                behavior = await inferParamBehavior(
                    address: address,
                    args: args,
                    padId: padId
                )
            case .color(let base, let channels):
                behavior = await makeColorCycleBehavior(
                    baseAddress: base,
                    channels: channels,
                    palette: palette,
                    padId: padId
                )
            case .vector2(let base, let xAddress, let yAddress):
                behavior = await makeVector2Behavior(
                    baseAddress: base,
                    xAddress: xAddress,
                    yAddress: yAddress,
                    padId: padId
                )
            }
            result[padId] = behavior
        }
        return result
    }

    private func awaitDynamicControlValue(address: String) async -> [OscArg]? {
        await DynamicControlStore.shared.value(address: address)
    }

    private func configuredColorCyclePalette() -> [DynamicColorPaletteEntry] {
        if let yaml = executor.yamlConfig,
           let configured = yaml.dynamic?.colorCyclePalette,
           !configured.isEmpty {
            let mapped = configured.compactMap { entry -> DynamicColorPaletteEntry? in
                guard entry.rgb.count == 3 else { return nil }
                let rgb = entry.rgb.map { Float($0) }
                let ledColor = entry.ledColor.map(yaml.color) ?? LP.white
                return DynamicColorPaletteEntry(rgb: rgb, ledColor: ledColor)
            }
            if !mapped.isEmpty {
                return mapped
            }
        }
        return Self.defaultColorCyclePalette
    }

    private static let defaultColorCyclePalette: [DynamicColorPaletteEntry] = [
        DynamicColorPaletteEntry(rgb: [1.0, 1.0, 1.0], ledColor: LP.white),
        DynamicColorPaletteEntry(rgb: [1.0, 0.2, 0.2], ledColor: LP.red),
        DynamicColorPaletteEntry(rgb: [1.0, 0.5, 0.1], ledColor: LP.orange),
        DynamicColorPaletteEntry(rgb: [1.0, 0.9, 0.2], ledColor: LP.yellow),
        DynamicColorPaletteEntry(rgb: [0.6, 1.0, 0.2], ledColor: LP.green),
        DynamicColorPaletteEntry(rgb: [0.2, 0.9, 0.3], ledColor: LP.green),
        DynamicColorPaletteEntry(rgb: [0.2, 0.9, 1.0], ledColor: LP.cyan),
        DynamicColorPaletteEntry(rgb: [0.2, 0.4, 1.0], ledColor: LP.blue),
        DynamicColorPaletteEntry(rgb: [0.4, 0.3, 1.0], ledColor: LP.blue),
        DynamicColorPaletteEntry(rgb: [0.7, 0.3, 1.0], ledColor: LP.purple),
        DynamicColorPaletteEntry(rgb: [1.0, 0.3, 0.9], ledColor: LP.pink),
        DynamicColorPaletteEntry(rgb: [1.0, 0.5, 0.7], ledColor: LP.pink),
    ]

    private func makeColorCycleBehavior(
        baseAddress: String,
        channels: [String],
        palette: [DynamicColorPaletteEntry],
        padId: ButtonId
    ) async -> PadBehavior {
        let label = dynamicControlLabel(for: baseAddress)
        let rgbAddresses = channels.sorted { lhs, rhs in
            colorChannelOrder(lhs) < colorChannelOrder(rhs)
        }

        var currentRGB: [Float] = []
        currentRGB.reserveCapacity(rgbAddresses.count)
        for address in rgbAddresses {
            let args = await awaitDynamicControlValue(address: address) ?? []
            currentRGB.append(firstNumericArg(args) ?? 0.0)
        }
        let nearestIndex = nearestPaletteIndex(for: currentRGB, palette: palette)
        let ledColors = palette.map(\.ledColor)
        let paletteValues = palette.map(\.rgb)
        let idleColor = ledColors.indices.contains(nearestIndex) ? ledColors[nearestIndex] : LP.white

        return PadBehavior(
            padId: padId,
            mode: .colorCycle,
            group: .custom,
            idleColor: idleColor,
            activeColor: idleColor,
            label: label,
            colorCycleAddresses: rgbAddresses,
            colorCyclePalette: paletteValues,
            colorCycleLedColors: ledColors,
            colorCycleIndex: nearestIndex
        )
    }

    private func makeVector2Behavior(
        baseAddress: String,
        xAddress: String,
        yAddress: String,
        padId: ButtonId
    ) async -> PadBehavior {
        let label = dynamicControlLabel(for: baseAddress)
        let xArgs = await awaitDynamicControlValue(address: xAddress) ?? []
        let yArgs = await awaitDynamicControlValue(address: yAddress) ?? []
        let xValue = clampUnit(firstNumericArg(xArgs) ?? 0.5)
        let yValue = clampUnit(firstNumericArg(yArgs) ?? 0.5)

        return PadBehavior(
            padId: padId,
            mode: .vector2,
            group: .custom,
            idleColor: LP.cyanDim,
            activeColor: LP.cyan,
            label: label,
            step: 0.1,
            minValue: 0.0,
            maxValue: 1.0,
            vector2Addresses: [xAddress, yAddress],
            vector2Current: [xValue, yValue],
            vector2Default: [0.5, 0.5]
        )
    }

    private func nearestPaletteIndex(for rgb: [Float], palette: [DynamicColorPaletteEntry]) -> Int {
        guard rgb.count == 3, !palette.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDistance = Float.greatestFiniteMagnitude
        for (index, entry) in palette.enumerated() where entry.rgb.count == 3 {
            let dr = rgb[0] - entry.rgb[0]
            let dg = rgb[1] - entry.rgb[1]
            let db = rgb[2] - entry.rgb[2]
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func colorChannelOrder(_ address: String) -> Int {
        if address.hasSuffix("/r") { return 0 }
        if address.hasSuffix("/g") { return 1 }
        if address.hasSuffix("/b") { return 2 }
        return 99
    }

    private enum DynamicParamMode {
        case toggle
        case stepped(min: Float, max: Float, step: Float, current: Float)
        case enumerated(optionCount: Int, current: Float, normalized: Bool)
        case trigger
    }

    private func inferParamBehavior(address: String, args: [OscArg], padId: ButtonId) async -> PadBehavior {
        let mode = await inferParamMode(address: address, args: args)
        let label = dynamicControlLabel(for: address)

        switch mode {
        case .toggle:
            return PadBehavior(
                padId: padId,
                mode: .toggle,
                group: .custom,
                idleColor: LP.greenDim,
                activeColor: LP.green,
                label: label,
                oscOn: OscCommand(address: address, args: [.float(1.0)]),
                oscOff: OscCommand(address: address, args: [.float(0.0)])
            )
        case .stepped(let min, let max, let step, let current):
            return PadBehavior(
                padId: padId,
                mode: .increment,
                group: .custom,
                idleColor: LP.orangeDim,
                activeColor: LP.orange,
                label: label,
                oscOn: nil,
                oscOff: nil,
                oscAction: OscCommand(address: address, args: [.float(current)]),
                step: step,
                minValue: min,
                maxValue: max
            )
        case .enumerated(let optionCount, let current, let normalized):
            let maxIndex = max(1, optionCount - 1)
            let step = normalized ? (1.0 / Float(maxIndex)) : 1.0
            let maxValue = normalized ? 1.0 : Float(maxIndex)
            return PadBehavior(
                padId: padId,
                mode: .increment,
                group: .custom,
                idleColor: LP.purpleDim,
                activeColor: LP.purple,
                label: label,
                oscOn: nil,
                oscOff: nil,
                oscAction: OscCommand(address: address, args: [.float(current)]),
                step: step,
                minValue: 0.0,
                maxValue: maxValue,
                enumOptionCount: optionCount
            )
        case .trigger:
            return PadBehavior(
                padId: padId,
                mode: .oneShot,
                group: .custom,
                idleColor: LP.blueDim,
                activeColor: LP.blue,
                label: label,
                oscOn: nil,
                oscOff: nil,
                oscAction: OscCommand(address: address, args: args)
            )
        }
    }

    private func inferParamMode(address: String, args: [OscArg]) async -> DynamicParamMode {
        if address.lowercased().contains("reset") {
            return .trigger
        }

        if let optionCount = await enumOptionCount(for: address), optionCount > 1 {
            let currentRaw = firstNumericArg(args) ?? 0.0
            if isNormalizedEnumValue(currentRaw) {
                return .enumerated(
                    optionCount: optionCount,
                    current: max(0.0, min(1.0, currentRaw)),
                    normalized: true
                )
            }

            let maxIndex = Float(max(0, optionCount - 1))
            return .enumerated(
                optionCount: optionCount,
                current: max(0.0, min(maxIndex, currentRaw.rounded())),
                normalized: false
            )
        }

        if args.count == 1, let value = firstNumericArg(args) {
            if isBinaryValue(value) {
                return .toggle
            }
            if (0.0...1.0).contains(value) {
                return .stepped(min: 0.0, max: 1.0, step: 0.05, current: value)
            }
            let range = max(1.0, abs(value))
            return .stepped(
                min: -range,
                max: range,
                step: max(0.1, range * 0.05),
                current: value
            )
        }

        return .trigger
    }

    private func enumOptionCount(for address: String) async -> Int? {
        guard let args = await awaitDynamicControlValue(address: "\(address)/numoptions"),
              let raw = firstNumericArg(args) else {
            return nil
        }
        return Int(raw.rounded())
    }

    private func firstNumericArg(_ args: [OscArg]) -> Float? {
        guard let first = args.first else { return nil }
        return numericValue(from: first)
    }

    private func numericValue(from arg: OscArg) -> Float? {
        switch arg {
        case .float(let value): return value
        case .int(let value): return Float(value)
        case .bool(let value): return value ? 1.0 : 0.0
        case .string: return nil
        }
    }

    private func isBinaryValue(_ value: Float) -> Bool {
        abs(value) < 0.0001 || abs(value - 1.0) < 0.0001
    }

    private func isNormalizedEnumValue(_ value: Float) -> Bool {
        value >= -0.0001 && value <= 1.0001
    }

    private func clampUnit(_ value: Float) -> Float {
        max(0.0, min(1.0, value))
    }

    private func dynamicControlLabel(for address: String) -> String {
        let parts = address.split(separator: "/")
        guard parts.count >= 3 else { return address }

        if parts[1] == "meta" || parts[1] == "global" {
            return parts.suffix(2).joined(separator: "/")
        }

        if parts.count >= 4 {
            return String(parts[3])
        }

        return String(parts.last ?? "")
    }

    private func initialRuntimeState(for behavior: PadBehavior) -> PadRuntimeState {
        var runtime = PadRuntimeState(currentColor: behavior.idleColor)
        if behavior.mode == .colorCycle {
            runtime.isActive = true
            runtime.currentValue = Float(behavior.colorCycleIndex)
            return runtime
        }
        if behavior.mode == .vector2 {
            let current = behavior.vector2Current.count == 2 ? behavior.vector2Current : [0.5, 0.5]
            runtime.currentValue = clampUnit(current[0])
            runtime.secondaryValue = clampUnit(current[1])
            return runtime
        }
        if (behavior.mode == .increment || behavior.mode == .decrement),
           let seedArg = behavior.oscAction?.args.first,
           let seedValue = numericValue(from: seedArg) {
            runtime.currentValue = seedValue
        }
        return runtime
    }

    private func sceneScopedControlAddresses(_ controls: [String], activeScene: String?) -> [String] {
        controls.filter { address in
            guard let scope = controlScope(for: address) else { return false }
            if scope == "meta" || scope == "global" {
                return false
            }
            if let activeScene, !activeScene.isEmpty {
                return scope == activeScene
            }
            return true
        }
    }

    private func metaControlAddresses(_ controls: [String]) -> [String] {
        controls.filter { address in
            guard let scope = controlScope(for: address) else { return false }
            return scope == "meta" || scope == "global"
        }
    }

    private func collapseColorControls(in addresses: [String]) -> [DynamicControlTarget] {
        var colorGroupChannels: [String: Set<String>] = [:]
        var vectorGroupAxes: [String: Set<String>] = [:]
        for address in addresses {
            guard let base = colorControlBase(for: address),
                  let channel = colorChannel(for: address) else {
                if let vectorBase = vectorControlBase(for: address),
                   let axis = vectorAxis(for: address) {
                    vectorGroupAxes[vectorBase, default: []].insert(axis)
                }
                continue
            }
            colorGroupChannels[base, default: []].insert(channel)
        }

        var result: [DynamicControlTarget] = []
        var emittedBases: Set<String> = []
        var emittedVectorBases: Set<String> = []
        for address in addresses {
            if let base = colorControlBase(for: address),
               let channels = colorGroupChannels[base] {
                guard !emittedBases.contains(base) else { continue }
                emittedBases.insert(base)
                if channels == Set(["r", "g", "b"]) {
                    result.append(.color(base: base, channels: ["\(base)/r", "\(base)/g", "\(base)/b"]))
                } else {
                    let ordered = channels.sorted()
                    for channel in ordered {
                        result.append(.scalar(address: "\(base)/\(channel)"))
                    }
                }
            } else if let vectorBase = vectorControlBase(for: address),
                      let axes = vectorGroupAxes[vectorBase] {
                guard !emittedVectorBases.contains(vectorBase) else { continue }
                emittedVectorBases.insert(vectorBase)
                if axes == Set(["x", "y"]) {
                    result.append(
                        .vector2(
                            base: vectorBase,
                            xAddress: "\(vectorBase)/x",
                            yAddress: "\(vectorBase)/y"
                        )
                    )
                } else {
                    let ordered = axes.sorted()
                    for axis in ordered {
                        result.append(.scalar(address: "\(vectorBase)/\(axis)"))
                    }
                }
            } else {
                result.append(.scalar(address: address))
            }
        }
        return result
    }

    private func colorControlBase(for address: String) -> String? {
        let parts = address.split(separator: "/")
        guard parts.count >= 4, parts[0] == "controls" else { return nil }
        let channel = parts.last.map(String.init) ?? ""
        guard channel == "r" || channel == "g" || channel == "b" else { return nil }
        return "/" + parts.dropLast().joined(separator: "/")
    }

    private func colorChannel(for address: String) -> String? {
        let channel = address.split(separator: "/").last.map(String.init)
        guard channel == "r" || channel == "g" || channel == "b" else { return nil }
        return channel
    }

    private func vectorControlBase(for address: String) -> String? {
        let parts = address.split(separator: "/")
        guard parts.count >= 4, parts[0] == "controls" else { return nil }
        let axis = parts.last.map(String.init) ?? ""
        guard axis == "x" || axis == "y" else { return nil }
        return "/" + parts.dropLast().joined(separator: "/")
    }

    private func vectorAxis(for address: String) -> String? {
        let axis = address.split(separator: "/").last.map(String.init)
        guard axis == "x" || axis == "y" else { return nil }
        return axis
    }

    private func dynamicControlSortKey(for address: String, activeScene: String?) -> (Int, String) {
        guard let scope = controlScope(for: address) else { return (3, address) }
        if let activeScene, scope == activeScene {
            return (0, address)
        }
        if scope == "meta" {
            return (1, address)
        }
        if scope == "global" {
            return (2, address)
        }
        return (3, address)
    }

    private func controlScope(for address: String) -> String? {
        let parts = address.split(separator: "/")
        guard parts.count >= 3, parts[0] == "controls" else { return nil }
        return String(parts[1])
    }

    private func shouldTrackDynamicControl(address: String) -> Bool {
        guard let scope = controlScope(for: address) else { return false }
        if scope == "meta" || scope == "global" {
            return true
        }
        guard let activeDynamicSceneName, !activeDynamicSceneName.isEmpty else {
            return true
        }
        return scope == activeDynamicSceneName
    }

    private func sceneName(from event: OscEvent) -> String? {
        let parts = event.address.split(separator: "/")
        guard parts.count >= 2, parts[0] == "scenes" else { return nil }
        if parts[1] == "select" {
            guard let firstArg = event.args.first, case .string(let selected) = firstArg else {
                return nil
            }
            return selected.isEmpty ? nil : selected
        }
        return String(parts[1])
    }
    
    // MARK: - Learn Mode
    
    /// Enter learn mode (available for hardware and UI simulation twin)
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
        // Capture dynamic scenes/controls
        if event.address.hasPrefix("/controls/") {
            let shouldTrack = withStateSync { shouldTrackDynamicControl(address: event.address) }
            if shouldTrack {
                Task { [weak self] in
                    await DynamicControlStore.shared.update(address: event.address, args: event.args)
                    guard let self else { return }
                    let controlBanks = self.withStateSync {
                        self.rolesByBank.filter { $0.value == .params || $0.value == .meta }.map { $0.key }
                    }
                    if !controlBanks.isEmpty { self.refreshDynamicBanks(for: controlBanks) }
                }
            }
        }
        if event.address.hasPrefix("/scenes/"), let name = sceneName(from: event), !name.isEmpty {
            withStateSync { activeDynamicSceneName = name }
            Task { [weak self] in
                guard let self else { return }
                await DynamicControlStore.shared.clearSceneScopedControls()
                let paramsBanks = self.withStateSync { self.rolesByBank.filter { $0.value == .params }.map { $0.key } }
                if !paramsBanks.isEmpty { self.refreshDynamicBanks(for: paramsBanks) }

                    var items = await DynamicGroupStore.shared.items(for: "$synesthesia/scenes")
                    if !items.contains(name) { items.append(name) }
                    await DynamicGroupStore.shared.update(source: "$synesthesia/scenes", items: items)
                    let sceneBanks = self.withStateSync { self.rolesByBank.filter { $0.value == .scenes || $0.value == .scenes2 }.map { $0.key } }
                    if !sceneBanks.isEmpty { self.refreshDynamicBanks(for: sceneBanks) }
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
            var workingState = self.state
            var combinedEffects: [LaunchpadEffect] = []

            if workingState.learnState.phase == .config {
                let captureResult = captureOscEvent(workingState, event: event)
                workingState = captureResult.state
                combinedEffects.append(contentsOf: captureResult.effects)
            }

            let syncResult = handleOscEvent(workingState, event: event)
            workingState = syncResult.state
            combinedEffects.append(contentsOf: syncResult.effects)

            self.state = workingState
            let effectsToExecute = self.mergedEffectsWithRender(from: combinedEffects)
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
    public func setLed(_ padId: ButtonId, color: LaunchpadColor) {
        guard withStateSync({ isEnabled }) else { return }
        midi.setLed(padId: padId, color: color.rawValue)
    }
    
    /// Set multiple LEDs (requires device connected)
    public func setLeds(_ updates: [(ButtonId, LaunchpadColor)]) {
        guard withStateSync({ isEnabled }) else {
            if Self.verboseRuntimeLogs {
                print("[Launchpad] setLeds ignored - module disabled")
            }
            return
        }
        if Self.verboseRuntimeLogs {
            print("[Launchpad] setLeds: updating \(updates.count) pads")
        }
        for (padId, color) in updates {
            midi.setLed(padId: padId, color: color.rawValue)
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
}

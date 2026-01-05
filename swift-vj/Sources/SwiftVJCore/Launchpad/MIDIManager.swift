// MIDIManager.swift - CoreMIDI wrapper for Launchpad
// Phase 5: MIDI Controller
//
// Deep module hiding CoreMIDI complexity behind simple interface
// Auto-detects Launchpad connect/disconnect - no mocks, real hardware only

import Foundation
import CoreMIDI

/// MIDI device info
public struct MIDIDeviceInfo: Identifiable, Sendable, Equatable {
    public let id: MIDIEndpointRef
    public let name: String
    public let manufacturer: String
    public let isLaunchpad: Bool
    
    init(endpoint: MIDIEndpointRef) {
        self.id = endpoint
        self.name = MIDIManager.getStringProperty(endpoint, kMIDIPropertyDisplayName) ?? "Unknown"
        self.manufacturer = MIDIManager.getStringProperty(endpoint, kMIDIPropertyManufacturer) ?? ""
        self.isLaunchpad = name.lowercased().contains("launchpad")
    }
    
    public static func == (lhs: MIDIDeviceInfo, rhs: MIDIDeviceInfo) -> Bool {
        lhs.id == rhs.id
    }
}

/// MIDI message type
public enum MIDIMessage: Sendable {
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int, velocity: Int)
    case controlChange(channel: Int, controller: Int, value: Int)
    
    /// Convert to ButtonId (Launchpad Programmer mode)
    /// - Notes 11-88: grid pads (y=0-7)
    /// - CC 91-98: top row buttons (x=0-7, y=-1)
    /// - CC 19,29,39,49,59,69,79,89: scene buttons (x=8, y=0-7)
    public var buttonId: ButtonId? {
        switch self {
        case .noteOn(_, let note, _), .noteOff(_, let note, _):
            return ButtonId(midiNote: note)
        case .controlChange(_, let controller, _):
            // Top row: CC 91-98 → x=0-7, y=-1
            if controller >= 91 && controller <= 98 {
                return ButtonId(x: controller - 91, y: -1)
            }
            // Scene buttons (right column): CC 19,29,39,49,59,69,79,89 → x=8, y=0-7
            if controller >= 19 && controller <= 89 && controller % 10 == 9 {
                let row = (controller / 10) - 1  // CC 19→row 0, CC 89→row 7
                return ButtonId(x: 8, y: row)
            }
            return nil
        }
    }
    
    /// Whether this is a press (noteOn with velocity > 0, or CC with value > 0)
    public var isPress: Bool {
        switch self {
        case .noteOn(_, _, let velocity):
            return velocity > 0
        case .controlChange(_, _, let value):
            return value > 0
        default:
            return false
        }
    }
    
    /// Whether this is a release (noteOff, noteOn with velocity 0, or CC with value 0)
    public var isRelease: Bool {
        switch self {
        case .noteOff:
            return true
        case .noteOn(_, _, let velocity):
            return velocity == 0
        case .controlChange(_, _, let value):
            return value == 0
        }
    }
}

/// Callback for MIDI messages
public typealias MIDIMessageCallback = @Sendable (MIDIMessage) -> Void

/// Callback for connection state changes
public typealias ConnectionStateCallback = @Sendable (Bool, String?) -> Void

/// CoreMIDI wrapper for device discovery and communication
/// Auto-monitors for Launchpad connect/disconnect events
public final class MIDIManager: @unchecked Sendable {
    
    // MARK: - Properties
    
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var connectedInput: MIDIEndpointRef = 0
    private var connectedOutput: MIDIEndpointRef = 0
    
    private var messageCallback: MIDIMessageCallback?
    private var connectionCallback: ConnectionStateCallback?
    private let callbackQueue = DispatchQueue(label: "midi.callback", qos: .userInteractive)
    
    /// Whether auto-reconnect is enabled
    private var autoReconnectEnabled = false
    
    /// Current connection status
    public private(set) var isConnected = false
    
    /// Name of connected device
    public private(set) var connectedDeviceName: String?
    
    /// Whether MIDI system is available
    public var isAvailable: Bool { client != 0 }
    
    // MARK: - Init
    
    public init() {
        setupMIDI()
    }
    
    deinit {
        disconnect()
        if client != 0 {
            MIDIClientDispose(client)
        }
    }
    
    // MARK: - Setup
    
    private func setupMIDI() {
        let status = MIDIClientCreateWithBlock("SwiftVJ" as CFString, &client) { [weak self] notification in
            self?.handleMIDINotification(notification)
        }
        
        if status != noErr {
            print("[MIDI] Failed to create client: \(status)")
            return
        }
        
        // Create input port
        let inputStatus = MIDIInputPortCreateWithProtocol(
            client,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            self?.handleMIDIEvents(eventList)
        }
        
        if inputStatus != noErr {
            print("[MIDI] Failed to create input port: \(inputStatus)")
        }
        
        // Create output port
        let outputStatus = MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
        
        if outputStatus != noErr {
            print("[MIDI] Failed to create output port: \(outputStatus)")
        }
        
        print("[MIDI] CoreMIDI initialized - \(MIDIGetNumberOfSources()) sources, \(MIDIGetNumberOfDestinations()) destinations")
    }
    
    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged:
            print("[MIDI] Setup changed - checking devices")
            handleDeviceChange()
            
        case .msgObjectAdded:
            print("[MIDI] Device added")
            // Delay slightly to let CoreMIDI finish setup
            callbackQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.handleDeviceChange()
            }
            
        case .msgObjectRemoved:
            print("[MIDI] Device removed")
            // Check if our device was removed
            callbackQueue.async { [weak self] in
                self?.handleDeviceChange()
            }
            
        default:
            break
        }
    }
    
    private func handleDeviceChange() {
        // If connected, check if device is still available
        if isConnected {
            let inputs = availableInputs()
            let stillExists = inputs.contains { $0.id == connectedInput }
            
            if !stillExists {
                print("[MIDI] Connected device no longer available")
                handleDisconnection()
                return
            }
        }
        
        // If not connected but auto-reconnect is enabled, try to connect
        if !isConnected && autoReconnectEnabled {
            if let _ = findLaunchpad() {
                print("[MIDI] Launchpad detected - auto-connecting")
                tryAutoConnect()
            }
        }
    }
    
    private func handleDisconnection() {
        let wasConnected = isConnected
        let deviceName = connectedDeviceName
        
        // Clean up connection state
        connectedInput = 0
        connectedOutput = 0
        connectedDeviceName = nil
        isConnected = false
        
        if wasConnected {
            print("[MIDI] Disconnected from \(deviceName ?? "device")")
            
            // Notify via callback
            if let callback = connectionCallback {
                callbackQueue.async {
                    callback(false, nil)
                }
            }
        }
    }
    
    private func tryAutoConnect() {
        guard autoReconnectEnabled, let callback = messageCallback else { return }
        
        if connectToLaunchpad(callback: callback) {
            // Notify connection
            if let connCallback = connectionCallback {
                callbackQueue.async { [weak self] in
                    connCallback(true, self?.connectedDeviceName)
                }
            }
        }
    }
    
    private func isEndpointValid(_ endpoint: MIDIEndpointRef) -> Bool {
        guard endpoint != 0 else { return false }
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        if status == noErr, let cfName = name {
            cfName.release()
            return true
        }
        return false
    }
    
    // MARK: - Device Discovery
    
    /// Get all available MIDI input devices
    public func availableInputs() -> [MIDIDeviceInfo] {
        var devices: [MIDIDeviceInfo] = []
        let sourceCount = MIDIGetNumberOfSources()
        
        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)
            if endpoint != 0 {
                devices.append(MIDIDeviceInfo(endpoint: endpoint))
            }
        }
        
        return devices
    }
    
    /// Get all available MIDI output devices
    public func availableOutputs() -> [MIDIDeviceInfo] {
        var devices: [MIDIDeviceInfo] = []
        let destCount = MIDIGetNumberOfDestinations()
        
        for i in 0..<destCount {
            let endpoint = MIDIGetDestination(i)
            if endpoint != 0 {
                devices.append(MIDIDeviceInfo(endpoint: endpoint))
            }
        }
        
        return devices
    }
    
    /// Find first Launchpad device
    /// Prefers the MIDI port over the DAW port for Programmer mode LED control
    public func findLaunchpad() -> (input: MIDIDeviceInfo, output: MIDIDeviceInfo)? {
        let inputs = availableInputs().filter { $0.isLaunchpad }
        let outputs = availableOutputs().filter { $0.isLaunchpad }
        
        // Debug: show all Launchpad ports
        print("[MIDI] Available Launchpad inputs: \(inputs.map { $0.name })")
        print("[MIDI] Available Launchpad outputs: \(outputs.map { $0.name })")
        
        // Prefer MIDI port over DAW port for LED control in Programmer mode
        // DAW ports contain "DAW" in their name, MIDI ports contain "MIDI" or neither
        let preferMIDI: (MIDIDeviceInfo, MIDIDeviceInfo) -> Bool = { a, b in
            let aIsDAW = a.name.lowercased().contains("daw")
            let bIsDAW = b.name.lowercased().contains("daw")
            // Prefer non-DAW (MIDI) ports
            if aIsDAW && !bIsDAW { return false }
            if !aIsDAW && bIsDAW { return true }
            return true // Keep original order otherwise
        }
        
        let sortedInputs = inputs.sorted(by: preferMIDI)
        let sortedOutputs = outputs.sorted(by: preferMIDI)
        
        guard let input = sortedInputs.first, let output = sortedOutputs.first else {
            return nil
        }
        
        print("[MIDI] Selected Launchpad: IN=\(input.name) / OUT=\(output.name)")
        return (input, output)
    }
    
    /// Check if any Launchpad is currently available
    public var isLaunchpadAvailable: Bool {
        findLaunchpad() != nil
    }
    
    // MARK: - Connection
    
    /// Connect to a MIDI device pair
    public func connect(input: MIDIDeviceInfo, output: MIDIDeviceInfo, callback: @escaping MIDIMessageCallback) -> Bool {
        disconnect()
        
        // Verify endpoints are still valid
        guard isEndpointValid(input.id), isEndpointValid(output.id) else {
            print("[MIDI] Device endpoints no longer valid")
            return false
        }
        
        // Connect input
        let inputStatus = MIDIPortConnectSource(inputPort, input.id, nil)
        if inputStatus != noErr {
            print("[MIDI] Failed to connect input: \(inputStatus)")
            return false
        }
        
        connectedInput = input.id
        connectedOutput = output.id
        connectedDeviceName = input.name
        messageCallback = callback
        isConnected = true
        
        print("[MIDI] ✓ Connected to \(input.name)")
        
        // Switch to Programmer Mode immediately
        if input.isLaunchpad {
            // 1. Enter DAW Mode
            sendDAWModeSysEx()
            
            // 2. Enter Programmer Mode (after small delay)
            callbackQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.sendProgrammerModeSysEx()
            }
        }
        
        return true
    }
    
    /// Connect to first available Launchpad
    @discardableResult
    public func connectToLaunchpad(callback: @escaping MIDIMessageCallback) -> Bool {
        guard let (input, output) = findLaunchpad() else {
            print("[MIDI] No Launchpad found in available devices")
            return false
        }
        
        return connect(input: input, output: output, callback: callback)
    }
    
    /// Enable auto-reconnect with connection state callback
    /// When enabled, will automatically connect when Launchpad appears and notify on disconnect
    public func enableAutoReconnect(
        messageCallback: @escaping MIDIMessageCallback,
        connectionCallback: @escaping ConnectionStateCallback
    ) {
        self.messageCallback = messageCallback
        self.connectionCallback = connectionCallback
        self.autoReconnectEnabled = true
        
        // Try immediate connection if device already present
        if let _ = findLaunchpad() {
            if connectToLaunchpad(callback: messageCallback) {
                callbackQueue.async { [weak self] in
                    connectionCallback(true, self?.connectedDeviceName)
                }
            }
        } else {
            print("[MIDI] Auto-reconnect enabled - waiting for Launchpad")
        }
    }
    
    /// Disable auto-reconnect
    public func disableAutoReconnect() {
        autoReconnectEnabled = false
        connectionCallback = nil
    }
    
    /// Disconnect from current device
    public func disconnect() {
        if connectedInput != 0 {
            MIDIPortDisconnectSource(inputPort, connectedInput)
        }
        
        let wasConnected = isConnected
        connectedInput = 0
        connectedOutput = 0
        connectedDeviceName = nil
        isConnected = false
        
        if wasConnected {
            print("[MIDI] Disconnected")
        }
    }
    
    // MARK: - Send
    
    private var sendCount = 0
    
    private func sendBytes(_ bytes: [UInt8]) {
        guard isConnected, connectedOutput != 0 else {
            print("[MIDI] sendBytes skipped - not connected (isConnected=\(isConnected), output=\(connectedOutput))")
            return
        }
        
        var packet = MIDIPacket()
        packet.timeStamp = 0
        packet.length = UInt16(bytes.count)
        
        // Unsafe copy to packet.data tuple
        withUnsafeMutablePointer(to: &packet.data) { dataPtr in
            bytes.withUnsafeBytes { bytesPtr in
                dataPtr.withMemoryRebound(to: UInt8.self, capacity: 256) { destPtr in
                    destPtr.update(from: bytesPtr.baseAddress!.assumingMemoryBound(to: UInt8.self), count: bytes.count)
                }
            }
        }
        
        var packetList = MIDIPacketList()
        packetList.numPackets = 1
        packetList.packet = packet
        
        withUnsafePointer(to: packetList) { ptr in
            let result = MIDISend(outputPort, connectedOutput, ptr)
            sendCount += 1
            if result != noErr {
                print("[MIDI] Error sending packet: \(result) (OSStatus)")
            } else if sendCount <= 5 || sendCount % 100 == 0 {
                // Log first few sends and then periodically
                print("[MIDI] Sent \(sendCount): \(bytes.map { String(format: "%02X", $0) }.joined(separator: " ")) to endpoint \(connectedOutput)")
            }
        }
    }

    /// Send a note on message
    public func sendNoteOn(channel: Int, note: Int, velocity: Int) {
        sendBytes([0x90 | UInt8(channel & 0xF), UInt8(note & 0x7F), UInt8(velocity & 0x7F)])
    }
    
    /// Send a note off message
    public func sendNoteOff(channel: Int, note: Int, velocity: Int = 0) {
        sendBytes([0x80 | UInt8(channel & 0xF), UInt8(note & 0x7F), UInt8(velocity & 0x7F)])
    }
    
    /// Send a control change message
    public func sendControlChange(channel: Int, controller: Int, value: Int) {
        sendBytes([0xB0 | UInt8(channel & 0xF), UInt8(controller & 0x7F), UInt8(value & 0x7F)])
    }
    
    // MARK: - MIDI Beat Clock
    
    /// MIDI Clock messages (System Real-Time)
    private let MIDI_CLOCK: UInt8 = 0xF8      // Timing clock (24 per quarter note)
    private let MIDI_START: UInt8 = 0xFA      // Start
    private let MIDI_CONTINUE: UInt8 = 0xFB  // Continue
    private let MIDI_STOP: UInt8 = 0xFC       // Stop
    
    private var clockTimer: Timer?
    private var currentClockBpm: Float = 120.0
    
    /// Start sending MIDI clock at the specified BPM
    /// The Launchpad syncs flashing LEDs to this clock (24 PPQN)
    public func startMidiClock(bpm: Float) {
        stopMidiClock()
        
        guard bpm > 20 && bpm < 300 else { return }
        currentClockBpm = bpm
        
        // MIDI clock: 24 pulses per quarter note
        // Interval = 60 seconds / BPM / 24
        let interval = 60.0 / Double(bpm) / 24.0
        
        // Send MIDI Start
        sendBytes([MIDI_START])
        print("[MIDI] Clock started at \(bpm) BPM (interval: \(String(format: "%.2f", interval * 1000))ms)")
        
        // Start clock timer
        clockTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sendClockTick()
        }
        
        // Add to main run loop to ensure it fires during UI events
        if let timer = clockTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    /// Update MIDI clock BPM (restarts clock with new tempo)
    public func updateMidiClockBpm(_ bpm: Float) {
        guard bpm > 20 && bpm < 300 else { return }
        guard abs(currentClockBpm - bpm) > 0.5 else { return }  // Ignore tiny changes
        
        if clockTimer != nil {
            startMidiClock(bpm: bpm)
        }
    }
    
    /// Stop sending MIDI clock
    public func stopMidiClock() {
        clockTimer?.invalidate()
        clockTimer = nil
        
        // Send MIDI Stop
        if isConnected {
            sendBytes([MIDI_STOP])
        }
    }
    
    private func sendClockTick() {
        guard isConnected else { return }
        sendBytes([MIDI_CLOCK])
    }
    
    /// Send DAW Mode SysEx (Launchpad Mini MK3)
    public func sendDAWModeSysEx() {
        // Launchpad Mini MK3 Enter DAW Mode: F0 00 20 29 02 0D 10 01 F7
        sendBytes([0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x10, 0x01, 0xF7])
        print("[MIDI] Sent DAW Mode SysEx")
    }

    /// Send Programmer Mode SysEx (Launchpad Mini MK3)
    public func sendProgrammerModeSysEx() {
        // Launchpad Mini MK3 Programmer Mode: F0 00 20 29 02 0D 0E 01 F7
        sendBytes([0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7])
        print("[MIDI] Sent Programmer Mode SysEx")
    }
    
    /// LED lighting mode (Launchpad Mini MK3 SysEx types)
    public enum LedMode: UInt8 {
        case solid = 0   // Static colour from palette
        case flash = 1   // Flashing colour (alternates between two colors)
        case pulse = 2   // Pulsing colour (fades in/out)
        case rgb = 3     // RGB colour (3 bytes)
    }
    
    // MARK: - SysEx LED Lighting
    
    /// LED lighting SysEx header: F0 00 20 29 02 0D 03
    private let ledSysExHeader: [UInt8] = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x03]
    
    /// Get LED index for a ButtonId (Programmer mode layout)
    private func ledIndex(for padId: ButtonId) -> UInt8 {
        if padId.isTopRow {
            // Top row: indices 91-98
            return UInt8(91 + padId.x)
        } else if padId.isSceneButton {
            // Scene buttons: indices 19, 29, 39, 49, 59, 69, 79, 89
            return UInt8((padId.y + 1) * 10 + 9)
        } else {
            // Grid: note = (y+1)*10 + (x+1), e.g. (0,0)→11, (7,7)→88
            return UInt8(padId.midiNote)
        }
    }
    
    /// Set LED color using SysEx message (more reliable than MIDI channel method)
    public func setLed(padId: ButtonId, color: Int, mode: LedMode = .solid) {
        let index = ledIndex(for: padId)
        var message = ledSysExHeader
        
        switch mode {
        case .solid:
            // Type 0: Static - 1 byte color
            message += [0x00, index, UInt8(color & 0x7F)]
        case .flash:
            // Type 1: Flashing - 2 bytes (color B = off/dim, color A = bright)
            // Flash between off and the color
            message += [0x01, index, 0x00, UInt8(color & 0x7F)]
        case .pulse:
            // Type 2: Pulsing - 1 byte color
            message += [0x02, index, UInt8(color & 0x7F)]
        case .rgb:
            // Type 3: RGB - 3 bytes (not used for palette colors)
            // For RGB, color encodes R/G/B packed, but we don't use this path normally
            message += [0x03, index, UInt8((color >> 14) & 0x7F), UInt8((color >> 7) & 0x7F), UInt8(color & 0x7F)]
        }
        
        message.append(0xF7)  // SysEx end
        sendBytes(message)
    }
    
    /// Set multiple LEDs in a single SysEx message (efficient batch update)
    public func setLeds(_ updates: [(padId: ButtonId, color: Int, mode: LedMode)]) {
        guard !updates.isEmpty else { return }
        
        var message = ledSysExHeader
        
        for (padId, color, mode) in updates {
            let index = ledIndex(for: padId)
            switch mode {
            case .solid:
                message += [0x00, index, UInt8(color & 0x7F)]
            case .flash:
                message += [0x01, index, 0x00, UInt8(color & 0x7F)]
            case .pulse:
                message += [0x02, index, UInt8(color & 0x7F)]
            case .rgb:
                message += [0x03, index, UInt8((color >> 14) & 0x7F), UInt8((color >> 7) & 0x7F), UInt8(color & 0x7F)]
            }
        }
        
        message.append(0xF7)
        sendBytes(message)
        print("[MIDI] SysEx LED batch: \(updates.count) LEDs")
    }
    
    /// Clear all LEDs using SysEx batch
    public func clearAllLeds() {
        guard isConnected else { return }
        
        var updates: [(padId: ButtonId, color: Int, mode: LedMode)] = []
        
        // Grid 8x8
        for y in 0..<8 {
            for x in 0..<8 {
                updates.append((ButtonId(x: x, y: y), LP.off, .solid))
            }
        }
        // Top row
        for x in 0..<8 {
            updates.append((ButtonId(x: x, y: -1), LP.off, .solid))
        }
        // Scene buttons
        for y in 0..<8 {
            updates.append((ButtonId(x: 8, y: y), LP.off, .solid))
        }
        
        setLeds(updates)
    }
    
    // MARK: - Receive
    
    private func handleMIDIEvents(_ eventList: UnsafePointer<MIDIEventList>) {
        let packet = eventList.pointee.packet
        let word = packet.words.0
        
        // Parse MIDI 1.0 Channel Voice Message in UMP format:
        // Bits 28-31: Message Type (0x2 for MIDI 1.0 CV)
        // Bits 24-27: Group
        // Bits 20-23: Status/Opcode (0x9=NoteOn, 0x8=NoteOff, 0xB=CC)
        // Bits 16-19: Channel
        // Bits 8-15: Data1 (note/controller)
        // Bits 0-7: Data2 (velocity/value)
        
        let umpType = (word >> 28) & 0xF
        let status = (word >> 20) & 0xF
        let channel = Int((word >> 16) & 0xF)
        let data1 = Int((word >> 8) & 0x7F)
        let data2 = Int(word & 0x7F)
        
        // Debug: log raw MIDI receive
        if umpType == 0x2 {  // MIDI 1.0 Channel Voice
            print("[MIDI] RX: type=\(umpType) status=\(String(format: "0x%X", status)) ch=\(channel) d1=\(data1) d2=\(data2)")
        }
        
        let message: MIDIMessage?
        
        // Only process MIDI 1.0 Channel Voice Messages (UMP type 0x2)
        if umpType == 0x2 {
            switch status {
            case 0x9:  // Note On
                message = .noteOn(channel: channel, note: data1, velocity: data2)
            case 0x8:  // Note Off
                message = .noteOff(channel: channel, note: data1, velocity: data2)
            case 0xB:  // Control Change
                message = .controlChange(channel: channel, controller: data1, value: data2)
            default:
                message = nil
            }
        } else {
            message = nil
        }
        
        if let message, let callback = messageCallback {
            callbackQueue.async {
                callback(message)
            }
        }
    }
    
    // MARK: - Helpers
    
    static func getStringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var string: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, property, &string)
        
        if status == noErr, let cfString = string?.takeRetainedValue() {
            return cfString as String
        }
        return nil
    }
}

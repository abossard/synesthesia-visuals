// MIDIManager.swift - CoreMIDI wrapper for Launchpad
// Phase 5: MIDI Controller
//
// Deep module hiding CoreMIDI complexity behind simple interface

import Foundation
import CoreMIDI

/// MIDI device info
public struct MIDIDeviceInfo: Identifiable, Sendable {
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
}

/// MIDI message type
public enum MIDIMessage: Sendable {
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int, velocity: Int)
    case controlChange(channel: Int, controller: Int, value: Int)
    
    /// Convert note to ButtonId (Launchpad Programmer mode)
    public var buttonId: ButtonId? {
        switch self {
        case .noteOn(_, let note, _), .noteOff(_, let note, _):
            return ButtonId(midiNote: note)
        default:
            return nil
        }
    }
    
    /// Whether this is a press (noteOn with velocity > 0)
    public var isPress: Bool {
        if case .noteOn(_, _, let velocity) = self {
            return velocity > 0
        }
        return false
    }
    
    /// Whether this is a release (noteOff or noteOn with velocity 0)
    public var isRelease: Bool {
        switch self {
        case .noteOff:
            return true
        case .noteOn(_, _, let velocity):
            return velocity == 0
        default:
            return false
        }
    }
}

/// Callback for MIDI messages
public typealias MIDIMessageCallback = @Sendable (MIDIMessage) -> Void

/// CoreMIDI wrapper for device discovery and communication
public final class MIDIManager: @unchecked Sendable {
    
    // MARK: - Properties
    
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var connectedInput: MIDIEndpointRef = 0
    private var connectedOutput: MIDIEndpointRef = 0
    
    private var messageCallback: MIDIMessageCallback?
    private let callbackQueue = DispatchQueue(label: "midi.callback", qos: .userInteractive)
    
    /// Current connection status
    public private(set) var isConnected = false
    
    /// Name of connected device
    public private(set) var connectedDeviceName: String?
    
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
        MIDIInputPortCreateWithProtocol(
            client,
            "Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, _ in
            self?.handleMIDIEvents(eventList)
        }
        
        // Create output port
        MIDIOutputPortCreate(client, "Output" as CFString, &outputPort)
    }
    
    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged:
            print("[MIDI] Setup changed")
        case .msgObjectAdded:
            print("[MIDI] Device added")
        case .msgObjectRemoved:
            print("[MIDI] Device removed")
            // Check if our device was removed
            if isConnected && !isEndpointValid(connectedInput) {
                disconnect()
            }
        default:
            break
        }
    }
    
    private func isEndpointValid(_ endpoint: MIDIEndpointRef) -> Bool {
        var name: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        return status == noErr
    }
    
    // MARK: - Device Discovery
    
    /// Get all available MIDI input devices
    public func availableInputs() -> [MIDIDeviceInfo] {
        var devices: [MIDIDeviceInfo] = []
        let sourceCount = MIDIGetNumberOfSources()
        
        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)
            devices.append(MIDIDeviceInfo(endpoint: endpoint))
        }
        
        return devices
    }
    
    /// Get all available MIDI output devices
    public func availableOutputs() -> [MIDIDeviceInfo] {
        var devices: [MIDIDeviceInfo] = []
        let destCount = MIDIGetNumberOfDestinations()
        
        for i in 0..<destCount {
            let endpoint = MIDIGetDestination(i)
            devices.append(MIDIDeviceInfo(endpoint: endpoint))
        }
        
        return devices
    }
    
    /// Find first Launchpad device
    public func findLaunchpad() -> (input: MIDIDeviceInfo, output: MIDIDeviceInfo)? {
        let inputs = availableInputs().filter { $0.isLaunchpad }
        let outputs = availableOutputs().filter { $0.isLaunchpad }
        
        guard let input = inputs.first, let output = outputs.first else {
            return nil
        }
        
        return (input, output)
    }
    
    // MARK: - Connection
    
    /// Connect to a MIDI device pair
    public func connect(input: MIDIDeviceInfo, output: MIDIDeviceInfo, callback: @escaping MIDIMessageCallback) -> Bool {
        disconnect()
        
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
        
        print("[MIDI] Connected to \(input.name)")
        return true
    }
    
    /// Connect to first available Launchpad
    public func connectToLaunchpad(callback: @escaping MIDIMessageCallback) -> Bool {
        guard let (input, output) = findLaunchpad() else {
            print("[MIDI] No Launchpad found")
            return false
        }
        
        return connect(input: input, output: output, callback: callback)
    }
    
    /// Disconnect from current device
    public func disconnect() {
        if connectedInput != 0 {
            MIDIPortDisconnectSource(inputPort, connectedInput)
        }
        
        connectedInput = 0
        connectedOutput = 0
        connectedDeviceName = nil
        messageCallback = nil
        isConnected = false
    }
    
    // MARK: - Send
    
    /// Send a note on message
    public func sendNoteOn(channel: Int, note: Int, velocity: Int) {
        guard isConnected, connectedOutput != 0 else { return }
        
        var packet = MIDIEventPacket()
        packet.timeStamp = 0
        packet.wordCount = 1
        packet.words.0 = UInt32(0x20900000) | UInt32((channel & 0xF) << 16) | UInt32((note & 0x7F) << 8) | UInt32(velocity & 0x7F)
        
        withUnsafePointer(to: packet) { packetPtr in
            var list = MIDIEventList()
            list.protocol = ._1_0
            list.numPackets = 1
            
            withUnsafeMutablePointer(to: &list.packet) { listPacketPtr in
                listPacketPtr.pointee = packetPtr.pointee
            }
            
            MIDISendEventList(outputPort, connectedOutput, &list)
        }
    }
    
    /// Send a note off message
    public func sendNoteOff(channel: Int, note: Int, velocity: Int = 0) {
        guard isConnected, connectedOutput != 0 else { return }
        
        var packet = MIDIEventPacket()
        packet.timeStamp = 0
        packet.wordCount = 1
        packet.words.0 = UInt32(0x20800000) | UInt32((channel & 0xF) << 16) | UInt32((note & 0x7F) << 8) | UInt32(velocity & 0x7F)
        
        withUnsafePointer(to: packet) { packetPtr in
            var list = MIDIEventList()
            list.protocol = ._1_0
            list.numPackets = 1
            
            withUnsafeMutablePointer(to: &list.packet) { listPacketPtr in
                listPacketPtr.pointee = packetPtr.pointee
            }
            
            MIDISendEventList(outputPort, connectedOutput, &list)
        }
    }
    
    /// Set LED color on Launchpad pad
    public func setLed(padId: ButtonId, color: Int) {
        sendNoteOn(channel: 0, note: padId.midiNote, velocity: color)
    }
    
    /// Clear all LEDs
    public func clearAllLeds() {
        for y in 0..<8 {
            for x in 0..<9 {  // Include scene buttons
                let padId = ButtonId(x: x, y: y)
                setLed(padId: padId, color: LP.off)
            }
        }
    }
    
    // MARK: - Receive
    
    private func handleMIDIEvents(_ eventList: UnsafePointer<MIDIEventList>) {
        let packet = eventList.pointee.packet
        let word = packet.words.0
        
        // Parse MIDI 1.0 message
        let messageType = (word >> 20) & 0xF
        let channel = Int((word >> 16) & 0xF)
        let data1 = Int((word >> 8) & 0x7F)
        let data2 = Int(word & 0x7F)
        
        let message: MIDIMessage?
        
        switch messageType {
        case 0x9:  // Note On
            message = .noteOn(channel: channel, note: data1, velocity: data2)
        case 0x8:  // Note Off
            message = .noteOff(channel: channel, note: data1, velocity: data2)
        case 0xB:  // Control Change
            message = .controlChange(channel: channel, controller: data1, value: data2)
        default:
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

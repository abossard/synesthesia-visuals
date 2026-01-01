import Foundation
import Network

/// Simple OSC server implementation
/// TODO: Replace with full SwiftOSC library once SPM support is available
class OSCServer {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    private var handlers: [String: (OSCMessage) -> Void] = [:]
    
    init(port: Int) {
        self.port = NWEndpoint.Port(integerLiteral: UInt16(port))
    }
    
    func setHandler(_ address: String, handler: @escaping (OSCMessage) -> Void) {
        handlers[address] = handler
    }
    
    func start() throws {
        let parameters = NWParameters.udp
        listener = try NWListener(using: parameters, on: port)
        
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("OSC server ready on port \(self.port)")
            case .failed(let error):
                NSLog("OSC server failed: \(error)")
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        
        listener?.start(queue: .main)
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        
        connection.receiveMessage { [weak self] (data, context, isComplete, error) in
            if let data = data, !data.isEmpty {
                self?.parseOSCPacket(data)
            }
            
            // Continue receiving on this connection
            if error == nil && !isComplete {
                self?.handleConnection(connection)
            }
        }
    }
    
    private func parseOSCPacket(_ data: Data) {
        // Basic OSC message parsing
        // Format: address (null-terminated string) + type tag + arguments
        
        var offset = 0
        
        // Parse address
        guard let addressEnd = data[offset...].firstIndex(of: 0) else {
            NSLog("Invalid OSC message: no address terminator")
            return
        }
        
        guard let address = String(data: data[offset..<addressEnd], encoding: .utf8) else {
            NSLog("Invalid OSC address encoding")
            return
        }
        
        // Align to 4-byte boundary
        offset = ((addressEnd + 1) + 3) & ~3
        
        // Parse type tag (starts with ',')
        guard offset < data.count, data[offset] == UInt8(ascii: ",") else {
            NSLog("Invalid OSC type tag")
            return
        }
        
        offset += 1
        let typeTagStart = offset
        
        guard let typeTagEnd = data[offset...].firstIndex(of: 0) else {
            NSLog("Invalid OSC type tag terminator")
            return
        }
        
        let typeTags = data[typeTagStart..<typeTagEnd]
        offset = (typeTagEnd + 3) & ~3
        
        // Parse arguments based on type tags
        var arguments: [Any] = []
        
        for typeTag in typeTags {
            switch typeTag {
            case UInt8(ascii: "i"):  // int32
                guard offset + 4 <= data.count else { break }
                let value = data[offset..<offset+4].withUnsafeBytes {
                    $0.load(as: Int32.self).bigEndian
                }
                arguments.append(value)
                offset += 4
                
            case UInt8(ascii: "f"):  // float32
                guard offset + 4 <= data.count else { break }
                let bytes = data[offset..<offset+4].withUnsafeBytes {
                    $0.load(as: UInt32.self).bigEndian
                }
                let value = Float(bitPattern: bytes)
                arguments.append(value)
                offset += 4
                
            case UInt8(ascii: "s"):  // string
                guard let stringEnd = data[offset...].firstIndex(of: 0) else { break }
                if let string = String(data: data[offset..<stringEnd], encoding: .utf8) {
                    arguments.append(string)
                }
                offset = (stringEnd + 3) & ~3
                
            default:
                NSLog("Unsupported OSC type tag: \(UnicodeScalar(typeTag))")
            }
        }
        
        // Dispatch to handler
        let message = OSCMessage(address: address, arguments: arguments)
        DispatchQueue.main.async {
            self.handlers[address]?(message)
        }
    }
}

struct OSCMessage {
    let address: String
    let arguments: [Any]
}

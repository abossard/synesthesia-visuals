import Foundation
import Network

class OSCSender {
    private var connection: NWConnection?
    private var host: String = "127.0.0.1"
    private var port: UInt16 = 9000
    
    func configure(host: String, port: UInt16) {
        self.host = host
        self.port = port
        setupConnection()
    }
    
    private func setupConnection() {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        connection = NWConnection(to: endpoint, using: .udp)
        connection?.start(queue: .global())
    }
    
    func send(result: DetectionResult) {
        guard let connection = connection else { return }
        
        // Send deck 1 info
        if let artist = result.deck1.artist, let title = result.deck1.title {
            let elapsed = result.deck1.elapsedSeconds ?? 0
            let fader = result.deck1.faderKnobPos ?? 0.5
            let msg = encodeOSC(
                address: "/vdj/deck1",
                args: [artist, title, elapsed, fader]
            )
            connection.send(content: msg, completion: .idempotent)
        }
        
        // Send deck 2 info
        if let artist = result.deck2.artist, let title = result.deck2.title {
            let elapsed = result.deck2.elapsedSeconds ?? 0
            let fader = result.deck2.faderKnobPos ?? 0.5
            let msg = encodeOSC(
                address: "/vdj/deck2",
                args: [artist, title, elapsed, fader]
            )
            connection.send(content: msg, completion: .idempotent)
        }
        
        // Send master deck
        if let master = result.masterDeck {
            let msg = encodeOSC(address: "/vdj/master", args: [master])
            connection.send(content: msg, completion: .idempotent)
        }
        
        // Send performance metrics
        let d1Confidence = result.deck1.faderConfidence ?? 0
        let d2Confidence = result.deck2.faderConfidence ?? 0
        let perfMsg = encodeOSC(
            address: "/vdj/performance",
            args: [d1Confidence, d2Confidence]
        )
        connection.send(content: perfMsg, completion: .idempotent)
    }
    
    // Minimal OSC encoder - supports strings, ints, floats
    private func encodeOSC(address: String, args: [Any]) -> Data {
        var data = Data()
        
        // Address (null-terminated, 4-byte aligned)
        let addrBytes = address.data(using: .utf8)! + Data([0])
        data.append(addrBytes)
        data.append(padding(addrBytes.count))
        
        // Type tag string
        var tags = ","
        for arg in args {
            switch arg {
            case is String: tags += "s"
            case is Int: tags += "i"
            case is Float, is Double: tags += "f"
            default: tags += "s"
            }
        }
        let tagBytes = tags.data(using: .utf8)! + Data([0])
        data.append(tagBytes)
        data.append(padding(tagBytes.count))
        
        // Arguments
        for arg in args {
            if let s = arg as? String {
                let sBytes = s.data(using: .utf8)! + Data([0])
                data.append(sBytes)
                data.append(padding(sBytes.count))
            } else if let i = arg as? Int {
                var value = Int32(i).bigEndian
                data.append(Data(bytes: &value, count: 4))
            } else if let f = arg as? Float {
                var value = f.bitPattern.bigEndian
                data.append(Data(bytes: &value, count: 4))
            } else if let d = arg as? Double {
                let f = Float(d)
                var value = f.bitPattern.bigEndian
                data.append(Data(bytes: &value, count: 4))
            }
        }
        
        return data
    }
    
    private func padding(_ count: Int) -> Data {
        let remainder = count % 4
        if remainder == 0 { return Data() }
        return Data(repeating: 0, count: 4 - remainder)
    }
}

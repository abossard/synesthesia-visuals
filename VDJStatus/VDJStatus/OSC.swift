import Foundation
import Network

/// Snapshot of deck state for change detection
private struct DeckSnapshot: Equatable {
    let artist: String
    let title: String
    let elapsedBucket: Int  // elapsed in 1-second buckets
    let faderBucket: Int    // fader in 5% buckets
    let playState: Int      // 0=unknown, 1=playing, 2=stopped
    
    init(deck: DeckDetection, playState: Int = 0) {
        self.artist = deck.artist ?? ""
        self.title = deck.title ?? ""
        self.elapsedBucket = Int((deck.elapsedSeconds ?? 0).rounded())
        self.faderBucket = Int(((deck.faderKnobPos ?? 0.5) * 20).rounded())  // 5% buckets
        self.playState = playState
    }
}

/// Snapshot of full state for change detection
private struct StateSnapshot: Equatable {
    let deck1: DeckSnapshot
    let deck2: DeckSnapshot
    let masterDeck: Int  // 0=none, 1, 2
}

class OSCSender {
    private var connection: NWConnection?
    private var host: String = "127.0.0.1"
    private var port: UInt16 = 9000
    
    // Rate limiting: max 1 Hz, skip if unchanged
    private var lastSendTime: Date = .distantPast
    private var lastSnapshot: StateSnapshot?
    private let minInterval: TimeInterval = 1.0  // 1 Hz max
    
    // Play state tracking (provided by caller via DeckStateManager)
    var deck1PlayState: Int = 0  // 0=unknown, 1=playing, 2=stopped
    var deck2PlayState: Int = 0
    
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
        
        // Build current snapshot for change detection
        let currentSnapshot = StateSnapshot(
            deck1: DeckSnapshot(deck: result.deck1, playState: deck1PlayState),
            deck2: DeckSnapshot(deck: result.deck2, playState: deck2PlayState),
            masterDeck: result.masterDeck ?? 0
        )
        
        // Rate limiting: check interval AND changes
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSendTime)
        
        if elapsed < minInterval {
            return  // Too soon
        }
        
        if let last = lastSnapshot, last == currentSnapshot {
            return  // Nothing changed
        }
        
        // Update tracking
        lastSendTime = now
        lastSnapshot = currentSnapshot
        
        // Send deck 1 info: /vdj/deck/1 [artist, title, elapsed, fader, playState]
        sendDeckMessage(connection: connection, deckNum: 1, deck: result.deck1, playState: deck1PlayState)
        
        // Send deck 2 info: /vdj/deck/2 [artist, title, elapsed, fader, playState]
        sendDeckMessage(connection: connection, deckNum: 2, deck: result.deck2, playState: deck2PlayState)
        
        // Send aggregated master: /vdj/master [artist, title, elapsed, fader, activeDeck]
        sendMasterMessage(connection: connection, result: result)
        
        // Send status: /vdj/status [d1PlayState, d2PlayState, masterDeck, d1Confidence, d2Confidence]
        sendStatusMessage(connection: connection, result: result)
    }
    
    private func sendDeckMessage(connection: NWConnection, deckNum: Int, deck: DeckDetection, playState: Int) {
        let artist = deck.artist ?? ""
        let title = deck.title ?? ""
        let elapsed = deck.elapsedSeconds ?? 0
        let fader = deck.faderKnobPos ?? 0.5
        
        let msg = encodeOSC(
            address: "/vdj/deck/\(deckNum)",
            args: [artist, title, elapsed, fader, playState]
        )
        connection.send(content: msg, completion: .idempotent)
    }
    
    private func sendMasterMessage(connection: NWConnection, result: DetectionResult) {
        let masterDeck = result.masterDeck ?? 0
        let deck = masterDeck == 1 ? result.deck1 : (masterDeck == 2 ? result.deck2 : nil)
        
        let artist = deck?.artist ?? ""
        let title = deck?.title ?? ""
        let elapsed = deck?.elapsedSeconds ?? 0
        let fader = deck?.faderKnobPos ?? 0.5
        
        let msg = encodeOSC(
            address: "/vdj/master",
            args: [artist, title, elapsed, fader, masterDeck]
        )
        connection.send(content: msg, completion: .idempotent)
    }
    
    private func sendStatusMessage(connection: NWConnection, result: DetectionResult) {
        let d1Confidence = result.deck1.faderConfidence ?? 0
        let d2Confidence = result.deck2.faderConfidence ?? 0
        let masterDeck = result.masterDeck ?? 0
        
        let msg = encodeOSC(
            address: "/vdj/status",
            args: [deck1PlayState, deck2PlayState, masterDeck, d1Confidence, d2Confidence]
        )
        connection.send(content: msg, completion: .idempotent)
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

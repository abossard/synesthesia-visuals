// VDJMonitor - Monitor VirtualDJ playback via OSC
// Following Grokking Simplicity: this is an action (side effects)

import Foundation
import OSCKit

/// Deck information from VirtualDJ
public struct VDJDeck: Sendable, Equatable {
    public let deckNumber: Int
    public let artist: String
    public let title: String
    public let album: String
    public let bpm: Double
    public let position: Double      // seconds
    public let duration: Double      // seconds
    public let isPlaying: Bool       // VDJ "play" state
    public let isAudible: Bool       // VDJ "is_audible" = playing AND volume up (KEY for deck selection!)
    public let isMaster: Bool
    public let volume: Double        // 0.0-1.0
    
    public init(
        deckNumber: Int,
        artist: String = "",
        title: String = "",
        album: String = "",
        bpm: Double = 0,
        position: Double = 0,
        duration: Double = 0,
        isPlaying: Bool = false,
        isAudible: Bool = false,
        isMaster: Bool = false,
        volume: Double = 1.0
    ) {
        self.deckNumber = deckNumber
        self.artist = artist
        self.title = title
        self.album = album
        self.bpm = bpm
        self.position = position
        self.duration = duration
        self.isPlaying = isPlaying
        self.isAudible = isAudible
        self.isMaster = isMaster
        self.volume = volume
    }
    
    /// Track key for change detection
    public var trackKey: String {
        "\(artist.lowercased())|\(title.lowercased())"
    }
    
    /// Check if deck has a track loaded (artist OR title - matching Python)
    public var hasTrack: Bool {
        !artist.isEmpty || !title.isEmpty
    }
}

/// VirtualDJ playback state (both decks)
public struct VDJPlayback: Sendable, Equatable {
    public let deck1: VDJDeck
    public let deck2: VDJDeck
    public let masterBPM: Double
    public let crossfader: Double  // -1.0 (left) to 1.0 (right)
    
    public init(
        deck1: VDJDeck = VDJDeck(deckNumber: 1),
        deck2: VDJDeck = VDJDeck(deckNumber: 2),
        masterBPM: Double = 0,
        crossfader: Double = 0
    ) {
        self.deck1 = deck1
        self.deck2 = deck2
        self.masterBPM = masterBPM
        self.crossfader = crossfader
    }
    
    /// Get the currently audible deck - the LOUDER deck with a track
    /// Priority: isAudible flag → volume comparison → hasTrack fallback
    public var audibleDeck: VDJDeck? {
        // 1. Check is_audible first (VDJ: playing AND volume up) - if VDJ sends it
        if deck1.isAudible && !deck2.isAudible { return deck1 }
        if deck2.isAudible && !deck1.isAudible { return deck2 }
        
        // 2. Both have tracks? Pick the LOUDER one by volume
        //    This handles crossfade: louder deck = the one coming in
        if deck1.hasTrack && deck2.hasTrack {
            // Significant volume difference (>10%) → pick louder
            if deck2.volume > deck1.volume + 0.1 { return deck2 }
            if deck1.volume > deck2.volume + 0.1 { return deck1 }
            // Similar volume → prefer deck 1 (like Python)
            return deck1
        }
        
        // 3. Only one has a track
        if deck1.hasTrack && !deck2.hasTrack { return deck1 }
        if deck2.hasTrack && !deck1.hasTrack { return deck2 }
        
        // 3. Both have tracks or neither - prefer deck 1 (like Python)
        return deck1.hasTrack ? deck1 : nil
    }
}

/// Error types for VDJ monitoring
public enum VDJMonitorError: Error, Equatable {
    case vdjNotRunning
    case oscError(String)
    case timeout
}

/// Handler for VDJ track changes
public typealias VDJTrackHandler = @Sendable (VDJDeck) -> Void

/// Handler for VDJ position updates
public typealias VDJPositionHandler = @Sendable (Int, Double) -> Void  // deck, position

/// Monitor VirtualDJ playback via OSC subscriptions
/// 
/// VDJ sends OSC messages on these addresses:
/// - /deck/1/artist, /deck/1/title, /deck/1/album
/// - /deck/1/get_bpm, /deck/1/get_position, /deck/1/get_duration
/// - /deck/1/play, /deck/1/masterdeck, /deck/1/volume
/// - /crossfader, /masterdeck_bpm
public actor VDJMonitor {
    
    // MARK: - Configuration
    
    public static let vdjOSCPort: UInt16 = 9009
    
    // MARK: - State
    
    private var deck1: VDJDeck = VDJDeck(deckNumber: 1)
    private var deck2: VDJDeck = VDJDeck(deckNumber: 2)
    private var masterBPM: Double = 0
    private var crossfader: Double = 0
    
    // Position tracking for inferring audibility (Python: _last_pos, _last_pos_time)
    private var deck1LastPos: Double = 0
    private var deck2LastPos: Double = 0
    
    private let health: ServiceHealth
    private var lastUpdate: Date = .distantPast
    private var isSubscribed = false
    
    // Callbacks
    private var trackHandlers: [VDJTrackHandler] = []
    private var positionHandlers: [VDJPositionHandler] = []
    
    public init() {
        self.health = ServiceHealth(name: "VirtualDJ")
    }
    
    // MARK: - VDJ OSC Subscription Commands
    
    /// Deck subscriptions (VDJ pushes on change)
    private static let deckSubscriptions = [
        "get_title", "get_artist", "get_album", "get_key",
        "get_songlength", "get_bpm", "loaded"
    ]
    
    /// Global subscriptions
    private static let globalSubscriptions = [
        "crossfader"
    ]
    
    /// Deck queries (poll for current values)
    /// Include metadata fields since VDJ may not push on initial subscribe
    private static let deckQueries = [
        "get_title", "get_artist", "get_album", "get_bpm", "get_songlength",
        "song_pos", "volume", "is_audible", "play"
    ]
    
    /// Subscribe to VDJ OSC events via OSCHub
    /// Call this after wiring handleOSC to the hub
    public func subscribe(using hub: OSCHub) throws {
        guard !isSubscribed else { return }
        
        var sentCount = 0
        // Subscribe to discrete events (VDJ pushes these)
        for deck in [1, 2] {
            for verb in Self.deckSubscriptions {
                let addr = "/vdj/subscribe/deck/\(deck)/\(verb)"
                try hub.sendToVDJ(addr)
                sentCount += 1
            }
        }
        
        // Global subscriptions
        for verb in Self.globalSubscriptions {
            try hub.sendToVDJ("/vdj/subscribe/\(verb)")
            sentCount += 1
        }
        
        print("📤 VDJMonitor: sent \(sentCount) subscribe commands to VDJ port 9009")
        isSubscribed = true
    }
    
    /// Query VDJ for current state (poll)
    public func query(using hub: OSCHub) throws {
        for deck in [1, 2] {
            for verb in Self.deckQueries {
                try hub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
            }
        }
    }
    
    // MARK: - Public API
    
    /// Get current playback state
    public func getPlayback() -> VDJPlayback {
        VDJPlayback(
            deck1: deck1,
            deck2: deck2,
            masterBPM: masterBPM,
            crossfader: crossfader
        )
    }
    
    /// Get the currently audible track
    public func getAudibleTrack() -> VDJDeck? {
        getPlayback().audibleDeck
    }
    
    /// Subscribe to track changes
    public func onTrackChange(_ handler: @escaping VDJTrackHandler) {
        trackHandlers.append(handler)
    }
    
    /// Subscribe to position updates
    public func onPositionUpdate(_ handler: @escaping VDJPositionHandler) {
        positionHandlers.append(handler)
    }
    
    /// Process incoming OSC message from VDJ
    public func handleOSC(address: String, values: [any OSCValue]) {
        // Parse deck number from address
        guard let deckNum = parseDeckNumber(from: address) else {
            handleGlobalOSC(address: address, values: values)
            return
        }
        
        // Get first value - pass raw for proper boolean parsing
        let firstValue = values.first
        let stringValue = (firstValue as? String) ?? ""
        let floatValue = firstValue.flatMap { extractFloat(from: $0) } ?? 0
        let boolValue = extractBool(from: firstValue)
        
        // Update deck state based on address suffix
        let suffix = address.components(separatedBy: "/").last ?? ""
        updateDeckValue(deckNum: deckNum, suffix: suffix, stringValue: stringValue, floatValue: floatValue, boolValue: boolValue)
        
        lastUpdate = Date()
        Task { await health.markAvailable(message: "VDJ connected") }
    }
    
    /// Check if monitor is receiving data
    public func isReceiving() -> Bool {
        Date().timeIntervalSince(lastUpdate) < 5.0
    }
    
    /// Get service health status
    public func status() async -> [String: Any] {
        await health.status()
    }
    
    // MARK: - Private
    
    private func parseDeckNumber(from address: String) -> Int? {
        // Python: parts = address.split("/"), if parts[2] == "deck": deck_num = int(parts[3])
        // For /vdj/deck/2/is_audible: parts = ["", "vdj", "deck", "2", "is_audible"]
        // For /deck/2/is_audible: parts = ["", "deck", "2", "is_audible"]
        let parts = address.split(separator: "/").map { String($0) }
        
        // Find "deck" in parts and get the next element as deck number
        for (index, part) in parts.enumerated() {
            if part == "deck", index + 1 < parts.count {
                if let deckNum = Int(parts[index + 1]) {
                    return deckNum
                }
            }
        }
        return nil
    }
    
    private func handleGlobalOSC(address: String, values: [any OSCValue]) {
        let floatValue = values.first.flatMap { extractFloat(from: $0) } ?? 0
        
        switch address {
        case "/crossfader":
            crossfader = floatValue * 2 - 1  // Convert 0-1 to -1..1
        case "/masterdeck_bpm", "/master_bpm":
            masterBPM = floatValue
        default:
            break
        }
    }
    
    private func updateDeckValue(deckNum: Int, suffix: String, stringValue: String, floatValue: Double, boolValue: Bool) {
        let oldDeck = deckNum == 1 ? deck1 : deck2
        let oldTrackKey = oldDeck.trackKey
        let lastPos = deckNum == 1 ? deck1LastPos : deck2LastPos
        
        var deck = oldDeck
        
        switch suffix {
        case "artist", "get_artist":
            deck = VDJDeck(
                deckNumber: deckNum, artist: stringValue, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isAudible: deck.isAudible, isMaster: deck.isMaster, volume: deck.volume
            )
        case "title", "get_title":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: stringValue,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isAudible: deck.isAudible, isMaster: deck.isMaster, volume: deck.volume
            )
        case "album", "get_album":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: stringValue, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isAudible: deck.isAudible, isMaster: deck.isMaster, volume: deck.volume
            )
        case "get_bpm", "bpm":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: floatValue, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isAudible: deck.isAudible, isMaster: deck.isMaster, volume: deck.volume
            )
        case "get_position", "position", "song_pos":
            // song_pos comes as 0.0-1.0 ratio, convert to seconds using duration
            let positionInSeconds = floatValue <= 1.0 ? floatValue * deck.duration : floatValue
            
            // Python: Infer playing from position changing (VDJ doesn't always send play state)
            let positionChanged = abs(floatValue - lastPos) > 0.001
            var inferredPlaying = deck.isPlaying
            var inferredAudible = deck.isAudible
            
            if positionChanged {
                inferredPlaying = true  // Position changed = playing
                inferredAudible = deck.volume > 0.1  // Infer audible from volume
                // Update last pos
                if deckNum == 1 { deck1LastPos = floatValue } else { deck2LastPos = floatValue }
            }
            
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: positionInSeconds,
                duration: deck.duration, isPlaying: inferredPlaying,
                isAudible: inferredAudible, isMaster: deck.isMaster, volume: deck.volume
            )
            // Notify position handlers
            for handler in positionHandlers {
                handler(deckNum, positionInSeconds)
            }
        case "get_duration", "duration", "get_songlength", "songlength":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: floatValue, isPlaying: deck.isPlaying,
                isAudible: deck.isAudible, isMaster: deck.isMaster, volume: deck.volume
            )
        case "play":
            // VDJ sends "1" for playing, "" for stopped - use boolValue (Python-style parsing)
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: boolValue,
                isAudible: deck.isAudible, isMaster: deck.isMaster, volume: deck.volume
            )
        case "is_audible":
            // VDJ "is_audible" = playing AND volume up - use boolValue (Python-style parsing)
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isAudible: boolValue, isMaster: deck.isMaster, volume: deck.volume
            )
        case "masterdeck":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isAudible: deck.isAudible, isMaster: boolValue, volume: deck.volume
            )
        case "volume":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isAudible: deck.isAudible, isMaster: deck.isMaster, volume: floatValue
            )
        case "loaded":
            // Track loaded state using boolValue (Python-style parsing)
            return  // loaded doesn't update deck state directly
        default:
            return
        }
        
        // Store updated deck
        if deckNum == 1 {
            deck1 = deck
        } else {
            deck2 = deck
        }
        
        // Check for track change
        if deck.trackKey != oldTrackKey && deck.hasTrack {
            for handler in trackHandlers {
                handler(deck)
            }
        }
    }
    
    private func extractFloat(from value: any OSCValue) -> Double? {
        if let f = value as? Float32 { return Double(f) }
        if let f = value as? Float64 { return f }
        if let i = value as? Int32 { return Double(i) }
        if let s = value as? String { return Double(s) }
        return nil
    }
    
    /// Parse boolean the way Python does: value not in (None, "", 0, "0", False)
    /// VDJ sends "1" for true, "" for false - this handles all cases
    private func extractBool(from value: (any OSCValue)?) -> Bool {
        guard let value = value else { return false }
        
        // Check string values first (VDJ often sends "1" or "")
        if let s = value as? String {
            return !s.isEmpty && s != "0" && s.lowercased() != "false"
        }
        // Check numeric values
        if let f = value as? Float32 { return f != 0 }
        if let f = value as? Float64 { return f != 0 }
        if let i = value as? Int32 { return i != 0 }
        if let b = value as? Bool { return b }
        
        return false
    }
}

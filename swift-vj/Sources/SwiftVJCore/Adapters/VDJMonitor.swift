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
    public let isPlaying: Bool
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
        self.isMaster = isMaster
        self.volume = volume
    }
    
    /// Track key for change detection
    public var trackKey: String {
        "\(artist.lowercased())|\(title.lowercased())"
    }
    
    /// Check if deck has a track loaded
    public var hasTrack: Bool {
        !artist.isEmpty && !title.isEmpty
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
    
    /// Get the currently audible deck (master or crossfader-based)
    public var audibleDeck: VDJDeck? {
        // First check for master flag
        if deck1.isMaster && deck1.isPlaying { return deck1 }
        if deck2.isMaster && deck2.isPlaying { return deck2 }
        
        // Fall back to crossfader position
        if crossfader < -0.5 && deck1.isPlaying { return deck1 }
        if crossfader > 0.5 && deck2.isPlaying { return deck2 }
        
        // If crossfader is centered, pick any playing deck
        if deck1.isPlaying { return deck1 }
        if deck2.isPlaying { return deck2 }
        
        // Last resort: any deck with a track (for testing when VDJ doesn't send play state)
        if deck1.hasTrack { return deck1 }
        if deck2.hasTrack { return deck2 }
        
        return nil
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
        var queryCount = 0
        for deck in [1, 2] {
            for verb in Self.deckQueries {
                try hub.sendToVDJ("/vdj/query/deck/\(deck)/\(verb)")
                queryCount += 1
            }
        }
        print("📤 VDJMonitor: sent \(queryCount) query commands to VDJ")
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
        
        // Get first value as string or float
        let stringValue = values.first.flatMap { $0 as? String } ?? ""
        let floatValue = values.first.flatMap { extractFloat(from: $0) } ?? 0
        
        // Update deck state based on address suffix
        let suffix = address.components(separatedBy: "/").last ?? ""
        updateDeckValue(deckNum: deckNum, suffix: suffix, stringValue: stringValue, floatValue: floatValue)
        
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
        // Match /vdj/deck/1/... or /deck/1/...
        if address.hasPrefix("/vdj/deck/1/") || address.hasPrefix("/deck/1/") { return 1 }
        if address.hasPrefix("/vdj/deck/2/") || address.hasPrefix("/deck/2/") { return 2 }
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
    
    private func updateDeckValue(deckNum: Int, suffix: String, stringValue: String, floatValue: Double) {
        let oldDeck = deckNum == 1 ? deck1 : deck2
        let oldTrackKey = oldDeck.trackKey
        
        var deck = oldDeck
        
        switch suffix {
        case "artist", "get_artist":
            deck = VDJDeck(
                deckNumber: deckNum, artist: stringValue, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isMaster: deck.isMaster, volume: deck.volume
            )
        case "title", "get_title":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: stringValue,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isMaster: deck.isMaster, volume: deck.volume
            )
        case "album", "get_album":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: stringValue, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isMaster: deck.isMaster, volume: deck.volume
            )
        case "get_bpm", "bpm":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: floatValue, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isMaster: deck.isMaster, volume: deck.volume
            )
        case "get_position", "position", "song_pos":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: floatValue,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isMaster: deck.isMaster, volume: deck.volume
            )
            // Notify position handlers
            for handler in positionHandlers {
                handler(deckNum, floatValue)
            }
        case "get_duration", "duration", "get_songlength", "songlength":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: floatValue, isPlaying: deck.isPlaying,
                isMaster: deck.isMaster, volume: deck.volume
            )
        case "play", "is_audible":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: floatValue > 0.5,
                isMaster: deck.isMaster, volume: deck.volume
            )
        case "masterdeck":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isMaster: floatValue > 0.5, volume: deck.volume
            )
        case "volume":
            deck = VDJDeck(
                deckNumber: deckNum, artist: deck.artist, title: deck.title,
                album: deck.album, bpm: deck.bpm, position: deck.position,
                duration: deck.duration, isPlaying: deck.isPlaying,
                isMaster: deck.isMaster, volume: floatValue
            )
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
}

// OSCHub - Central OSC communication adapter
// Following Grokking Simplicity: this is an action (side effects)
// Renamed to OSCHub to avoid conflict with OSCKit's OSCClient

import Foundation
import OSCKit

/// OSC message handler type
public typealias OSCMessageHandler = @Sendable (String, [any OSCValue]) -> Void
public typealias OSCOutgoingMessageHandler = @Sendable (String, String, [OscArg], String?) -> Void

/// Error types for OSC operations
public enum OSCHubError: Error, Equatable {
    case notStarted
    case sendFailed(String)
    case serverFailed(String)
}

/// Pattern match classification
private enum PatternMatch {
    case any       // "*" or "/" or ""
    case exact     // "/exact/path"
    case prefix    // "/prefix*" -> stored in trie as "/prefix"
}

/// Latency statistics for OSC processing
public struct OSCLatencyStats: Sendable {
    public let averageMs: Double
    public let maxMs: Double
    public let sampleCount: Int
    
    public init(averageMs: Double = 0, maxMs: Double = 0, sampleCount: Int = 0) {
        self.averageMs = averageMs
        self.maxMs = maxMs
        self.sampleCount = sampleCount
    }
}

/// Central OSC hub managing send and receive
///
/// Architecture:
/// - Receive ports: 9999 (Synesthesia), 9010 (VDJ responses)
/// - Forwards received messages to: Magic (11111)
/// - Send channels: VDJ (9009), Synesthesia (7777), Magic (11111)
/// - Uses PrefixTrie for O(n) pattern matching
/// - Tracks latency for monitoring
///
/// Note: Named "OSCHub" to avoid conflict with OSCKit's OSCClient class
public final class OSCHub: @unchecked Sendable {

    // MARK: - Configuration

    /// Default ports from Config
    public static let defaultReceivePort: UInt16 = Config.oscReceivePort        // Synesthesia audio
    public static let defaultVdjReceivePort: UInt16 = 9010    // VDJ responses
    public static let defaultVdjPort: UInt16 = Config.oscVDJPort           // Send to VDJ
    public static let defaultSynesthesiaPort: UInt16 = Config.oscSynesthesiaPort
    public static let defaultMagicPort: UInt16 = Config.oscMagicPort

    public enum PortKeys {
        public static let receivePort = "osc_receive_port"
        public static let vdjPort = "osc_vdj_port"
        public static let synesthesiaPort = "osc_synesthesia_port"
        public static let magicPort = "osc_magic_port"
        public static let vdjReceivePort = "osc_vdj_receive_port"
    }

    private static func loadPort(from defaults: UserDefaults, key: String, fallback: UInt16) -> UInt16 {
        let value = defaults.integer(forKey: key)
        guard value > 0 && value <= UInt16.max else { return fallback }
        return UInt16(value)
    }

    /// Forward targets for received messages (Magic only - Swift VJ handles rendering directly)
    private let forwardTargets: [(host: String, port: UInt16)]

    // MARK: - Ports (configured at init)

    public let receivePort: UInt16
    public let vdjReceivePort: UInt16
    public let vdjPort: UInt16
    public let synesthesiaPort: UInt16
    public let magicPort: UInt16

    // MARK: - State

    // Client bound to port 9999 so VDJ responses come back to us
    // (VDJ responds to the source port of subscribe requests)
    private var client: OSCUDPClient?
    private var server: OSCUDPServer?         // Port 9999 for Synesthesia
    private var vdjServer: OSCUDPServer?      // Port 9010 for VDJ responses
    private var isStarted = false

    // Subscriptions using PrefixTrie for O(n) pattern matching
    private let lock = NSLock()
    private var subscriptions: [String: [OSCMessageHandler]] = [:]
    private var anyHandlers: [OSCMessageHandler] = []      // "*" or "/" patterns
    private var exactHandlers: [String: [OSCMessageHandler]] = [:]  // exact matches
    private let prefixTrie = PrefixTrie<[OSCMessageHandler]>()  // prefix matches
    private var subscriptionOrder: Int = 0

    // Stats (atomic via lock)
    private var messagesSent: Int = 0
    private var messagesReceived: Int = 0
    private var messagesForwarded: Int = 0

    /// Optional observer invoked after successful outgoing sends.
    public var outgoingMessageHandler: OSCOutgoingMessageHandler?
    
    // Latency monitoring
    private var latencyEnabled: Bool = false
    private var latencySum: Double = 0
    private var latencyMax: Double = 0
    private var latencyCount: Int = 0

    // MARK: - Lifecycle

    public init() {
        let defaults = UserDefaults.standard
        self.receivePort = Self.loadPort(from: defaults, key: PortKeys.receivePort, fallback: Self.defaultReceivePort)
        self.vdjPort = Self.loadPort(from: defaults, key: PortKeys.vdjPort, fallback: Self.defaultVdjPort)
        self.synesthesiaPort = Self.loadPort(from: defaults, key: PortKeys.synesthesiaPort, fallback: Self.defaultSynesthesiaPort)
        self.magicPort = Self.loadPort(from: defaults, key: PortKeys.magicPort, fallback: Self.defaultMagicPort)
        self.vdjReceivePort = Self.loadPort(from: defaults, key: PortKeys.vdjReceivePort, fallback: Self.defaultVdjReceivePort)
        self.forwardTargets = [
            ("127.0.0.1", self.magicPort)
        ]
    }

    /// Start the OSC client and server
    public func start() throws {
        guard !isStarted else { return }

        // Start server on port 9999 for Synesthesia audio
        let oscServer = OSCUDPServer(port: receivePort) { [weak self] message, timeTag, _, _ in
            Task { await self?.handleMessage(message, timeTag: timeTag) }
        }

        do {
            try oscServer.start()
            self.server = oscServer
        } catch {
            throw OSCHubError.serverFailed("Server start failed on port \(receivePort): \(error.localizedDescription)")
        }

        // Start VDJ server on port 9010 for VDJ responses
        let vdjOscServer = OSCUDPServer(port: vdjReceivePort) { [weak self] message, timeTag, _, _ in
            Task { await self?.handleMessage(message, timeTag: timeTag) }
        }

        do {
            try vdjOscServer.start()
            self.vdjServer = vdjOscServer
        } catch {
            oscServer.stop()
            throw OSCHubError.serverFailed("VDJ Server start failed on port \(vdjReceivePort): \(error.localizedDescription)")
        }

        // Start client for sending (no port binding needed)
        let oscClient = OSCUDPClient()
        do {
            try oscClient.start()
            self.client = oscClient
        } catch {
            oscServer.stop()
            vdjOscServer.stop()
            throw OSCHubError.sendFailed("Client start failed: \(error.localizedDescription)")
        }

        isStarted = true
    }

    /// Stop the OSC client and server
    public func stop() {
        guard isStarted else { return }

        client?.stop()
        client = nil
        server?.stop()
        server = nil
        vdjServer?.stop()
        vdjServer = nil
        isStarted = false
    }

    /// Whether the hub is running
    public var running: Bool {
        isStarted
    }

    // MARK: - Send Methods

    /// Send OSC message to VirtualDJ
    public func sendToVDJ(_ address: String, values: [any OSCValue] = [], source: String? = nil) throws {
        try send(address, values: values, host: "127.0.0.1", port: vdjPort, target: "vdj", source: source)
    }

    /// Send OSC message to Synesthesia
    public func sendToSynesthesia(_ address: String, values: [any OSCValue] = [], source: String? = nil) throws {
        try send(address, values: values, host: "127.0.0.1", port: synesthesiaPort, target: "synesthesia", source: source)
    }

    /// Send OSC message to Magic Music Visuals
    public func sendToMagic(_ address: String, values: [any OSCValue] = [], source: String? = nil) throws {
        try send(address, values: values, host: "127.0.0.1", port: magicPort, target: "magic", source: source)
    }

    /// Send OSC message to specific host and port
    public func send(
        _ address: String,
        values: [any OSCValue] = [],
        host: String,
        port: UInt16,
        target: String? = nil,
        source: String? = nil
    ) throws {
        guard isStarted else {
            throw OSCHubError.notStarted
        }

        let message = OSCMessage(address, values: values)
        guard let oscClient = client else {
            throw OSCHubError.notStarted
        }
        do {
            try oscClient.send(message, to: host, port: port)
            lock.withLock { messagesSent += 1 }
            let outgoingTarget = target ?? "custom"
            outgoingMessageHandler?(outgoingTarget, address, Self.mapOutgoingArgs(values), source)
        } catch {
            throw OSCHubError.sendFailed(error.localizedDescription)
        }
    }

    private static func mapOutgoingArgs(_ values: [any OSCValue]) -> [OscArg] {
        values.compactMap { value in
            if let int32 = value as? Int32 { return .int(Int(int32)) }
            if let int = value as? Int { return .int(int) }
            if let float32 = value as? Float32 { return .float(Float(float32)) }
            if let float = value as? Float { return .float(float) }
            if let double = value as? Double { return .float(Float(double)) }
            if let string = value as? String { return .string(string) }
            if let bool = value as? Bool { return .bool(bool) }
            return nil
        }
    }

    // MARK: - Subscribe Methods

    /// Subscribe to incoming OSC messages matching a pattern
    /// - Pattern: "*" matches all, "/prefix*" matches prefix, exact path for exact match
    /// - Uses PrefixTrie for O(n) prefix matching
    public func subscribe(pattern: String, handler: @escaping OSCMessageHandler) {
        lock.withLock {
            // Store in legacy subscriptions for backwards compat
            var handlers = subscriptions[pattern] ?? []
            handlers.append(handler)
            subscriptions[pattern] = handlers
            
            // Also store in optimized structures
            let classification = classifyPattern(pattern)
            switch classification {
            case .any:
                anyHandlers.append(handler)
            case .exact:
                var exactList = exactHandlers[pattern] ?? []
                exactList.append(handler)
                exactHandlers[pattern] = exactList
            case .prefix:
                let prefix = String(pattern.dropLast())  // Remove trailing *
                // Get existing handlers for this prefix or start fresh
                let prefixHandlers = [handler]
                // Note: PrefixTrie stores handlers at each prefix node
                prefixTrie.add(prefix, entry: PatternEntry(
                    order: subscriptionOrder,
                    pattern: pattern,
                    value: prefixHandlers
                ))
                subscriptionOrder += 1
            }
        }
    }

    /// Unsubscribe all handlers for a pattern
    public func unsubscribe(pattern: String) {
        lock.withLock {
            _ = subscriptions.removeValue(forKey: pattern)
            
            let classification = classifyPattern(pattern)
            switch classification {
            case .any:
                anyHandlers.removeAll()
            case .exact:
                exactHandlers.removeValue(forKey: pattern)
            case .prefix:
                let prefix = String(pattern.dropLast())
                prefixTrie.remove(prefix)
            }
        }
    }

    /// Clear all subscriptions
    public func clearSubscriptions() {
        lock.withLock {
            subscriptions.removeAll()
            anyHandlers.removeAll()
            exactHandlers.removeAll()
            prefixTrie.clear()
            subscriptionOrder = 0
        }
    }
    
    /// Classify a pattern for optimized matching
    private func classifyPattern(_ pattern: String) -> PatternMatch {
        if pattern.isEmpty || pattern == "*" || pattern == "/" {
            return .any
        }
        if pattern.hasSuffix("*") {
            return .prefix
        }
        return .exact
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: OSCMessage, timeTag: OSCTimeTag) async {
        let startTime = latencyEnabled ? CFAbsoluteTimeGetCurrent() : 0
        
        lock.withLock { messagesReceived += 1 }

        // Forward to all targets
        forwardMessage(message)

        // Dispatch to subscribed handlers (using optimized matching)
        dispatchMessageOptimized(message)
        
        // Track latency
        if latencyEnabled {
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0  // ms
            lock.withLock {
                latencySum += elapsed
                latencyCount += 1
                if elapsed > latencyMax {
                    latencyMax = elapsed
                }
            }
        }
    }

    private func forwardMessage(_ message: OSCMessage) {
        guard let oscClient = client else { return }
        for target in forwardTargets {
            do {
                try oscClient.send(message, to: target.host, port: target.port)
                lock.withLock { messagesForwarded += 1 }
            } catch {
                // Log error but don't stop processing
            }
        }
    }
    
    /// Optimized dispatch using PrefixTrie for O(n) matching
    private func dispatchMessageOptimized(_ message: OSCMessage) {
        let address = message.addressPattern.stringValue
        let values = message.values
        
        // Get snapshots under lock
        let (currentAny, currentExact) = lock.withLock {
            (anyHandlers, exactHandlers)
        }
        
        // 1. Call "any" handlers (match all messages)
        for handler in currentAny {
            handler(address, values)
        }
        
        // 2. Call exact match handlers
        if let handlers = currentExact[address] {
            for handler in handlers {
                handler(address, values)
            }
        }
        
        // 3. Call prefix match handlers via trie (O(address.length))
        let prefixMatches = prefixTrie.match(address)
        for entry in prefixMatches {
            for handler in entry.value {
                handler(address, values)
            }
        }
    }

    private func dispatchMessage(_ message: OSCMessage) {
        let address = message.addressPattern.stringValue
        let values = message.values

        let currentSubscriptions = lock.withLock { subscriptions }

        for (pattern, handlers) in currentSubscriptions {
            if matches(address: address, pattern: pattern) {
                for handler in handlers {
                    handler(address, values)
                }
            }
        }
    }

    /// Check if an address matches a subscription pattern
    private func matches(address: String, pattern: String) -> Bool {
        // "*" or "/" matches everything
        if pattern == "*" || pattern == "/" || pattern.isEmpty {
            return true
        }

        // Prefix match with wildcard
        if pattern.hasSuffix("*") {
            let prefix = String(pattern.dropLast())
            return address.hasPrefix(prefix)
        }

        // Exact match
        return address == pattern
    }

    // MARK: - Latency Monitoring
    
    /// Enable or disable latency monitoring
    public func setLatencyMonitoring(enabled: Bool) {
        lock.withLock {
            latencyEnabled = enabled
            if enabled {
                latencySum = 0
                latencyMax = 0
                latencyCount = 0
            }
        }
    }
    
    /// Get current latency statistics
    public func latencyStats() -> OSCLatencyStats {
        lock.withLock {
            let avg = latencyCount > 0 ? latencySum / Double(latencyCount) : 0
            return OSCLatencyStats(
                averageMs: avg,
                maxMs: latencyMax,
                sampleCount: latencyCount
            )
        }
    }
    
    /// Reset latency statistics
    public func resetLatencyStats() {
        lock.withLock {
            latencySum = 0
            latencyMax = 0
            latencyCount = 0
        }
    }

    // MARK: - Stats

    /// Get current statistics
    public func stats() -> [String: Any] {
        lock.withLock {
            var result: [String: Any] = [
                "running": isStarted,
                "receivePort": receivePort,
                "vdjReceivePort": vdjReceivePort,
                "messagesSent": messagesSent,
                "messagesReceived": messagesReceived,
                "messagesForwarded": messagesForwarded,
                "subscriptionCount": subscriptions.count
            ]
            
            // Include latency stats if enabled
            if latencyEnabled && latencyCount > 0 {
                result["latencyAvgMs"] = latencySum / Double(latencyCount)
                result["latencyMaxMs"] = latencyMax
                result["latencySamples"] = latencyCount
            }
            
            return result
        }
    }

    /// Reset statistics
    public func resetStats() {
        lock.withLock {
            messagesSent = 0
            messagesReceived = 0
            messagesForwarded = 0
            latencySum = 0
            latencyMax = 0
            latencyCount = 0
        }
    }
}

// MARK: - Convenience Extensions

public extension OSCHub {
    /// Send a simple string message to VDJ
    func sendToVDJ(_ address: String, _ stringValue: String) throws {
        try sendToVDJ(address, values: [stringValue])
    }

    /// Send a simple int message to VDJ
    func sendToVDJ(_ address: String, _ intValue: Int32) throws {
        try sendToVDJ(address, values: [intValue])
    }

    /// Send a simple float message to VDJ
    func sendToVDJ(_ address: String, _ floatValue: Float32) throws {
        try sendToVDJ(address, values: [floatValue])
    }
}

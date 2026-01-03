// OSCHub - Central OSC communication adapter
// Following Grokking Simplicity: this is an action (side effects)
// Renamed to OSCHub to avoid conflict with OSCKit's OSCClient

import Foundation
import OSCKit

/// OSC message handler type
public typealias OSCMessageHandler = @Sendable (String, [any OSCValue]) -> Void

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
/// - Single receive port: 9999 (all incoming OSC)
/// - Forwards received messages to: 10000 (Processing), 11111 (Magic)
/// - Send channels: VDJ (9009), Synesthesia (7777), Processing (10000)
/// - Uses PrefixTrie for O(n) pattern matching
/// - Tracks latency for monitoring
///
/// Note: Named "OSCHub" to avoid conflict with OSCKit's OSCClient class
public final class OSCHub: @unchecked Sendable {

    // MARK: - Configuration

    /// Default ports from Config
    public static let receivePort: UInt16 = 9999
    public static let vdjPort: UInt16 = 9009
    public static let synesthesiaPort: UInt16 = 7777
    public static let processingPort: UInt16 = 10000
    public static let magicPort: UInt16 = 11111

    /// Forward targets for received messages
    public static let forwardTargets: [(host: String, port: UInt16)] = [
        ("127.0.0.1", processingPort),
        ("127.0.0.1", magicPort)
    ]

    // MARK: - State

    // Client bound to port 9999 so VDJ responses come back to us
    // (VDJ responds to the source port of subscribe requests)
    private var client: OSCClient?
    private var server: OSCServer?
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
    
    // Latency monitoring
    private var latencyEnabled: Bool = false
    private var latencySum: Double = 0
    private var latencyMax: Double = 0
    private var latencyCount: Int = 0

    // MARK: - Lifecycle

    public init() {}

    /// Start the OSC client and server
    public func start() throws {
        guard !isStarted else { return }

        // Start server FIRST on receive port with port reuse enabled
        // OSCKit 0.6.x API: OSCServer with setHandler (no host/port in callback)
        let oscServer = OSCServer(port: Self.receivePort) { [weak self] message, timeTag in
            await self?.handleMessage(message, timeTag: timeTag)
        }
        oscServer.isPortReuseEnabled = true

        do {
            try oscServer.start()
            self.server = oscServer
        } catch {
            throw OSCHubError.serverFailed("Server start failed on port \(Self.receivePort): \(error.localizedDescription)")
        }

        // Start client bound to SAME port 9999 with port reuse
        // This ensures VDJ responds to port 9999 (not ephemeral port)
        let oscClient = OSCClient(localPort: Self.receivePort)
        oscClient.isPortReuseEnabled = true
        do {
            try oscClient.start()
            self.client = oscClient
        } catch {
            oscServer.stop()
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
        isStarted = false
    }

    /// Whether the hub is running
    public var running: Bool {
        isStarted
    }

    // MARK: - Send Methods

    /// Send OSC message to VirtualDJ
    public func sendToVDJ(_ address: String, values: [any OSCValue] = []) throws {
        try send(address, values: values, host: "127.0.0.1", port: Self.vdjPort)
    }

    /// Send OSC message to Synesthesia
    public func sendToSynesthesia(_ address: String, values: [any OSCValue] = []) throws {
        try send(address, values: values, host: "127.0.0.1", port: Self.synesthesiaPort)
    }

    /// Send OSC message to Processing/VJUniverse
    public func sendToProcessing(_ address: String, values: [any OSCValue] = []) throws {
        try send(address, values: values, host: "127.0.0.1", port: Self.processingPort)
    }

    /// Send OSC message to specific host and port
    public func send(_ address: String, values: [any OSCValue] = [], host: String, port: UInt16) throws {
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
        } catch {
            throw OSCHubError.sendFailed(error.localizedDescription)
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
        for target in Self.forwardTargets {
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
                "receivePort": Self.receivePort,
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

    /// Send a simple string message to Processing
    func sendToProcessing(_ address: String, _ stringValue: String) throws {
        try sendToProcessing(address, values: [stringValue])
    }
}

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

/// Central OSC hub managing send and receive
///
/// Architecture:
/// - Single receive port: 9999 (all incoming OSC)
/// - Forwards received messages to: 10000 (Processing), 11111 (Magic)
/// - Send channels: VDJ (9009), Synesthesia (7777), Processing (10000)
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

    // Subscriptions: pattern -> handlers (protected by lock)
    private let lock = NSLock()
    private var subscriptions: [String: [OSCMessageHandler]] = [:]

    // Stats (atomic via lock)
    private var messagesSent: Int = 0
    private var messagesReceived: Int = 0
    private var messagesForwarded: Int = 0

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
    public func subscribe(pattern: String, handler: @escaping OSCMessageHandler) {
        lock.withLock {
            var handlers = subscriptions[pattern] ?? []
            handlers.append(handler)
            subscriptions[pattern] = handlers
        }
    }

    /// Unsubscribe all handlers for a pattern
    public func unsubscribe(pattern: String) {
        lock.withLock { _ = subscriptions.removeValue(forKey: pattern) }
    }

    /// Clear all subscriptions
    public func clearSubscriptions() {
        lock.withLock { subscriptions.removeAll() }
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: OSCMessage, timeTag: OSCTimeTag) async {
        lock.withLock { messagesReceived += 1 }

        // Forward to all targets
        forwardMessage(message)

        // Dispatch to subscribed handlers
        dispatchMessage(message)
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

    // MARK: - Stats

    /// Get current statistics
    public func stats() -> [String: Any] {
        lock.withLock {
            [
                "running": isStarted,
                "receivePort": Self.receivePort,
                "messagesSent": messagesSent,
                "messagesReceived": messagesReceived,
                "messagesForwarded": messagesForwarded,
                "subscriptionCount": subscriptions.count
            ]
        }
    }

    /// Reset statistics
    public func resetStats() {
        lock.withLock {
            messagesSent = 0
            messagesReceived = 0
            messagesForwarded = 0
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

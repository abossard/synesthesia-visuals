// OSCClient - Central OSC communication adapter
// Following Grokking Simplicity: this is an action (side effects)

import Foundation
import OSCKit

/// OSC message handler type
public typealias OSCHandler = @Sendable (String, [any OSCValue]) -> Void

/// Error types for OSC operations
public enum OSCClientError: Error, Equatable {
    case notStarted
    case sendFailed(String)
    case serverFailed(String)
}

/// Central OSC client managing send and receive
///
/// Architecture:
/// - Single receive port: 9999 (all incoming OSC)
/// - Forwards received messages to: 10000 (Processing), 11111 (Magic)
/// - Send channels: VDJ (9009), Synesthesia (7777), Processing (10000)
public actor OSCClient {

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

    private let client = OSCUDPClient()
    private var server: OSCUDPServer?
    private var isStarted = false

    // Subscriptions: pattern -> handlers
    private var subscriptions: [String: [OSCHandler]] = [:]

    // Stats
    private var messagesSent: Int = 0
    private var messagesReceived: Int = 0
    private var messagesForwarded: Int = 0

    // MARK: - Lifecycle

    public init() {}

    /// Start the OSC client and server
    public func start() throws {
        guard !isStarted else { return }

        // Start client
        do {
            try client.start()
        } catch {
            throw OSCClientError.sendFailed("Client start failed: \(error.localizedDescription)")
        }

        // Start server on receive port
        let oscServer = OSCUDPServer(port: Self.receivePort)
        oscServer.setReceiveHandler { [weak self] message, timeTag, host, port in
            Task { [weak self] in
                await self?.handleMessage(message, timeTag: timeTag, host: host, port: port)
            }
        }

        do {
            try oscServer.start()
            self.server = oscServer
        } catch {
            client.stop()
            throw OSCClientError.serverFailed("Server start failed on port \(Self.receivePort): \(error.localizedDescription)")
        }

        isStarted = true
    }

    /// Stop the OSC client and server
    public func stop() {
        guard isStarted else { return }

        client.stop()
        server?.stop()
        server = nil
        isStarted = false
    }

    /// Whether the client is running
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
            throw OSCClientError.notStarted
        }

        let message = OSCMessage(address, values: values)
        do {
            try client.send(.message(message), to: host, port: port)
            messagesSent += 1
        } catch {
            throw OSCClientError.sendFailed(error.localizedDescription)
        }
    }

    // MARK: - Subscribe Methods

    /// Subscribe to incoming OSC messages matching a pattern
    /// - Pattern: "*" matches all, "/prefix*" matches prefix, exact path for exact match
    public func subscribe(pattern: String, handler: @escaping OSCHandler) {
        var handlers = subscriptions[pattern] ?? []
        handlers.append(handler)
        subscriptions[pattern] = handlers
    }

    /// Unsubscribe all handlers for a pattern
    public func unsubscribe(pattern: String) {
        subscriptions.removeValue(forKey: pattern)
    }

    /// Clear all subscriptions
    public func clearSubscriptions() {
        subscriptions.removeAll()
    }

    // MARK: - Message Handling

    private func handleMessage(_ message: OSCMessage, timeTag: OSCTimeTag, host: String, port: UInt16) {
        messagesReceived += 1

        // Forward to all targets
        forwardMessage(message)

        // Dispatch to subscribed handlers
        dispatchMessage(message)
    }

    private func forwardMessage(_ message: OSCMessage) {
        for target in Self.forwardTargets {
            do {
                try client.send(.message(message), to: target.host, port: target.port)
                messagesForwarded += 1
            } catch {
                // Log error but don't stop processing
            }
        }
    }

    private func dispatchMessage(_ message: OSCMessage) {
        let address = message.addressPattern.stringValue
        let values = message.values

        for (pattern, handlers) in subscriptions {
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
        [
            "running": isStarted,
            "receivePort": Self.receivePort,
            "messagesSent": messagesSent,
            "messagesReceived": messagesReceived,
            "messagesForwarded": messagesForwarded,
            "subscriptionCount": subscriptions.count
        ]
    }

    /// Reset statistics
    public func resetStats() {
        messagesSent = 0
        messagesReceived = 0
        messagesForwarded = 0
    }
}

// MARK: - Convenience Extensions

public extension OSCClient {
    /// Send a simple string message
    func sendToVDJ(_ address: String, _ stringValue: String) throws {
        try sendToVDJ(address, values: [stringValue])
    }

    /// Send a simple int message
    func sendToVDJ(_ address: String, _ intValue: Int32) throws {
        try sendToVDJ(address, values: [intValue])
    }

    /// Send a simple float message
    func sendToVDJ(_ address: String, _ floatValue: Float32) throws {
        try sendToVDJ(address, values: [floatValue])
    }

    /// Send a simple string message to Processing
    func sendToProcessing(_ address: String, _ stringValue: String) throws {
        try sendToProcessing(address, values: [stringValue])
    }
}

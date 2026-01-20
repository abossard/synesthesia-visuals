// WLEDAdapter - UDP transmission for WLED Sound Reactive
// Following A Philosophy of Software Design: deep module with simple interface
// Hides UDP socket complexity behind 2-3 public methods

import Foundation
import Network

/// Error types for WLED operations
public enum WLEDAdapterError: Error, LocalizedError {
    case connectionFailed(String)
    case sendFailed(String)
    case invalidHost(String)
    case notStarted
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "WLED connection failed: \(reason)"
        case .sendFailed(let reason):
            return "WLED send failed: \(reason)"
        case .invalidHost(let host):
            return "Invalid WLED host: \(host)"
        case .notStarted:
            return "WLED adapter not started"
        }
    }
}

/// Deep module for WLED UDP communication
/// Hides Network.framework complexity behind simple interface
///
/// Public interface (3 methods):
/// - start() - Initialize UDP connections
/// - send(packet, to: controller) - Send audio sync packet
/// - stop() - Clean shutdown
public actor WLEDAdapter {
    
    // MARK: - State
    
    private var connections: [String: NWConnection] = [:]
    private var isStarted = false
    
    // Stats
    private var packetsSent: Int = 0
    private var sendErrors: Int = 0
    private var lastSendTime: Date?
    
    // MARK: - Lifecycle
    
    public init() {}
    
    /// Start the adapter (prepare for sending)
    public func start() {
        guard !isStarted else { return }
        isStarted = true
    }
    
    /// Stop the adapter and close all connections
    public func stop() {
        guard isStarted else { return }
        
        // Close all connections
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        isStarted = false
    }
    
    // MARK: - Send Methods
    
    /// Send audio sync packet to a WLED controller
    /// - Parameters:
    ///   - packet: Audio sync packet to send
    ///   - controller: Target WLED controller configuration
    /// - Throws: WLEDAdapterError if send fails
    public func send(_ packet: WLEDAudioSyncPacket, to controller: WLEDController) async throws {
        guard isStarted else {
            throw WLEDAdapterError.notStarted
        }
        
        guard controller.enabled else {
            // Silently skip disabled controllers
            return
        }
        
        // Get or create connection for this controller
        let connection = try await getConnection(for: controller)
        
        // Encode packet to binary data
        let data = packet.encode()
        
        // Send UDP packet
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    self.sendErrors += 1
                    continuation.resume(throwing: WLEDAdapterError.sendFailed(error.localizedDescription))
                } else {
                    Task {
                        await self.recordSend()
                    }
                    continuation.resume()
                }
            })
        }
    }
    
    /// Send audio sync packet to multiple controllers
    /// - Parameters:
    ///   - packet: Audio sync packet to send
    ///   - controllers: List of target WLED controllers
    /// - Returns: Array of controller IDs that failed to receive the packet
    public func send(_ packet: WLEDAudioSyncPacket, to controllers: [WLEDController]) async -> [String] {
        var failedControllers: [String] = []
        
        for controller in controllers where controller.enabled {
            do {
                try await send(packet, to: controller)
            } catch {
                failedControllers.append(controller.id)
                // Log error but continue with other controllers
                print("Failed to send to WLED controller \(controller.name): \(error.localizedDescription)")
            }
        }
        
        return failedControllers
    }
    
    // MARK: - Connection Management
    
    /// Get or create UDP connection for a controller
    private func getConnection(for controller: WLEDController) async throws -> NWConnection {
        let key = controller.id
        
        // Return existing connection if available and ready
        if let existing = connections[key], existing.state == .ready {
            return existing
        }
        
        // Create new connection
        let host = NWEndpoint.Host(controller.host)
        let port = NWEndpoint.Port(rawValue: controller.port) ?? NWEndpoint.Port(integerLiteral: 21324)
        
        let connection = NWConnection(
            host: host,
            port: port,
            using: .udp
        )
        
        // Store connection
        connections[key] = connection
        
        // Start connection
        connection.start(queue: .global())
        
        // Wait for connection to be ready (or fail)
        try await waitForReady(connection)
        
        return connection
    }
    
    /// Wait for connection to reach ready state
    private func waitForReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: WLEDAdapterError.connectionFailed(error.localizedDescription))
                case .waiting(let error):
                    // UDP doesn't really wait, but handle just in case
                    print("WLED connection waiting: \(error.localizedDescription)")
                default:
                    break
                }
            }
            
            // Timeout after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                if !resumed {
                    resumed = true
                    continuation.resume(throwing: WLEDAdapterError.connectionFailed("Connection timeout"))
                }
            }
        }
    }
    
    // MARK: - Stats
    
    private func recordSend() {
        packetsSent += 1
        lastSendTime = Date()
    }
    
    /// Get adapter statistics
    public func stats() -> [String: Any] {
        [
            "started": isStarted,
            "connections": connections.count,
            "packetsSent": packetsSent,
            "sendErrors": sendErrors,
            "lastSendTime": lastSendTime?.ISO8601Format() ?? "never"
        ]
    }
    
    /// Reset statistics
    public func resetStats() {
        packetsSent = 0
        sendErrors = 0
        lastSendTime = nil
    }
}

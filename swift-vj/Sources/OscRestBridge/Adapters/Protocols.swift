// Protocols.swift - Protocol interfaces for dependency injection
// Following A Philosophy of Software Design: narrow interfaces

import Foundation

// MARK: - OSC Transport

/// Protocol for OSC communication
public protocol OSCTransport: Sendable {
    func start(host: String, port: UInt16, handler: @escaping @Sendable (String, [Any]) async -> Void) async throws
    func stop() async
}

// MARK: - HTTP Client

/// Protocol for HTTP requests
public protocol HTTPClient: Sendable {
    func execute(
        method: String,
        url: String,
        headers: [String: String],
        body: Data?,
        timeoutMs: Int
    ) async throws -> (statusCode: Int, body: Data)
}

// MARK: - Clock

/// Protocol for time abstraction (for testing)
public protocol Clock: Sendable {
    func now() -> Date
}

public struct SystemClock: Clock {
    public init() {}
    
    public func now() -> Date {
        Date()
    }
}

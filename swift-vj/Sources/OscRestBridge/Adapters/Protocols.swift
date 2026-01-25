// Protocols.swift - Protocol interfaces for dependency injection
// Following A Philosophy of Software Design: narrow interfaces

import Foundation

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

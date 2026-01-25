// TestDoubles.swift - Test implementations for behavioral tests
// Following Grokking Simplicity: separate test infrastructure

import Foundation
@testable import OscRestBridge

// MARK: - Test HTTP Client

actor TestHTTPClient: HTTPClient {
    private(set) var requests: [CapturedRequest] = []
    var shouldFail: Bool = false
    var failureError: Error = HTTPError.networkError("Simulated failure")
    var responseStatusCode: Int = 200
    var responseBody: Data = Data()
    
    struct CapturedRequest: Sendable {
        let method: String
        let url: String
        let headers: [String: String]
        let body: Data?
        let timeoutMs: Int
    }
    
    func execute(
        method: String,
        url: String,
        headers: [String: String],
        body: Data?,
        timeoutMs: Int
    ) async throws -> (statusCode: Int, body: Data) {
        let request = CapturedRequest(
            method: method,
            url: url,
            headers: headers,
            body: body,
            timeoutMs: timeoutMs
        )
        requests.append(request)
        
        if shouldFail {
            throw failureError
        }
        
        return (responseStatusCode, responseBody)
    }
    
    func reset() {
        requests = []
        shouldFail = false
        responseStatusCode = 200
        responseBody = Data()
    }
}

// MARK: - Test Clock

final class TestClock: Clock, @unchecked Sendable {
    private var currentTime: Date
    private let lock = NSLock()
    
    init(startTime: Date = Date(timeIntervalSince1970: 1000000000)) {
        self.currentTime = startTime
    }
    
    func now() -> Date {
        lock.withLock { currentTime }
    }
    
    func advance(by seconds: TimeInterval) {
        lock.withLock {
            currentTime = currentTime.addingTimeInterval(seconds)
        }
    }
}

// OscRestBridge.swift - Module entry point
// Public API for OscRestBridge module

import Foundation

/// Convenience factory for creating a service with default dependencies
/// Note: OSC messages are handled via subscription to the existing OSCHub
public func createDefaultBridgeService() -> OscRestBridgeService {
    OscRestBridgeService(
        httpClient: URLSessionHTTPClient(),
        clock: SystemClock()
    )
}

// OscRestBridge.swift - Module entry point
// Public API for OscRestBridge module

import Foundation

// Re-export main types
@_exported import struct OscRestBridge.BridgeConfig
@_exported import struct OscRestBridge.BridgeState
@_exported import enum OscRestBridge.BridgeEvent
@_exported import actor OscRestBridge.OscRestBridgeService
@_exported import struct OscRestBridge.HTTPRequestPlan
@_exported import struct OscRestBridge.ConfigSummary
@_exported import struct OscRestBridge.ConfigValidationError
@_exported import enum OscRestBridge.ConfigStatus
@_exported import struct OscRestBridge.BridgeStats
@_exported import struct OscRestBridge.SlotState
@_exported import struct OscRestBridge.OSCMessageRecord
@_exported import struct OscRestBridge.HTTPRequestRecord
@_exported import enum OscRestBridge.ParsedOSCRoute

// Re-export protocols
@_exported import protocol OscRestBridge.OSCTransport
@_exported import protocol OscRestBridge.HTTPClient
@_exported import protocol OscRestBridge.Clock

// Re-export implementations
@_exported import class OscRestBridge.OSCKitTransport
@_exported import class OscRestBridge.URLSessionHTTPClient
@_exported import struct OscRestBridge.SystemClock

// Re-export config loader
@_exported import enum OscRestBridge.ConfigLoader

/// Convenience factory for creating a service with default dependencies
public func createDefaultBridgeService() -> OscRestBridgeService {
    OscRestBridgeService(
        oscTransport: OSCKitTransport(),
        httpClient: URLSessionHTTPClient(),
        clock: SystemClock()
    )
}

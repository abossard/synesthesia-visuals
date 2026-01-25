// BridgeState.swift - Observable state for UI
// Following Grokking Simplicity: immutable state snapshots

import Foundation

// MARK: - Config Status

public enum ConfigStatus: Sendable, Equatable {
    case notLoaded
    case valid(summary: ConfigSummary)
    case invalid(errors: [ConfigValidationError])
}

public struct ConfigSummary: Sendable, Equatable {
    public let baseUrl: String
    public let oscPort: UInt16
    public let slotCount: Int
    public let sceneCount: Int
    public let oneshotCount: Int
    public let paramCount: Int
    
    public init(baseUrl: String, oscPort: UInt16, slotCount: Int, sceneCount: Int, oneshotCount: Int, paramCount: Int) {
        self.baseUrl = baseUrl
        self.oscPort = oscPort
        self.slotCount = slotCount
        self.sceneCount = sceneCount
        self.oneshotCount = oneshotCount
        self.paramCount = paramCount
    }
}

public struct ConfigValidationError: Sendable, Equatable {
    public let path: String
    public let message: String
    
    public init(path: String, message: String) {
        self.path = path
        self.message = message
    }
}

// MARK: - Statistics

public struct BridgeStats: Sendable, Equatable {
    public var totalOscReceived: Int
    public var totalOscUnknown: Int
    public var totalRestPlanned: Int
    public var totalRestSent: Int
    public var totalRestFailures: Int
    
    public var sceneActivations: [String: Int]
    public var oneshotTriggers: [String: Int]
    public var paramUpdates: [String: Int]
    public var slotMessages: [String: Int]
    
    public var oscRate: Double  // messages/sec
    public var httpRate: Double  // requests/sec
    
    public init() {
        self.totalOscReceived = 0
        self.totalOscUnknown = 0
        self.totalRestPlanned = 0
        self.totalRestSent = 0
        self.totalRestFailures = 0
        self.sceneActivations = [:]
        self.oneshotTriggers = [:]
        self.paramUpdates = [:]
        self.slotMessages = [:]
        self.oscRate = 0.0
        self.httpRate = 0.0
    }
}

// MARK: - Slot State

public struct SlotState: Sendable, Equatable {
    public var blackoutActive: Bool
    public var lastActiveSceneName: String?
    public var lastSceneChangeTime: Date?
    
    public init(blackoutActive: Bool = false, lastActiveSceneName: String? = nil, lastSceneChangeTime: Date? = nil) {
        self.blackoutActive = blackoutActive
        self.lastActiveSceneName = lastActiveSceneName
        self.lastSceneChangeTime = lastSceneChangeTime
    }
}

// MARK: - Message Records (Ring Buffer)

public struct OSCMessageRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let path: String
    public let value: Double
    public let parsed: ParsedOSCRoute?
    public let unknownReason: String?
    
    public init(timestamp: Date, path: String, value: Double, parsed: ParsedOSCRoute?, unknownReason: String?) {
        self.id = UUID()
        self.timestamp = timestamp
        self.path = path
        self.value = value
        self.parsed = parsed
        self.unknownReason = unknownReason
    }
}

public enum ParsedOSCRoute: Sendable, Equatable {
    case scene(slot: String, sceneName: String)
    case oneshot(slot: String, oneshotName: String)
    case blackout(slot: String)
    case param(slot: String, paramName: String)
}

public struct HTTPRequestRecord: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let method: String
    public let url: String
    public let bodyPreview: String?
    public let statusCode: Int?
    public let responsePreview: String?
    public let error: String?
    public let planned: Bool  // true if dry-run
    
    public init(timestamp: Date, method: String, url: String, bodyPreview: String?, statusCode: Int?, responsePreview: String?, error: String?, planned: Bool) {
        self.id = UUID()
        self.timestamp = timestamp
        self.method = method
        self.url = url
        self.bodyPreview = bodyPreview
        self.statusCode = statusCode
        self.responsePreview = responsePreview
        self.error = error
        self.planned = planned
    }
}

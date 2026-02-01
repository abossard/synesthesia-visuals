// BridgeEvent.swift - Structured events for logging and diagnostics
// Following Grokking Simplicity: immutable event data

import Foundation

public enum BridgeEvent: Sendable, Equatable {
    case oscReceived(timestamp: Date, path: String, value: Double, parsed: ParsedOSCRoute?)
    case oscUnknownRoute(timestamp: Date, path: String, value: Double, reason: String)
    case restRequestPlanned(timestamp: Date, plan: HTTPRequestPlan)
    case restRequestSent(timestamp: Date, plan: HTTPRequestPlan)
    case restResponse(timestamp: Date, plan: HTTPRequestPlan, statusCode: Int, body: String?)
    case restFailure(timestamp: Date, plan: HTTPRequestPlan, error: String)
    case configLoaded(timestamp: Date, summary: ConfigSummary)
    case configInvalid(timestamp: Date, errors: [ConfigValidationError])
    case configReloaded(timestamp: Date, summary: ConfigSummary, changesSummary: String)
    case started(timestamp: Date)
    case stopped(timestamp: Date)
}

// MARK: - HTTP Request Plan

public struct HTTPRequestPlan: Sendable, Equatable {
    public let method: String
    public let url: String
    public let headers: [String: String]
    public let body: Data?
    
    public init(method: String, url: String, headers: [String: String], body: Data?) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
    
    public var bodyPreview: String? {
        guard let body = body else { return nil }
        guard let text = String(data: body, encoding: .utf8) else { return "<binary>" }
        return String(text.prefix(500))
    }
}

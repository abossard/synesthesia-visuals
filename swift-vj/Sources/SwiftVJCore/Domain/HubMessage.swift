// HubMessage.swift - Unified message type for all protocol traffic
// Following Grokking Simplicity: immutable data (no side effects)

import Foundation

public enum HubMessageSource: String, Sendable, CaseIterable {
    case osc = "OSC"
    case os2l = "OS2L"
    case rest = "REST"
}

public struct HubMessage: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let source: HubMessageSource
    public let title: String
    public let detail: String
    public let isIncoming: Bool

    public init(source: HubMessageSource, title: String, detail: String = "", isIncoming: Bool = true) {
        self.id = UUID()
        self.timestamp = Date()
        self.source = source
        self.title = title
        self.detail = detail
        self.isIncoming = isIncoming
    }
}

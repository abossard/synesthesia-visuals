// HubMessageLog.swift - Thread-safe circular buffer for unified protocol messages
// Following Grokking Simplicity: actor = action (side effects via isolation)

import Foundation

public actor HubMessageLog {
    private var messages: [HubMessage] = []
    private let maxMessages: Int

    public init(maxMessages: Int = 500) {
        self.maxMessages = maxMessages
    }

    public func record(_ message: HubMessage) {
        messages.append(message)
        if messages.count > maxMessages { messages.removeFirst() }
    }

    public func getMessages() -> [HubMessage] { messages }

    public func getMessages(source: HubMessageSource) -> [HubMessage] {
        messages.filter { $0.source == source }
    }

    public func clear() { messages.removeAll() }

    public func count() -> Int { messages.count }

    public func count(source: HubMessageSource) -> Int {
        messages.filter { $0.source == source }.count
    }
}

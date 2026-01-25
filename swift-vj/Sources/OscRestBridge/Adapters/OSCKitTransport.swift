// OSCKitTransport.swift - OSCKit adapter
// Following Grokking Simplicity: action (side effects)

import Foundation
import OSCKit

/// Real OSC transport using OSCKit
public final class OSCKitTransport: OSCTransport, @unchecked Sendable {
    private var server: OSCServer?
    private let lock = NSLock()
    
    public init() {}
    
    public func start(
        host: String,
        port: UInt16,
        handler: @escaping @Sendable (String, [Any]) async -> Void
    ) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        let oscServer = OSCServer(port: port) { message, _ in
            let path = message.addressPattern.stringValue
            let values = message.values.map { $0 as Any }
            
            Task {
                await handler(path, values)
            }
        }
        
        oscServer.isPortReuseEnabled = true
        
        try oscServer.start()
        self.server = oscServer
    }
    
    public func stop() async {
        lock.lock()
        defer { lock.unlock() }
        
        server?.stop()
        server = nil
    }
}

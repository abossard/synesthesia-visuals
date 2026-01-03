// SyphonReceiver.swift
// SyphonKit - Swift wrapper for Syphon Metal client
//
// Receives textures from other Syphon-enabled applications

import Foundation
import Metal
import Syphon
import Combine
import CoreGraphics

/// Swift wrapper around SyphonMetalClient for receiving textures
public final class SyphonReceiver {
    
    private var client: SyphonMetalClient?
    private let device: MTLDevice
    private var serverDescription: [String: Any]?
    
    /// Publisher for new frames
    public let framePublisher = PassthroughSubject<MTLTexture, Never>()
    
    /// Whether the client is connected
    public var isConnected: Bool { client?.isValid ?? false }
    
    /// The size of the received texture
    public var textureSize: CGSize {
        guard let client = client,
              let texture = client.newFrameImage() else {
            return CGSize(width: 0, height: 0)
        }
        return CGSize(width: texture.width, height: texture.height)
    }
    
    /// Creates a new Syphon receiver
    /// - Parameter device: The Metal device to use
    public init(device: MTLDevice) {
        self.device = device
    }
    
    /// Connects to a Syphon server
    /// - Parameter serverDescription: The server description from SyphonServerDirectory
    /// - Returns: true if connection succeeded
    @discardableResult
    public func connect(to serverDescription: [String: Any]) -> Bool {
        disconnect()
        
        client = SyphonMetalClient(
            serverDescription: serverDescription,
            device: device,
            options: nil,
            newFrameHandler: { [weak self] client in
                self?.handleNewFrame(client)
            }
        )
        
        self.serverDescription = serverDescription
        return client?.isValid ?? false
    }
    
    /// Connects to a server by name
    /// - Parameters:
    ///   - appName: The application name (optional)
    ///   - serverName: The server name (optional)
    /// - Returns: true if a matching server was found and connected
    @discardableResult
    public func connect(appName: String? = nil, serverName: String? = nil) -> Bool {
        guard let servers = SyphonServerDirectory.shared().servers as? [[String: Any]] else {
            return false
        }
        
        for server in servers {
            let matchesApp = appName == nil || 
                (server[SyphonServerDescriptionAppNameKey as String] as? String) == appName
            let matchesName = serverName == nil ||
                (server[SyphonServerDescriptionNameKey as String] as? String) == serverName
            
            if matchesApp && matchesName {
                return connect(to: server)
            }
        }
        
        return false
    }
    
    /// Disconnects from the current server
    public func disconnect() {
        client?.stop()
        client = nil
        serverDescription = nil
    }
    
    /// Gets the latest frame texture
    /// - Returns: The current frame as a Metal texture, or nil
    public func currentFrame() -> MTLTexture? {
        guard let client = client, client.isValid else { return nil }
        return client.newFrameImage()
    }
    
    private func handleNewFrame(_ client: SyphonMetalClient) {
        if let texture = client.newFrameImage() {
            framePublisher.send(texture)
        }
    }
    
    deinit {
        disconnect()
    }
}

// MARK: - Server Discovery

extension SyphonReceiver {
    
    /// Gets all available Syphon servers
    public static func availableServers() -> [ServerInfo] {
        guard let servers = SyphonServerDirectory.shared().servers as? [[String: Any]] else {
            return []
        }
        
        return servers.compactMap { dict in
            let appName = dict[SyphonServerDescriptionAppNameKey as String] as? String ?? ""
            let serverName = dict[SyphonServerDescriptionNameKey as String] as? String ?? ""
            return ServerInfo(appName: appName, serverName: serverName, description: dict)
        }
    }
    
    /// Information about an available Syphon server
    public struct ServerInfo: Identifiable {
        public let id = UUID()
        public let appName: String
        public let serverName: String
        public let description: [String: Any]
        
        public var displayName: String {
            if serverName.isEmpty {
                return appName
            }
            return "\(appName) - \(serverName)"
        }
    }
}

// SyphonSender.swift
// SyphonKit - Swift wrapper for Syphon Metal server
//
// Provides zero-latency texture sharing between macOS applications

import Foundation
import Metal
import Syphon

/// Swift wrapper around SyphonMetalServer for sending textures
public final class SyphonSender {
    
    private var server: SyphonMetalServer?
    private let device: MTLDevice
    private let name: String
    
    /// Whether the server is currently active
    public var isActive: Bool { server != nil }
    
    /// The name this server publishes under
    public var serverName: String { name }
    
    /// Creates a new Syphon sender
    /// - Parameters:
    ///   - name: The server name (visible to Syphon clients)
    ///   - device: The Metal device to use
    public init(name: String, device: MTLDevice) {
        self.name = name
        self.device = device
    }
    
    /// Starts the Syphon server
    /// - Returns: true if server started successfully
    @discardableResult
    public func start() -> Bool {
        guard server == nil else { return true }
        
        server = SyphonMetalServer(
            name: name,
            device: device,
            options: nil
        )
        
        return server != nil
    }
    
    /// Stops the Syphon server
    public func stop() {
        server?.stop()
        server = nil
    }
    
    /// Publishes a Metal texture to connected clients
    /// - Parameters:
    ///   - texture: The texture to publish
    ///   - commandBuffer: The command buffer for synchronization
    ///   - flipped: Whether to flip the texture vertically (default: false)
    public func publish(
        texture: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        flipped: Bool = false
    ) {
        guard let server = server else { return }
        
        if flipped {
            let region = MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(
                    width: texture.width,
                    height: texture.height,
                    depth: 1
                )
            )
            server.publishFrameTexture(
                texture,
                onCommandBuffer: commandBuffer,
                imageRegion: region,
                flipped: true
            )
        } else {
            server.publishFrameTexture(
                texture,
                onCommandBuffer: commandBuffer
            )
        }
    }
    
    /// Publishes a texture from an IOSurface
    /// - Parameters:
    ///   - surface: The IOSurface to publish
    ///   - flipped: Whether to flip vertically
    public func publish(surface: IOSurfaceRef, flipped: Bool = false) {
        guard let server = server else { return }
        
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(
                width: IOSurfaceGetWidth(surface),
                height: IOSurfaceGetHeight(surface),
                depth: 1
            )
        )
        
        // Create texture from IOSurface for publishing
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: IOSurfaceGetWidth(surface),
            height: IOSurfaceGetHeight(surface),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        
        if let texture = device.makeTexture(
            descriptor: descriptor,
            iosurface: surface,
            plane: 0
        ) {
            // Need a command buffer for the publish
            if let queue = device.makeCommandQueue(),
               let commandBuffer = queue.makeCommandBuffer() {
                server.publishFrameTexture(
                    texture,
                    onCommandBuffer: commandBuffer,
                    imageRegion: region,
                    flipped: flipped
                )
                commandBuffer.commit()
            }
        }
    }
    
    deinit {
        stop()
    }
}

// MARK: - Convenience Extensions

extension SyphonSender {
    /// Creates and immediately starts a sender
    public static func create(
        name: String,
        device: MTLDevice
    ) -> SyphonSender? {
        let sender = SyphonSender(name: name, device: device)
        guard sender.start() else { return nil }
        return sender
    }
}

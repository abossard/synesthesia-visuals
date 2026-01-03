// SyphonOutput.swift - Syphon server management for VJ tile outputs
// Port of Syphon output from VJUniverse
//
// Note: This uses a stub implementation. For real Syphon output:
// 1. Download Syphon.framework from https://github.com/Syphon/Syphon-Framework
// 2. Add it to the project
// 3. Replace SyphonMetalServerStub with actual SyphonMetalServer

import Foundation
import Metal

// MARK: - Syphon Server Protocol

/// Protocol for Syphon server (allows stub/real implementation swap)
protocol SyphonServerProtocol {
    var name: String { get }
    func publishTexture(
        _ texture: MTLTexture,
        onCommandBuffer commandBuffer: MTLCommandBuffer,
        imageRegion: MTLRegion,
        flipped: Bool
    )
    func stop()
}

// MARK: - Syphon Metal Server Stub

/// Stub implementation for when Syphon.framework is not available
/// Replace with real SyphonMetalServer when framework is integrated
final class SyphonMetalServerStub: SyphonServerProtocol {
    let name: String
    private let device: MTLDevice

    init(name: String, device: MTLDevice, options: [String: Any]?) {
        self.name = name
        self.device = device
        // In real implementation, this creates the Syphon server
    }

    func publishTexture(
        _ texture: MTLTexture,
        onCommandBuffer commandBuffer: MTLCommandBuffer,
        imageRegion: MTLRegion,
        flipped: Bool
    ) {
        // Stub: In real implementation, this publishes to Syphon
        // The texture is ready for sharing with other applications
    }

    func stop() {
        // Stub: In real implementation, this stops the server
    }
}

// MARK: - Syphon Output Manager

/// Manages Syphon servers for all tile outputs
/// Each tile gets its own Syphon server for OBS/Resolume compositing
final class SyphonOutputManager {
    // MARK: - Properties

    private var servers: [String: SyphonServerProtocol] = [:]
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// Whether Syphon output is enabled
    var isEnabled: Bool = true

    /// Number of active servers
    var serverCount: Int { servers.count }

    /// Active server names
    var serverNames: [String] { Array(servers.keys).sorted() }

    /// Whether using stub (vs real Syphon)
    var isUsingStub: Bool { true }  // Set to false when real Syphon is integrated

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
    }

    deinit {
        stopAll()
    }

    // MARK: - Server Management

    /// Create a Syphon server for a tile
    func createServer(name: String) {
        guard servers[name] == nil else { return }

        // Use stub implementation - replace with real SyphonMetalServer when available
        let server = SyphonMetalServerStub(
            name: name,
            device: device,
            options: nil
        )
        servers[name] = server
        print("[Syphon] Created server: \(name)\(isUsingStub ? " (stub)" : "")")
    }

    /// Create all standard tile servers
    func createStandardServers() {
        let names = [
            TileConfig.shader.syphonName,
            TileConfig.mask.syphonName,
            TileConfig.lyrics.syphonName,
            TileConfig.refrain.syphonName,
            TileConfig.songInfo.syphonName,
            TileConfig.image.syphonName
        ]

        for name in names {
            createServer(name: name)
        }
    }

    /// Publish a texture to a Syphon server
    func publish(
        name: String,
        texture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard isEnabled,
              let server = servers[name] else { return }

        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)

        server.publishTexture(
            texture,
            onCommandBuffer: commandBuffer,
            imageRegion: region,
            flipped: false
        )
    }

    /// Publish texture with automatic command buffer
    func publish(name: String, texture: MTLTexture) {
        guard isEnabled,
              let server = servers[name],
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)

        server.publishTexture(
            texture,
            onCommandBuffer: commandBuffer,
            imageRegion: region,
            flipped: false
        )

        commandBuffer.commit()
    }

    /// Stop a specific server
    func stopServer(name: String) {
        if let server = servers[name] {
            server.stop()
            servers.removeValue(forKey: name)
            print("[Syphon] Stopped server: \(name)")
        }
    }

    /// Stop all servers
    func stopAll() {
        for (name, server) in servers {
            server.stop()
            print("[Syphon] Stopped server: \(name)")
        }
        servers.removeAll()
    }

    /// Check if a server exists
    func hasServer(name: String) -> Bool {
        servers[name] != nil
    }
}

// MARK: - Real Syphon Integration Guide
/*
 To integrate real Syphon.framework:

 1. Download from https://github.com/Syphon/Syphon-Framework/releases

 2. Add to Xcode project:
    - Drag Syphon.framework to project
    - Add to "Frameworks, Libraries, and Embedded Content"
    - Set to "Embed & Sign"

 3. Create bridging header if needed:
    #import <Syphon/Syphon.h>

 4. Replace SyphonMetalServerStub with:

    import Syphon

    extension SyphonMetalServer: SyphonServerProtocol {
        func publishTexture(
            _ texture: MTLTexture,
            onCommandBuffer commandBuffer: MTLCommandBuffer,
            imageRegion: MTLRegion,
            flipped: Bool
        ) {
            self.publishFrameTexture(
                texture,
                onCommandBuffer: commandBuffer,
                imageRegion: imageRegion,
                flipped: flipped
            )
        }
    }

 5. Update createServer() to use SyphonMetalServer:
    let server = SyphonMetalServer(name: name, device: device, options: nil)

 6. Set isUsingStub = false
*/

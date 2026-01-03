// SyphonOutput.swift - Syphon server management for VJ tile outputs
// Port of Syphon output from VJUniverse
//
// Now using real Syphon.xcframework via SyphonKit wrapper

import Foundation
import Metal
import SyphonKit

// MARK: - Syphon Output Manager

/// Manages Syphon servers for all tile outputs
/// Each tile gets its own Syphon server for OBS/Resolume compositing
final class SyphonOutputManager {
    // MARK: - Properties

    private var senders: [String: SyphonSender] = [:]
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// Whether Syphon output is enabled
    var isEnabled: Bool = true

    /// Number of active servers
    var serverCount: Int { senders.count }

    /// Active server names
    var serverNames: [String] { Array(senders.keys).sorted() }

    /// Whether using stub (vs real Syphon) - now always false with real framework
    var isUsingStub: Bool { false }

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
        guard senders[name] == nil else { return }

        let sender = SyphonSender(name: name, device: device)
        if sender.start() {
            senders[name] = sender
            print("[Syphon] Created server: \(name)")
        } else {
            print("[Syphon] Failed to create server: \(name)")
        }
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
              let sender = senders[name] else { return }

        sender.publish(
            texture: texture,
            commandBuffer: commandBuffer,
            flipped: false
        )
    }

    /// Publish texture with automatic command buffer
    func publish(name: String, texture: MTLTexture) {
        guard isEnabled,
              let sender = senders[name],
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        sender.publish(
            texture: texture,
            commandBuffer: commandBuffer,
            flipped: false
        )

        commandBuffer.commit()
    }

    /// Stop a specific server
    func stopServer(name: String) {
        if let sender = senders[name] {
            sender.stop()
            senders.removeValue(forKey: name)
            print("[Syphon] Stopped server: \(name)")
        }
    }

    /// Stop all servers
    func stopAll() {
        for (name, sender) in senders {
            sender.stop()
            print("[Syphon] Stopped server: \(name)")
        }
        senders.removeAll()
    }

    /// Check if a server exists
    func hasServer(name: String) -> Bool {
        senders[name] != nil
    }
}

// MARK: - Server Discovery Extension

extension SyphonOutputManager {
    /// Get list of all available Syphon servers (from other apps)
    static func availableServers() -> [SyphonReceiver.ServerInfo] {
        SyphonReceiver.availableServers()
    }
}

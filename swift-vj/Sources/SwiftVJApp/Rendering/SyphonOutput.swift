// SyphonOutput.swift - Thread-safe Syphon server management
// Syphon's SyphonMetalServer is thread-safe per its header documentation.
// This wrapper adds lock protection for the senders dictionary only.

import Foundation
import Metal
import os.lock
import SyphonKit

// MARK: - Syphon Output Manager

/// Thread-safe Syphon server manager for VJ tile outputs
/// Each tile gets its own Syphon server for OBS/Resolume compositing
/// NOT @MainActor - can be called from any thread (headless render loop thread)
final class SyphonOutputManager: @unchecked Sendable {
    // MARK: - Properties

    private var senders: [String: SyphonSender] = [:]
    private let sendersLock = OSAllocatedUnfairLock()
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    /// Number of active servers
    var serverCount: Int {
        sendersLock.lock()
        defer { sendersLock.unlock() }
        return senders.count
    }

    /// Active server names
    var serverNames: [String] {
        sendersLock.lock()
        defer { sendersLock.unlock() }
        return Array(senders.keys).sorted()
    }
    
    /// Shared instance for global access
    static let shared: SyphonOutputManager = {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device available for Syphon")
        }
        return SyphonOutputManager(device: device)
    }()

    // MARK: - Init

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
    }

    deinit {
        stopAll()
    }

    // MARK: - Server Management

    /// Create a Syphon server for a tile (thread-safe)
    func createServer(name: String) {
        sendersLock.lock()
        defer { sendersLock.unlock() }
        
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

    /// Publish a texture to a Syphon server (thread-safe, called from render thread)
    func publish(
        name: String,
        texture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        sendersLock.lock()
        let sender = senders[name]
        sendersLock.unlock()
        
        guard let sender = sender else { return }

        sender.publish(
            texture: texture,
            commandBuffer: commandBuffer,
            flipped: false
        )
    }

    /// Publish texture with automatic command buffer (thread-safe)
    func publish(name: String, texture: MTLTexture) {
        sendersLock.lock()
        let sender = senders[name]
        sendersLock.unlock()
        
        guard let sender = sender,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        sender.publish(
            texture: texture,
            commandBuffer: commandBuffer,
            flipped: false
        )

        commandBuffer.commit()
    }

    /// Stop a specific server (thread-safe)
    func stopServer(name: String) {
        sendersLock.lock()
        let sender = senders.removeValue(forKey: name)
        sendersLock.unlock()
        
        if let sender = sender {
            sender.stop()
            print("[Syphon] Stopped server: \(name)")
        }
    }

    /// Stop all servers (thread-safe)
    func stopAll() {
        sendersLock.lock()
        let allSenders = senders
        senders.removeAll()
        sendersLock.unlock()
        
        for (name, sender) in allSenders {
            sender.stop()
            print("[Syphon] Stopped server: \(name)")
        }
    }

    /// Check if a server exists (thread-safe)
    func hasServer(name: String) -> Bool {
        sendersLock.lock()
        defer { sendersLock.unlock() }
        return senders[name] != nil
    }
}

// MARK: - Server Discovery Extension

extension SyphonOutputManager {
    /// Get list of all available Syphon servers (from other apps)
    static func availableServers() -> [SyphonReceiver.ServerInfo] {
        SyphonReceiver.availableServers()
    }
}

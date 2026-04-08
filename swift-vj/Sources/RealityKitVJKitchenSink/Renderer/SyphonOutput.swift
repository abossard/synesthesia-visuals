// SyphonOutput.swift
// RealityKitVJKitchenSink
//
// Wrapper for SyphonMetalServer to publish rendered textures.
// Reference: https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h

import Metal
import SyphonKit

/// Manages Syphon server for publishing Metal textures
final class SyphonOutput {
    private let sender: SyphonSender
    private let serverName: String

    init(device: MTLDevice, serverName: String) {
        self.serverName = serverName
        self.sender = SyphonSender(name: serverName, device: device)
        // Start the server immediately
        sender.start()
    }

    deinit {
        stop()
    }

    /// Publish a texture to Syphon clients
    /// IMPORTANT: Must be called BEFORE commandBuffer.commit() for zero-latency publishing
    func publish(texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        sender.publish(texture: texture, commandBuffer: commandBuffer)
    }

    /// Stop the Syphon server
    func stop() {
        sender.stop()
    }

    /// Check if server is active
    var isActive: Bool {
        return sender.isActive
    }
}

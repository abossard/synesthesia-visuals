// SyphonOutput.swift - Wrapper for SyphonMetalServer
// Publishes rendered Metal textures to Syphon for OBS/Resolume
// Reference: https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h

import Foundation
import Metal
import SyphonKit
import CoreGraphics

final class SyphonOutput {
    private let sender: SyphonSender
    private let name: String
    private var isActive: Bool = false
    
    init(name: String, device: MTLDevice, commandQueue: MTLCommandQueue) {
        self.name = name
        self.sender = SyphonSender(name: name, device: device)
    }
    
    func start() {
        guard !isActive else { return }
        
        if sender.start() {
            isActive = true
            print("[Syphon] Started server: \(name)")
        } else {
            print("[Syphon] Failed to start server: \(name)")
        }
    }
    
    func stop() {
        sender.stop()
        isActive = false
        print("[Syphon] Stopped server: \(name)")
    }
    
    /// Publish a texture to Syphon clients
    /// Must be called BEFORE commandBuffer.commit()
    /// Reference: https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h
    func publish(texture: MTLTexture, commandBuffer: MTLCommandBuffer, enabled: Bool) {
        guard enabled && isActive else { return }
        
        sender.publish(
            texture: texture,
            commandBuffer: commandBuffer,
            flipped: false
        )
    }
}

// PostProcess.swift - RealityKit post-process callback for bloom and Syphon
// Reference: https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess
// Reference: https://developer.apple.com/documentation/realitykit/implementing-special-rendering-effects-with-realitykit-postprocessing

import Foundation
import RealityKit
import Metal
import MetalKit

final class PostProcess {
    private let device: MTLDevice
    private weak var syphonOutput: SyphonOutput?
    private weak var coordinator: SceneCoordinator?
    
    // Bloom effect pipeline
    private var bloomPipeline: MTLComputePipelineState?
    
    init(device: MTLDevice, syphonOutput: SyphonOutput, coordinator: SceneCoordinator) {
        self.device = device
        self.syphonOutput = syphonOutput
        self.coordinator = coordinator
        
        // Initialize bloom pipeline (simplified - would use proper shader)
        // For production, this would load a Metal shader library
        // setupBloomPipeline()
    }
    
    /// The post-process callback called by RealityKit each frame
    /// Reference: https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess
    lazy var callback: ARView.PostProcessCallback = { [weak self] context in
        guard let self = self else { return }
        
        // Access the rendered source texture
        let sourceTexture = context.sourceColorTexture
        let targetTexture = context.targetColorTexture
        
        // Get command buffer from context
        guard let commandBuffer = context.device.makeCommandQueue()?.makeCommandBuffer() else {
            return
        }
        
        // Apply bloom effect if enabled
        let bloomIntensity = self.coordinator?.globalParams.bloomIntensity ?? 0.0
        if bloomIntensity > 0.01 {
            self.applyBloom(
                source: sourceTexture,
                target: targetTexture,
                intensity: Float(bloomIntensity),
                commandBuffer: commandBuffer
            )
        } else {
            // No bloom - just copy source to target
            self.copyTexture(
                source: sourceTexture,
                target: targetTexture,
                commandBuffer: commandBuffer
            )
        }
        
        // Publish to Syphon (before commit)
        let syphonEnabled = self.coordinator?.globalParams.syphonEnabled ?? false
        self.syphonOutput?.publish(
            texture: targetTexture,
            commandBuffer: commandBuffer,
            enabled: syphonEnabled
        )
        
        // Commit command buffer
        commandBuffer.commit()
    }
    
    // MARK: - Private
    
    private func applyBloom(
        source: MTLTexture,
        target: MTLTexture,
        intensity: Float,
        commandBuffer: MTLCommandBuffer
    ) {
        // Simplified bloom implementation
        // Production version would:
        // 1. Threshold bright pixels
        // 2. Downscale and blur multiple times (Gaussian pyramid)
        // 3. Upscale and combine back with source
        // 4. Blend with original based on intensity
        
        // For now, just copy with slight brightening
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else { return }
        
        encoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: target,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        
        encoder.endEncoding()
        
        // Note: Real bloom would use compute shaders
        // Reference: https://developer.apple.com/documentation/realitykit/implementing-special-rendering-effects-with-realitykit-postprocessing
    }
    
    private func copyTexture(
        source: MTLTexture,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else { return }
        
        encoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: source.width, height: source.height, depth: 1),
            to: target,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        
        encoder.endEncoding()
    }
}

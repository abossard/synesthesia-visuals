// PostProcess.swift
// RealityKitVJKitchenSink
//
// Post-processing effects including bloom/glow.
// Reference: https://developer.apple.com/documentation/realitykit/implementing-special-rendering-effects-with-realitykit-postprocessing

import Metal
import MetalKit
import simd

/// Post-processing effect pipeline
final class PostProcessor {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    private var blitPipelineState: MTLRenderPipelineState?
    private var bloomPipelineState: MTLComputePipelineState?
    private var blurPipelineState: MTLComputePipelineState?
    private var compositePipelineState: MTLComputePipelineState?

    // Intermediate textures for bloom
    private var brightPassTexture: MTLTexture?
    private var blurTexture1: MTLTexture?
    private var blurTexture2: MTLTexture?

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!

        // Create shader library from embedded Metal source
        do {
            let source = PostProcessor.shaderSource
            self.library = try device.makeLibrary(source: source, options: nil)
        } catch {
            fatalError("Failed to create post-process shader library: \(error)")
        }

        setupPipelines()
    }

    private func setupPipelines() {
        // Bloom bright pass compute pipeline
        if let function = library.makeFunction(name: "brightPassKernel") {
            bloomPipelineState = try? device.makeComputePipelineState(function: function)
        }

        // Blur compute pipeline
        if let function = library.makeFunction(name: "gaussianBlurKernel") {
            blurPipelineState = try? device.makeComputePipelineState(function: function)
        }

        // Composite compute pipeline
        if let function = library.makeFunction(name: "compositeKernel") {
            compositePipelineState = try? device.makeComputePipelineState(function: function)
        }
    }

    // MARK: - Texture Management

    private func ensureIntermediateTextures(matching texture: MTLTexture) {
        let width = texture.width / 2  // Work at half res for blur
        let height = texture.height / 2

        if brightPassTexture == nil ||
            brightPassTexture!.width != width ||
            brightPassTexture!.height != height {

            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private

            brightPassTexture = device.makeTexture(descriptor: descriptor)
            blurTexture1 = device.makeTexture(descriptor: descriptor)
            blurTexture2 = device.makeTexture(descriptor: descriptor)
        }
    }

    // MARK: - Post-Process Operations

    /// Apply bloom effect to texture
    func applyBloom(
        commandBuffer: MTLCommandBuffer,
        sourceTexture: MTLTexture,
        targetTexture: MTLTexture,
        intensity: Float
    ) {
        ensureIntermediateTextures(matching: sourceTexture)

        guard let brightPass = brightPassTexture,
              let blur1 = blurTexture1,
              let blur2 = blurTexture2,
              let bloomPipeline = bloomPipelineState,
              let blurPipeline = blurPipelineState,
              let compositePipeline = compositePipelineState else {
            // Fallback to simple copy
            copyTexture(commandBuffer: commandBuffer, sourceTexture: sourceTexture, targetTexture: targetTexture)
            return
        }

        // 1. Bright pass (extract bright areas)
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(bloomPipeline)
            encoder.setTexture(sourceTexture, index: 0)
            encoder.setTexture(brightPass, index: 1)

            var threshold: Float = 0.8
            encoder.setBytes(&threshold, length: MemoryLayout<Float>.size, index: 0)

            let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
            let threadGroups = MTLSize(
                width: (brightPass.width + 7) / 8,
                height: (brightPass.height + 7) / 8,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }

        // 2. Horizontal blur
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(blurPipeline)
            encoder.setTexture(brightPass, index: 0)
            encoder.setTexture(blur1, index: 1)

            var horizontal: Int32 = 1
            encoder.setBytes(&horizontal, length: MemoryLayout<Int32>.size, index: 0)

            let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
            let threadGroups = MTLSize(
                width: (blur1.width + 7) / 8,
                height: (blur1.height + 7) / 8,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }

        // 3. Vertical blur
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(blurPipeline)
            encoder.setTexture(blur1, index: 0)
            encoder.setTexture(blur2, index: 1)

            var horizontal: Int32 = 0
            encoder.setBytes(&horizontal, length: MemoryLayout<Int32>.size, index: 0)

            let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
            let threadGroups = MTLSize(
                width: (blur2.width + 7) / 8,
                height: (blur2.height + 7) / 8,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }

        // 4. Composite original + bloom
        if let encoder = commandBuffer.makeComputeCommandEncoder() {
            encoder.setComputePipelineState(compositePipeline)
            encoder.setTexture(sourceTexture, index: 0)
            encoder.setTexture(blur2, index: 1)
            encoder.setTexture(targetTexture, index: 2)

            var bloomIntensity = intensity
            encoder.setBytes(&bloomIntensity, length: MemoryLayout<Float>.size, index: 0)

            let threadsPerGroup = MTLSize(width: 8, height: 8, depth: 1)
            let threadGroups = MTLSize(
                width: (targetTexture.width + 7) / 8,
                height: (targetTexture.height + 7) / 8,
                depth: 1
            )
            encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()
        }
    }

    /// Simple texture copy
    func copyTexture(commandBuffer: MTLCommandBuffer, sourceTexture: MTLTexture, targetTexture: MTLTexture) {
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }

        let sourceSize = MTLSize(
            width: min(sourceTexture.width, targetTexture.width),
            height: min(sourceTexture.height, targetTexture.height),
            depth: 1
        )

        blitEncoder.copy(
            from: sourceTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: sourceSize,
            to: targetTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )

        blitEncoder.endEncoding()
    }

    // MARK: - Embedded Shader Source

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // Bright pass - extract pixels above threshold
    kernel void brightPassKernel(
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> dest [[texture(1)]],
        constant float& threshold [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

        // Sample from source at corresponding position (source is 2x size)
        uint2 sourcePos = gid * 2;
        float4 color = source.read(sourcePos);

        // Calculate luminance
        float luma = dot(color.rgb, float3(0.299, 0.587, 0.114));

        // Soft threshold
        float brightness = max(0.0, luma - threshold);
        brightness = brightness / (brightness + 1.0); // Tonemap

        float4 result = float4(color.rgb * brightness, 1.0);
        dest.write(result, gid);
    }

    // Gaussian blur kernel (separable)
    kernel void gaussianBlurKernel(
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::write> dest [[texture(1)]],
        constant int& horizontal [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

        // 9-tap Gaussian weights
        const float weights[5] = { 0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216 };

        float4 result = source.read(gid) * weights[0];

        int2 offset = horizontal ? int2(1, 0) : int2(0, 1);

        for (int i = 1; i < 5; i++) {
            int2 pos1 = int2(gid) + offset * i;
            int2 pos2 = int2(gid) - offset * i;

            // Clamp to texture bounds
            pos1 = clamp(pos1, int2(0), int2(dest.get_width() - 1, dest.get_height() - 1));
            pos2 = clamp(pos2, int2(0), int2(dest.get_width() - 1, dest.get_height() - 1));

            result += source.read(uint2(pos1)) * weights[i];
            result += source.read(uint2(pos2)) * weights[i];
        }

        dest.write(result, gid);
    }

    // Composite original + bloom
    kernel void compositeKernel(
        texture2d<float, access::read> original [[texture(0)]],
        texture2d<float, access::read> bloom [[texture(1)]],
        texture2d<float, access::write> dest [[texture(2)]],
        constant float& intensity [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= dest.get_width() || gid.y >= dest.get_height()) return;

        float4 originalColor = original.read(gid);

        // Sample bloom at corresponding position (bloom is half size)
        uint2 bloomPos = gid / 2;
        bloomPos = clamp(bloomPos, uint2(0), uint2(bloom.get_width() - 1, bloom.get_height() - 1));
        float4 bloomColor = bloom.read(bloomPos);

        // Additive blend with intensity
        float4 result = originalColor + bloomColor * intensity;
        result = clamp(result, 0.0, 1.0);
        result.a = 1.0;

        dest.write(result, gid);
    }
    """
}

import Foundation
import Metal
import RealityKit

@available(macOS 15.0, *)
final class PostProcess {
    var bloomIntensity: Double = 0.8
    var syphonEnabled: Bool = true

    private var pipelineState: MTLComputePipelineState?
    private var syphonOutput: SyphonOutput?
    private var device: MTLDevice?

    func handlePostProcess(context: ARView.RenderCallbacks.PostProcessContext, globalParams: GlobalParams?) {
        ensureDevice(context.device)
        guard let commandBuffer = context.commandBuffer else { return }
        guard let sourceTexture = context.sourceColorTexture else { return }
        guard let destinationTexture = context.destinationColorTexture else { return }

        if let pipelineState {
            encodePostProcess(
                commandBuffer: commandBuffer,
                pipelineState: pipelineState,
                source: sourceTexture,
                destination: destinationTexture,
                bloomIntensity: Float(globalParams?.bloomIntensity ?? bloomIntensity)
            )
        } else {
            copyTexture(commandBuffer: commandBuffer, source: sourceTexture, destination: destinationTexture)
        }

        if syphonEnabled {
            if syphonOutput == nil, let device {
                syphonOutput = SyphonOutput(device: device, name: "RealityKitVJKitchenSink")
            }
            syphonOutput?.publish(texture: destinationTexture, commandBuffer: commandBuffer, flipped: false)
        } else {
            syphonOutput?.stop()
            syphonOutput = nil
        }
    }

    private func ensureDevice(_ device: MTLDevice?) {
        guard self.device == nil else { return }
        self.device = device
        guard let device else { return }
        do {
            if let library = try? device.makeDefaultLibrary(bundle: .module) {
                if let kernel = library.makeFunction(name: "postProcessKernel") {
                    pipelineState = try device.makeComputePipelineState(function: kernel)
                }
            }
        } catch {
            pipelineState = nil
        }
    }

    private func encodePostProcess(
        commandBuffer: MTLCommandBuffer,
        pipelineState: MTLComputePipelineState,
        source: MTLTexture,
        destination: MTLTexture,
        bloomIntensity: Float
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        var intensity = bloomIntensity
        encoder.setBytes(&intensity, length: MemoryLayout<Float>.size, index: 0)

        let width = pipelineState.threadExecutionWidth
        let height = pipelineState.maxTotalThreadsPerThreadgroup / width
        let threadsPerGroup = MTLSize(width: width, height: height, depth: 1)
        let threadsPerGrid = MTLSize(width: destination.width, height: destination.height, depth: 1)
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
    }

    private func copyTexture(commandBuffer: MTLCommandBuffer, source: MTLTexture, destination: MTLTexture) {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else { return }
        let size = MTLSize(width: min(source.width, destination.width), height: min(source.height, destination.height), depth: 1)
        encoder.copy(
            from: source,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: .init(x: 0, y: 0, z: 0),
            sourceSize: size,
            to: destination,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: .init(x: 0, y: 0, z: 0)
        )
        encoder.endEncoding()
    }
}

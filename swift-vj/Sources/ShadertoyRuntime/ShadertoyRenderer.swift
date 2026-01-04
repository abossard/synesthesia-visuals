// ShadertoyRenderer.swift - Multi-pass Shadertoy renderer for Metal
// Supports: single-pass, multi-pass (BufA-D + Image), and feedback/ping-pong

import Foundation
import Metal
import MetalKit
import simd

// MARK: - Render Pass State

/// State for a single render pass including ping-pong buffers
public final class RenderPassState {
    public let passName: PassName
    public let config: PassConfig

    /// Pipeline state for this pass
    public var pipelineState: MTLRenderPipelineState?

    /// Render target textures (ping-pong pair if needed)
    public var currentTexture: MTLTexture?
    public var previousTexture: MTLTexture?

    /// Current texture dimensions
    public var width: Int = 0
    public var height: Int = 0

    /// Which texture is current (for ping-pong)
    public var pingPongIndex: Int = 0

    init(passName: PassName, config: PassConfig) {
        self.passName = passName
        self.config = config
    }

    /// Swap ping-pong textures
    public func swapPingPong() {
        swap(&currentTexture, &previousTexture)
        pingPongIndex = 1 - pingPongIndex
    }
}

// MARK: - Shader Instance

/// Loaded shader with all passes ready for rendering
public final class ShaderInstance: @unchecked Sendable {
    public let name: String
    public let folder: ShaderFolder
    public let metadata: ShaderMetadata

    /// Pass states in render order
    public var passes: [RenderPassState]

    /// Uniform data
    public var uniforms: ShadertoyUniforms

    /// Frame counter
    public var frameCount: Int32 = 0

    /// Time tracking
    public var startTime: Date = Date()
    public var lastFrameTime: Date = Date()

    init(folder: ShaderFolder) {
        self.name = folder.name
        self.folder = folder
        self.metadata = folder.metadata
        self.passes = folder.metadata.sortedPasses.map { RenderPassState(passName: $0.name, config: $0) }
        self.uniforms = ShadertoyUniforms()
    }

    /// Get pass state by name
    public func pass(named name: PassName) -> RenderPassState? {
        passes.first { $0.passName == name }
    }

    /// Reset timing
    public func resetTime() {
        startTime = Date()
        lastFrameTime = Date()
        frameCount = 0
        uniforms.iTime = 0
        uniforms.iFrame = 0
    }
}

// MARK: - Shadertoy Renderer

/// Main renderer for Shadertoy shaders with multi-pass support
public final class ShadertoyRenderer: NSObject, MTKViewDelegate {

    // MARK: - Properties

    /// Metal device
    public let device: MTLDevice

    /// Command queue
    public let commandQueue: MTLCommandQueue

    /// Resource manager
    public let resourceManager: ResourceManager

    /// Currently loaded shader
    public private(set) var currentShader: ShaderInstance?

    /// Viewport dimensions
    public private(set) var viewportWidth: Int = 1280
    public private(set) var viewportHeight: Int = 720

    /// Mouse state
    public var mousePosition: SIMD2<Float> = SIMD2(0, 0)
    public var mousePressed: Bool = false
    public var mouseClicked: Bool = false

    /// Audio uniforms (external update)
    public var audioUniforms: (bass: Float, lowMid: Float, mid: Float, highs: Float,
                               energyFast: Float, energySlow: Float, beat: Float, level: Float,
                               kickEnv: Float, kickPulse: Float, bpm: Float, confidence: Float)?

    // MARK: - Private Properties

    /// Fullscreen triangle vertex buffer
    private var vertexBuffer: MTLBuffer?

    /// Uniform buffer
    private var uniformBuffer: MTLBuffer?

    /// Metal shader library cache
    private var libraryCache: [String: MTLLibrary] = [:]

    /// Dummy resources for unbound channels
    private var dummyResources: DummyResources?

    /// Sampler cache
    private var samplerCache: SamplerCache?

    // MARK: - Initialization

    public init?(device: MTLDevice) {
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.commandQueue = commandQueue

        self.resourceManager = ResourceManager(device: device)

        super.init()

        setupResources()
    }

    private func setupResources() {
        dummyResources = DummyResources(device: device)
        samplerCache = SamplerCache(device: device)

        // Create fullscreen triangle vertices
        // Using a single triangle that covers the screen (more efficient than quad)
        let vertices: [Float] = [
            // Position (x, y), TexCoord (u, v)
            -1.0, -1.0,  0.0, 1.0,  // bottom-left
             3.0, -1.0,  2.0, 1.0,  // bottom-right (extends past screen)
            -1.0,  3.0,  0.0, -1.0  // top-left (extends past screen)
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared)

        // Create uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<ShadertoyUniformBuffer>.stride, options: .storageModeShared)
    }

    // MARK: - Shader Loading

    /// Load a shader from a folder
    public func loadShader(from folder: ShaderFolder) async throws {
        let instance = ShaderInstance(folder: folder)

        // Load and compile each pass
        for passState in instance.passes {
            try await loadPass(passState, in: instance)
        }

        // Set as current
        currentShader = instance
        instance.resetTime()

        // Allocate render targets
        resizeRenderTargets()
    }

    /// Load a shader from compiled MSL files
    public func loadShader(from buildDirectory: URL, shaderName: String, metadata: ShaderMetadata) async throws {
        // Create a temporary shader folder reference
        let folderURL = buildDirectory.appendingPathComponent(shaderName)

        // Create instance
        let instance = ShaderInstance(folder: try ShaderFolder(url: folderURL))

        // Load each pass from compiled MSL
        for passConfig in metadata.sortedPasses {
            let passState = RenderPassState(passName: passConfig.name, config: passConfig)

            let mslPath = folderURL.appendingPathComponent("\(passConfig.name.rawValue).metal")
            if FileManager.default.fileExists(atPath: mslPath.path) {
                let mslSource = try String(contentsOf: mslPath, encoding: .utf8)
                let library = try device.makeLibrary(source: mslSource, options: nil)

                let pipelineState = try createPipelineState(from: library)
                passState.pipelineState = pipelineState
            }

            instance.passes.append(passState)
        }

        currentShader = instance
        instance.resetTime()
        resizeRenderTargets()
    }

    /// Load a single pass
    private func loadPass(_ passState: RenderPassState, in instance: ShaderInstance) async throws {
        guard let sourceURL = instance.folder.sourceURL(for: passState.passName) else {
            throw ShadertoyError.sourceNotFound(passState.passName.rawValue)
        }

        let originalSource = try String(contentsOf: sourceURL, encoding: .utf8)

        // Load common if present
        var commonSource: String? = nil
        if let commonURL = instance.folder.commonURL {
            commonSource = try String(contentsOf: commonURL, encoding: .utf8)
        }

        // Generate wrapper
        let generator = WrapperGeneratorFactory.generator(for: passState.config)
        let wrappedGLSL = generator.generateWrapper(originalSource: originalSource, commonSource: commonSource)

        // For now, we'll use the inline Metal conversion
        // In production, this would use the SPIR-V pipeline
        let metalSource = convertToMetal(glsl: wrappedGLSL, passConfig: passState.config)

        do {
            let library = try device.makeLibrary(source: metalSource, options: nil)
            let pipelineState = try createPipelineState(from: library)
            passState.pipelineState = pipelineState
        } catch {
            // Try simplified conversion
            let simplifiedMetal = createFallbackMetal(for: passState.passName)
            let library = try device.makeLibrary(source: simplifiedMetal, options: nil)
            passState.pipelineState = try createPipelineState(from: library)
            print("[ShadertoyRenderer] Using fallback shader for \(passState.passName.rawValue): \(error)")
        }
    }

    /// Create pipeline state from library
    private func createPipelineState(from library: MTLLibrary) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Render Target Management

    /// Resize render targets for all passes
    private func resizeRenderTargets() {
        guard let shader = currentShader else { return }

        for passState in shader.passes {
            let (width, height) = passState.config.output.dimensions(
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight
            )

            // Only reallocate if size changed
            if width != passState.width || height != passState.height {
                passState.width = width
                passState.height = height

                // Create render target
                passState.currentTexture = createRenderTarget(width: width, height: height)

                // Create second texture if ping-pong needed
                if passState.config.requiresPingPong {
                    passState.previousTexture = createRenderTarget(width: width, height: height)
                }
            }
        }
    }

    private func createRenderTarget(width: Int, height: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private

        return device.makeTexture(descriptor: descriptor)
    }

    // MARK: - Rendering

    /// Render a frame to a texture or view
    public func render(to drawable: CAMetalDrawable? = nil, commandBuffer: MTLCommandBuffer? = nil) {
        guard let shader = currentShader else { return }

        let cmdBuffer = commandBuffer ?? commandQueue.makeCommandBuffer()
        guard let cmdBuffer = cmdBuffer else { return }

        // Update uniforms
        updateUniforms(shader: shader)

        // Render passes in order: BufA -> BufB -> BufC -> BufD -> Image
        for passState in shader.passes {
            if passState.passName == .image {
                // Final pass renders to drawable or current texture
                if let drawable = drawable {
                    renderPass(passState, shader: shader, to: drawable.texture, commandBuffer: cmdBuffer)
                } else if let texture = passState.currentTexture {
                    renderPass(passState, shader: shader, to: texture, commandBuffer: cmdBuffer)
                }
            } else {
                // Buffer passes render to their textures
                guard let texture = passState.currentTexture else { continue }
                renderPass(passState, shader: shader, to: texture, commandBuffer: cmdBuffer)

                // Swap ping-pong if needed
                if passState.config.requiresPingPong {
                    passState.swapPingPong()
                }
            }
        }

        // Present if we have a drawable
        if let drawable = drawable {
            cmdBuffer.present(drawable)
        }

        cmdBuffer.commit()

        // Update frame counter
        shader.frameCount += 1
    }

    /// Render a single pass
    private func renderPass(_ passState: RenderPassState, shader: ShaderInstance, to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let pipelineState = passState.pipelineState,
              let uniformBuffer = uniformBuffer,
              let vertexBuffer = vertexBuffer else { return }

        // Update uniforms for this pass resolution
        updateUniformsForPass(passState, shader: shader)

        // Create render pass descriptor
        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = texture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)

        // Bind channel textures
        bindChannels(passState, shader: shader, encoder: encoder)

        // Draw fullscreen triangle
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Bind channel textures for a pass
    private func bindChannels(_ passState: RenderPassState, shader: ShaderInstance, encoder: MTLRenderCommandEncoder) {
        guard let dummyResources = dummyResources,
              let samplerCache = samplerCache else { return }

        for channel in passState.config.channels {
            let textureIndex = channel.index + 1  // 1-4 for iChannel0-3

            var texture: MTLTexture? = nil

            switch channel.source {
            case .none:
                texture = dummyResources.blackTexture2D

            case .buffer:
                // Get current frame output from referenced buffer
                if let ref = channel.ref,
                   let passName = PassName(rawValue: ref),
                   let bufferPass = shader.pass(named: passName) {
                    texture = bufferPass.currentTexture
                }

            case .bufferPrev:
                // Get previous frame output (ping-pong)
                if let ref = channel.ref,
                   let passName = PassName(rawValue: ref),
                   let bufferPass = shader.pass(named: passName) {
                    texture = bufferPass.previousTexture ?? bufferPass.currentTexture
                }

            case .file:
                // TODO: Load from file cache
                texture = dummyResources.blackTexture2D

            case .noise:
                // TODO: Generate noise texture
                texture = dummyResources.blackTexture2D

            case .keyboard:
                // TODO: Create keyboard state texture
                texture = dummyResources.blackTexture2D

            case .video:
                // TODO: Video input
                texture = dummyResources.blackTexture2D

            case .audioFFT:
                // TODO: Audio FFT texture
                texture = dummyResources.blackTexture2D
            }

            encoder.setFragmentTexture(texture ?? dummyResources.blackTexture2D, index: textureIndex)

            // Bind sampler
            let sampler = samplerCache.sampler(filter: channel.filter, wrap: channel.wrap)
            encoder.setFragmentSamplerState(sampler ?? dummyResources.defaultSampler, index: channel.index)
        }
    }

    // MARK: - Uniform Updates

    private func updateUniforms(shader: ShaderInstance) {
        let now = Date()
        let deltaTime = Float(now.timeIntervalSince(shader.lastFrameTime))
        let totalTime = Float(now.timeIntervalSince(shader.startTime))

        shader.lastFrameTime = now

        shader.uniforms.updateTime(time: totalTime, deltaTime: deltaTime, frame: shader.frameCount)
        shader.uniforms.updateDate()
        shader.uniforms.updateResolution(width: Float(viewportWidth), height: Float(viewportHeight))
        shader.uniforms.updateMouse(x: mousePosition.x, y: mousePosition.y, pressed: mousePressed, clicked: mouseClicked)

        // Reset click state after processing
        mouseClicked = false

        // Update audio if available
        if let audio = audioUniforms {
            shader.uniforms.updateAudio(
                bass: audio.bass, lowMid: audio.lowMid, mid: audio.mid, highs: audio.highs,
                energyFast: audio.energyFast, energySlow: audio.energySlow, beat: audio.beat, level: audio.level,
                kickEnv: audio.kickEnv, kickPulse: audio.kickPulse, bpm: audio.bpm, confidence: audio.confidence
            )
        }
    }

    private func updateUniformsForPass(_ passState: RenderPassState, shader: ShaderInstance) {
        guard let uniformBuffer = uniformBuffer else { return }

        // Update resolution to pass resolution
        var uniforms = shader.uniforms
        uniforms.iResolution = SIMD3<Float>(Float(passState.width), Float(passState.height), 1.0)

        // Update channel resolutions
        for (index, channel) in passState.config.channels.enumerated() {
            var width: Float = 1
            var height: Float = 1

            if channel.source == .buffer || channel.source == .bufferPrev,
               let ref = channel.ref,
               let passName = PassName(rawValue: ref),
               let bufferPass = shader.pass(named: passName) {
                width = Float(bufferPass.width)
                height = Float(bufferPass.height)
            }

            uniforms.updateChannelResolution(index: index, width: width, height: height)
        }

        // Write to buffer
        let buffer = ShadertoyUniformBuffer(from: uniforms)
        let ptr = uniformBuffer.contents().bindMemory(to: ShadertoyUniformBuffer.self, capacity: 1)
        ptr.pointee = buffer
    }

    // MARK: - MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportWidth = Int(size.width)
        viewportHeight = Int(size.height)
        resizeRenderTargets()
    }

    public func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable else { return }
        render(to: drawable)
    }

    // MARK: - Metal Conversion (Simplified)

    /// Convert GLSL to Metal (simplified inline version)
    /// In production, use the SPIR-V pipeline for accurate conversion
    private func convertToMetal(glsl: String, passConfig: PassConfig) -> String {
        // This is a placeholder - the real conversion uses SPIR-V
        return createFallbackMetal(for: passConfig.name)
    }

    /// Create fallback Metal shader
    private func createFallbackMetal(for passName: PassName) -> String {
        """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        struct ShadertoyUniforms {
            float3 iResolution;
            float _pad0;
            float iTime;
            float iTimeDelta;
            int iFrame;
            float iFrameRate;
            float4 iMouse;
            float4 iDate;
            float iSampleRate;
            float3 _pad1;
            float iChannelTime0, iChannelTime1, iChannelTime2, iChannelTime3;
            float3 iChannelResolution0; float _pad2;
            float3 iChannelResolution1; float _pad3;
            float3 iChannelResolution2; float _pad4;
            float3 iChannelResolution3; float _pad5;
            float4 iAudioBands;
            float4 iAudioEnergy;
            float4 iKick;
        };

        vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                     constant float4 *vertices [[buffer(0)]]) {
            VertexOut out;
            float4 v = vertices[vertexID];
            out.position = float4(v.xy, 0.0, 1.0);
            out.uv = v.zw;
            return out;
        }

        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant ShadertoyUniforms &u [[buffer(0)]],
                                      texture2d<float> iChannel0 [[texture(1)]],
                                      texture2d<float> iChannel1 [[texture(2)]],
                                      texture2d<float> iChannel2 [[texture(3)]],
                                      texture2d<float> iChannel3 [[texture(4)]],
                                      sampler s0 [[sampler(0)]],
                                      sampler s1 [[sampler(1)]],
                                      sampler s2 [[sampler(2)]],
                                      sampler s3 [[sampler(3)]]) {
            float2 fragCoord = in.position.xy;
            float2 uv = fragCoord / u.iResolution.xy;

            // Fallback procedural pattern
            float t = u.iTime;
            float2 p = uv * 2.0 - 1.0;
            p.x *= u.iResolution.x / u.iResolution.y;

            float r = length(p);
            float a = atan2(p.y, p.x);

            float3 col = float3(0.0);

            // Audio-reactive rings
            float bass = u.iAudioBands.x;
            float mid = u.iAudioBands.z;
            float highs = u.iAudioBands.w;

            float ring1 = smoothstep(0.3 + bass * 0.2, 0.32 + bass * 0.2, r);
            ring1 *= 1.0 - smoothstep(0.32 + bass * 0.2, 0.34 + bass * 0.2, r);

            float ring2 = smoothstep(0.5 + mid * 0.2, 0.52 + mid * 0.2, r);
            ring2 *= 1.0 - smoothstep(0.52 + mid * 0.2, 0.54 + mid * 0.2, r);

            float spiral = sin(a * 8.0 + t * 2.0 + r * 10.0) * 0.5 + 0.5;

            col.r = ring1 + spiral * highs;
            col.g = ring2 + spiral * mid * 0.5;
            col.b = spiral * bass;

            // Kick pulse
            col += u.iKick.x * 0.1;

            return float4(col, 1.0);
        }
        """
    }
}

// MARK: - Errors

public enum ShadertoyError: Error {
    case sourceNotFound(String)
    case compilationFailed(String)
    case invalidMetadata(String)
}

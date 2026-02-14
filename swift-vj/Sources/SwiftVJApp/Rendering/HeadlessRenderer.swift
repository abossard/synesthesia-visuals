// HeadlessRenderer.swift - Single command buffer render loop for VJ tiles
// Renders all tiles headless to textures, publishes to Syphon on same buffer, then commits once.
// UI previews consume via Syphon clients only.

import Foundation
import Metal
import MetalKit
import CoreGraphics
import AppKit
import SwiftUI
import SyphonKit

// MARK: - Tile Renderer Protocol

/// Protocol for headless tile rendering (no MTKView)
protocol TileRenderer {
    var name: String { get }
    var texture: MTLTexture? { get }
    func render(commandBuffer: MTLCommandBuffer, uniforms: ShaderUniforms)
}

// MARK: - Text Animation Mode

/// Available text animation modes for lyrics/text tiles
enum TextAnimationMode: String, CaseIterable, Identifiable, Sendable {
    case instant = "Instant"
    case fadeInOut = "Fade In/Out"
    case waveDissolve = "Wave Dissolve"
    case blurPop = "Blur Pop"
    case springBounce = "Spring Bounce"
    case typewriter = "Typewriter"
    case glowPulse = "Glow Pulse"
    case rainbowWave = "Rainbow Wave"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .instant: return "No animation, instant text change"
        case .fadeInOut: return "Simple opacity fade"
        case .waveDissolve: return "Characters dissolve left-to-right with blur"
        case .blurPop: return "Characters blur in with scale"
        case .springBounce: return "Characters bounce in with spring physics"
        case .typewriter: return "Characters appear one by one"
        case .glowPulse: return "Pulsing glow effect"
        case .rainbowWave: return "Hue rotation wave across text"
        }
    }
}

// MARK: - Shader Renderer

/// Headless shader renderer - loads from metallib, renders to offscreen texture
final class ShaderRenderer: TileRenderer {
    let name: String
    private(set) var texture: MTLTexture?
    
    private let device: MTLDevice
    private(set) var pipelineState: MTLRenderPipelineState?
    private var uniformBuffer: MTLBuffer?
    private var vertexBuffer: MTLBuffer?
    private var metallibLibrary: MTLLibrary?
    
    private(set) var currentShaderName: String = ""
    
    init(name: String, device: MTLDevice, width: Int = 1280, height: Int = 720) {
        self.name = name
        self.device = device
        setupTexture(width: width, height: height)
        setupBuffers()
        loadMetalLib()
    }
    
    private func setupTexture(width: Int, height: Int) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        texture = device.makeTexture(descriptor: descriptor)
    }
    
    private func setupBuffers() {
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<ShaderUniforms>.stride,
            options: .storageModeShared
        )
        
        let vertices: [Float] = [
            -1, 1, 0, 0,   // top-left
             1, 1, 1, 0,   // top-right
            -1, -1, 0, 1,  // bottom-left
             1, -1, 1, 1,  // bottom-right
        ]
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }
    
    private func loadMetalLib() {
        let execURL = Bundle.main.bundleURL
        let searchPaths = [
            execURL.appendingPathComponent("Shaders.metallib").path,
            execURL.appendingPathComponent("Contents/Resources/Shaders.metallib").path,
            Bundle.main.path(forResource: "Shaders", ofType: "metallib") ?? "",
            "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJApp/Resources/Shaders.metallib",
            "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Build/Shaders.metallib"
        ].filter { !$0.isEmpty }
        
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                if let lib = try? device.makeLibrary(URL: URL(fileURLWithPath: path)) {
                    metallibLibrary = lib
                    print("[ShaderRenderer:\(name)] Loaded metallib: \(path)")
                    return
                }
            }
        }
        print("[ShaderRenderer:\(name)] Failed to load metallib")
    }
    
    /// Load a shader by name. Returns true if successful, false if shader not found.
    @discardableResult
    func loadShader(name shaderName: String) -> Bool {
        guard let library = metallibLibrary else {
            print("[ShaderRenderer:\(name)] ❌ FAILED: No metallib loaded")
            return false
        }
        
        let fragmentName = "fragment_\(shaderName)"
        
        guard let fragmentFunction = library.makeFunction(name: fragmentName) else {
            print("[ShaderRenderer:\(name)] ❌ FAILED: Fragment function '\(fragmentName)' not found in metallib")
            // List available functions for debugging
            let available = library.functionNames.filter { $0.hasPrefix("fragment_") }.prefix(10)
            print("[ShaderRenderer:\(name)] Available (first 10): \(available.joined(separator: ", "))")
            return false
        }
        
        guard let vertexFunction = library.makeFunction(name: "vertex_fullscreen") else {
            print("[ShaderRenderer:\(name)] ❌ FAILED: Vertex function 'vertex_fullscreen' not found")
            return false
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            currentShaderName = shaderName
            print("[ShaderRenderer:\(name)] ✓ Loaded: \(fragmentName)")
            return true
        } catch {
            print("[ShaderRenderer:\(name)] ❌ Pipeline error: \(error)")
            return false
        }
    }
    
    func render(commandBuffer: MTLCommandBuffer, uniforms: ShaderUniforms) {
        guard let texture = texture else {
            // print("[ShaderRenderer:\(name)] No texture")
            return
        }
        guard let pipelineState = pipelineState else {
            // Only log once per shader to avoid spam
            return
        }
        guard let uniformBuffer = uniformBuffer else {
            return
        }
        
        // Update uniforms
        var u = uniforms
        memcpy(uniformBuffer.contents(), &u, MemoryLayout<ShaderUniforms>.stride)
        
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
}

// MARK: - SwiftUI Text Renderers

/// Wave dissolve renderer - characters fade/blur from left to right
struct WaveDissolveRenderer: SwiftUI.TextRenderer, Animatable {
    var progress: Double  // 0 = all visible, 1 = all dissolved
    var direction: Double = 1.0  // 1 = left-to-right, -1 = right-to-left

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            let count = run.count
            let delay = 1.0 / Double(max(count, 1))

            for (index, slice) in run.enumerated() {
                let charProgress: Double
                if direction > 0 {
                    charProgress = max(0, min(1, (progress - Double(index) * delay) / (1.0 - Double(count - 1) * delay)))
                } else {
                    let reverseIndex = count - 1 - index
                    charProgress = max(0, min(1, (progress - Double(reverseIndex) * delay) / (1.0 - Double(count - 1) * delay)))
                }

                var copy = context
                copy.opacity = 1.0 - charProgress
                copy.addFilter(.blur(radius: charProgress * 10))
                copy.draw(slice)
            }
        }
    }
}

/// Blur pop renderer - characters blur in with scale effect
struct BlurPopRenderer: SwiftUI.TextRenderer, Animatable {
    var progress: Double  // 0 = hidden, 1 = fully visible
    var staggerDelay: Double = 0.05

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            for (index, slice) in run.enumerated() {
                let delay = Double(index) * staggerDelay
                let charProgress = max(0, min(1, (progress - delay) / (1.0 - delay * 0.5)))

                let bounds = slice.typographicBounds.rect
                let centerX = bounds.midX
                let centerY = bounds.midY

                var copy = context
                let scale = 0.5 + charProgress * 0.5
                let blur = (1.0 - charProgress) * 8

                copy.translateBy(x: centerX, y: centerY)
                copy.scaleBy(x: scale, y: scale)
                copy.translateBy(x: -centerX, y: -centerY)

                copy.opacity = charProgress
                copy.addFilter(.blur(radius: blur))
                copy.draw(slice)
            }
        }
    }
}

/// Spring bounce renderer - characters bounce in with spring physics
struct SpringBounceRenderer: SwiftUI.TextRenderer, Animatable {
    var progress: Double
    var bounceHeight: Double = 20

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private func springValue(_ t: Double) -> Double {
        let omega: Double = 10
        let zeta: Double = 0.7
        let damping = exp(-zeta * omega * t)
        let oscillation = cos(omega * sqrt(1 - zeta * zeta) * t)
        return 1.0 - damping * oscillation
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            for (index, slice) in run.enumerated() {
                let delay = Double(index) * 0.03
                let charTime = max(0, progress - delay)
                let spring = springValue(charTime * 3)

                let yOffset = bounceHeight * (1.0 - spring)

                var copy = context
                copy.translateBy(x: 0, y: -yOffset)
                copy.opacity = min(1, charTime * 5)
                copy.draw(slice)
            }
        }
    }
}

/// Typewriter renderer - characters appear one by one
struct TypewriterRenderer: SwiftUI.TextRenderer, Animatable {
    var progress: Double  // 0-1 maps to characters revealed

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            let count = run.count
            let charsToShow = Int(progress * Double(count))

            for (index, slice) in run.enumerated() {
                if index < charsToShow {
                    context.draw(slice)
                } else if index == charsToShow {
                    let charProgress = (progress * Double(count)) - Double(index)
                    var copy = context
                    copy.opacity = charProgress
                    copy.draw(slice)
                }
            }
        }
    }
}

/// Glow pulse renderer - pulsing glow synced to beat
struct GlowPulseRenderer: SwiftUI.TextRenderer, Animatable {
    var intensity: Double  // 0-1
    var glowRadius: Double = 12

    var animatableData: Double {
        get { intensity }
        set { intensity = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        if intensity > 0.01 {
            var glowContext = context
            glowContext.addFilter(.blur(radius: glowRadius * intensity))
            glowContext.opacity = intensity * 0.6

            for run in layout.flattenedRuns {
                for slice in run {
                    glowContext.draw(slice)
                }
            }
        }

        for run in layout.flattenedRuns {
            for slice in run {
                context.draw(slice)
            }
        }
    }
}

/// Rainbow wave renderer - hue rotation wave across text
struct RainbowWaveRenderer: SwiftUI.TextRenderer, Animatable {
    var phase: Double
    var waveSpeed: Double = 0.6

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for run in layout.flattenedRuns {
            for (index, slice) in run.enumerated() {
                let hueOffset = (Double(index) * 0.1 + phase * waveSpeed).truncatingRemainder(dividingBy: 1.0)

                var copy = context
                copy.addFilter(.hueRotation(Angle(degrees: hueOffset * 360)))
                copy.draw(slice)
            }
        }
    }
}

// MARK: - SwiftUI Text Tile Renderer

private final class RenderResources: @unchecked Sendable {
    let outputTexture: MTLTexture
    let stagingTexture: MTLTexture
    let pipelineState: MTLRenderPipelineState
    let vertexBuffer: MTLBuffer
    let samplerState: MTLSamplerState
    var hasValidContent: Bool = false

    init(outputTexture: MTLTexture, stagingTexture: MTLTexture,
         pipelineState: MTLRenderPipelineState, vertexBuffer: MTLBuffer,
         samplerState: MTLSamplerState) {
        self.outputTexture = outputTexture
        self.stagingTexture = stagingTexture
        self.pipelineState = pipelineState
        self.vertexBuffer = vertexBuffer
        self.samplerState = samplerState
    }
}

@MainActor
final class SwiftUITextTileRenderer: TileRenderer {
    let name: String

    nonisolated(unsafe) private var resources: RenderResources?

    nonisolated var texture: MTLTexture? {
        resources?.outputTexture
    }

    private let device: MTLDevice
    private let width: Int
    private let height: Int

    private var currentView: AnyView?
    private var lastRenderedContent: String = ""

    init(name: String, device: MTLDevice, width: Int = 1280, height: Int = 720) {
        self.name = name
        self.device = device
        self.width = width
        self.height = height
        setupResources()
    }

    private func setupResources() {
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        outputDescriptor.usage = [.renderTarget, .shaderRead]
        outputDescriptor.storageMode = .private

        let stagingDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        stagingDescriptor.usage = [.shaderRead]
        stagingDescriptor.storageMode = .managed

        guard let outputTexture = device.makeTexture(descriptor: outputDescriptor),
              let stagingTexture = device.makeTexture(descriptor: stagingDescriptor) else {
            print("[SwiftUITextTileRenderer:\(name)] Failed to create textures")
            return
        }

        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex VertexOut swiftUICopyVertex(uint vid [[vertex_id]],
                                            constant float4 *vertices [[buffer(0)]]) {
            float4 v = vertices[vid];
            VertexOut out;
            out.position = float4(v.xy, 0, 1);
            out.uv = v.zw;
            return out;
        }

        fragment float4 swiftUICopyFragment(VertexOut in [[stage_in]],
                                             texture2d<float> tex [[texture(0)]],
                                             sampler s [[sampler(0)]]) {
            return tex.sample(s, in.uv);
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertexFunc = library.makeFunction(name: "swiftUICopyVertex"),
                  let fragmentFunc = library.makeFunction(name: "swiftUICopyFragment") else { return }

            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

            let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

            let vertices: [Float] = [
                -1,  1, 0, 0,
                 1,  1, 1, 0,
                -1, -1, 0, 1,
                 1, -1, 1, 1,
            ]
            guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared) else { return }

            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else { return }

            resources = RenderResources(
                outputTexture: outputTexture,
                stagingTexture: stagingTexture,
                pipelineState: pipelineState,
                vertexBuffer: vertexBuffer,
                samplerState: samplerState
            )
            print("[SwiftUITextTileRenderer:\(name)] Resources initialized")
        } catch {
            print("[SwiftUITextTileRenderer:\(name)] Pipeline error: \(error)")
        }
    }

    // MARK: - Content Update

    func update(contentHash: String, viewBuilder: () -> AnyView) {
        guard contentHash != lastRenderedContent else { return }
        currentView = viewBuilder()
        captureSwiftUIView()
        lastRenderedContent = contentHash
    }

    func forceCapture() {
        captureSwiftUIView()
    }

    private func captureSwiftUIView() {
        guard let resources = resources else { return }
        guard let cgImage = captureView() else { return }
        uploadCGImage(cgImage, to: resources.stagingTexture)
        resources.hasValidContent = true
    }

    private func captureView() -> CGImage? {
        guard let view = currentView else { return nil }
        let renderer = SwiftUI.ImageRenderer(content: view)
        renderer.scale = 2.0
        return renderer.cgImage
    }

    private func uploadCGImage(_ cgImage: CGImage, to texture: MTLTexture) {
        let bytesPerRow = width * 4

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return }

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: bytesPerRow)
    }

    // MARK: - TileRenderer Protocol (render thread safe)

    nonisolated func render(commandBuffer: MTLCommandBuffer, uniforms: ShaderUniforms) {
        guard let resources = resources, resources.hasValidContent else { return }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = resources.outputTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }

        encoder.setRenderPipelineState(resources.pipelineState)
        encoder.setVertexBuffer(resources.vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(resources.stagingTexture, index: 0)
        encoder.setFragmentSamplerState(resources.samplerState, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
}

// MARK: - Text.Layout Extension

extension Text.Layout {
    var flattenedRuns: some RandomAccessCollection<Text.Layout.Run> {
        self.flatMap { line in line }
    }
}

// MARK: - Image Renderer

/// Headless image renderer with crossfade support
final class ImageRenderer: TileRenderer {
    let name = "image"
    private(set) var texture: MTLTexture?
    
    private let device: MTLDevice
    private let width: Int = 1280
    private let height: Int = 720
    
    // Image textures
    private var currentImageTexture: MTLTexture?
    private var nextImageTexture: MTLTexture?
    
    // Crossfade pipeline
    private var blendPipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var samplerState: MTLSamplerState?
    private var uniformBuffer: MTLBuffer?
    
    // State
    var imageState: ImageDisplayState = .empty {
        didSet { updateImageTextures() }
    }
    
    private var lastBeatCount: Int = 0
    private var beatCounter: Int = 0
    
    // Crossfade animation
    private var currentCrossfade: Float = 0.0
    private let crossfadeDuration: Float = 0.5  // seconds
    
    // Logger closure for UI logging
    var logger: ((String) -> Void)?
    
    // Track first successful render
    private var hasRenderedFirstFrame: Bool = false
    
    init(device: MTLDevice) {
        self.device = device
        setupTexture()
        setupBlendPipeline()
        setupBuffers()
        logger?("[ImageRenderer] Initialized with resolution \(width)x\(height)")
    }
    
    private func setupTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        texture = device.makeTexture(descriptor: descriptor)
        logger?("[ImageRenderer] Created output texture")
    }
    
    private func setupBuffers() {
        // Fullscreen quad vertices
        let vertices: [Float] = [
            -1, 1, 0, 0,   // top-left
             1, 1, 1, 0,   // top-right
            -1, -1, 0, 1,  // bottom-left
             1, -1, 1, 1,  // bottom-right
        ]
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        // Uniform buffer for ImageUniforms (crossfade + aspect ratios)
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<Float>.stride * 4,
            options: .storageModeShared
        )
        
        // Sampler state
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }
    
    private func setupBlendPipeline() {
        // Create blend shader with cover mode scaling
        let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        struct ImageUniforms {
            float crossfade;
            float outputAspect;  // width/height of output (16/9 = 1.777)
            float currentAspect; // width/height of current texture
            float nextAspect;    // width/height of next texture
        };

        vertex VertexOut vertex_image(uint vid [[vertex_id]],
                                       constant float4* vertices [[buffer(0)]]) {
            VertexOut out;
            float4 v = vertices[vid];
            out.position = float4(v.xy, 0, 1);
            out.texCoord = v.zw;
            return out;
        }

        // Cover mode: scale and crop to fill output, centered
        float2 coverUV(float2 uv, float texAspect, float outAspect) {
            float2 scale = float2(1.0);
            if (texAspect > outAspect) {
                // Texture is wider - crop sides
                scale.x = outAspect / texAspect;
            } else {
                // Texture is taller - crop top/bottom
                scale.y = texAspect / outAspect;
            }
            return (uv - 0.5) * scale + 0.5;
        }

        fragment float4 fragment_image_blend(VertexOut in [[stage_in]],
                                             texture2d<float> currentTex [[texture(0)]],
                                             texture2d<float> nextTex [[texture(1)]],
                                             sampler texSampler [[sampler(0)]],
                                             constant ImageUniforms& uniforms [[buffer(0)]]) {
            // UV coordinates already correct since texture loaded with bottomLeft origin
            float2 uv = in.texCoord;

            // Apply cover mode UV transform
            float2 currentUV = coverUV(uv, uniforms.currentAspect, uniforms.outputAspect);
            float2 nextUV = coverUV(uv, uniforms.nextAspect, uniforms.outputAspect);

            float4 current = currentTex.sample(texSampler, currentUV);
            float4 next = nextTex.sample(texSampler, nextUV);
            return mix(current, next, uniforms.crossfade);
        }
        """
        
        guard let library = try? device.makeLibrary(source: source, options: nil),
              let vertexFunction = library.makeFunction(name: "vertex_image"),
              let fragmentFunction = library.makeFunction(name: "fragment_image_blend") else {
            logger?("[ImageRenderer] ❌ Failed to create blend shader")
            return
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            blendPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            logger?("[ImageRenderer] ✓ Blend pipeline created")
        } catch {
            logger?("[ImageRenderer] ❌ Pipeline error: \(error)")
        }
    }
    
    private func updateImageTextures() {
        // Load current image
        if let url = imageState.currentImageURL {
            let filename = url.lastPathComponent
            logger?("[ImageRenderer] Loading current: \(filename)")
            logger?("[ImageRenderer]   Path: \(url.path)")
            currentImageTexture = loadImageTexture(from: url)
            if currentImageTexture != nil {
                logger?("[ImageRenderer] ✓ Current image loaded")
            } else {
                logger?("[ImageRenderer] ❌ Failed to load current image")
            }
        }
        
        // Load next image for crossfade
        if let url = imageState.nextImageURL {
            let filename = url.lastPathComponent
            logger?("[ImageRenderer] Loading next: \(filename)")
            nextImageTexture = loadImageTexture(from: url)
            if nextImageTexture != nil {
                logger?("[ImageRenderer] ✓ Next image loaded")
            }
        }
    }
    
    private func loadImageTexture(from url: URL) -> MTLTexture? {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger?("[ImageRenderer] ❌ Failed to create NSImage from: \(url.lastPathComponent)")
            return nil
        }
        
        let textureLoader = MTKTextureLoader(device: device)
        do {
            // Use .origin: .bottomLeft to load image with correct orientation for Metal
            // This ensures the texture matches expected UV coordinate system
            let texture = try textureLoader.newTexture(cgImage: cgImage, options: [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .SRGB: false,
                .origin: MTKTextureLoader.Origin.bottomLeft
            ])
            return texture
        } catch {
            logger?("[ImageRenderer] ❌ Texture load error: \(error)")
            return nil
        }
    }
    
    func handleBeat(beat4: Int) {
        guard imageState.beatsPerChange > 0 else { return }
        
        // Count beats
        if beat4 != lastBeatCount {
            let prevCounter = beatCounter
            lastBeatCount = beat4
            beatCounter += 1
            
            // Only log when counter changes (not every frame)
            if prevCounter != beatCounter {
                logger?("[ImageRenderer] Beat: \(beatCounter)/\(imageState.beatsPerChange) (beat4=\(beat4))")
            }
            
            // Auto-advance on beat count
            if beatCounter >= imageState.beatsPerChange {
                beatCounter = 0
                logger?("[ImageRenderer] 🔄 Auto-switching image (beat trigger)")
                nextImage()
            }
        }
    }
    
    func nextImage() {
        guard !imageState.folderImages.isEmpty else {
            logger?("[ImageRenderer] ⚠️ Next image: no images loaded")
            return
        }
        let nextIndex = (imageState.folderIndex + 1) % imageState.folderImages.count
        logger?("[ImageRenderer] → Next image: \(nextIndex + 1)/\(imageState.folderImages.count)")
        updateImageState(folderIndex: nextIndex)
    }
    
    func prevImage() {
        guard !imageState.folderImages.isEmpty else {
            logger?("[ImageRenderer] ⚠️ Prev image: no images loaded")
            return
        }
        let prevIndex = (imageState.folderIndex - 1 + imageState.folderImages.count) % imageState.folderImages.count
        logger?("[ImageRenderer] ← Prev image: \(prevIndex + 1)/\(imageState.folderImages.count)")
        updateImageState(folderIndex: prevIndex)
    }
    
    private func updateImageState(folderIndex: Int) {
        guard !imageState.folderImages.isEmpty else { return }
        
        let current = imageState.folderImages[folderIndex]
        let nextIndex = (folderIndex + 1) % imageState.folderImages.count
        let next = imageState.folderImages[nextIndex]
        
        // Reset crossfade animation for new transition
        currentCrossfade = 0.0
        
        imageState = ImageDisplayState(
            currentImageURL: current,
            nextImageURL: next,
            crossfadeProgress: 0.0,
            isFading: true,
            coverMode: imageState.coverMode,
            folderImages: imageState.folderImages,
            folderIndex: folderIndex,
            beatsPerChange: imageState.beatsPerChange
        )
    }
    
    func render(commandBuffer: MTLCommandBuffer, uniforms: ShaderUniforms) {
        guard let texture = texture,
              let pipelineState = blendPipelineState else {
            return
        }
        
        // If no image texture, clear to transparent black
        guard let current = currentImageTexture else {
            let passDescriptor = MTLRenderPassDescriptor()
            passDescriptor.colorAttachments[0].texture = texture
            passDescriptor.colorAttachments[0].loadAction = .clear
            passDescriptor.colorAttachments[0].storeAction = .store
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) {
                encoder.endEncoding()
            }
            return
        }
        
        // Log first successful render
        if !hasRenderedFirstFrame {
            hasRenderedFirstFrame = true
            logger?("[ImageRenderer] 🎬 Rendering to Syphon server 'Image'")
        }
        
        // Animate crossfade (ramp from 0 to 1 when isFading)
        if imageState.isFading && currentCrossfade < 1.0 {
            // Approximate deltaTime from uniforms (speed is audio-reactive, ~1.0 baseline)
            let deltaTime: Float = 1.0 / 60.0  // ~16ms per frame
            currentCrossfade = min(1.0, currentCrossfade + deltaTime / crossfadeDuration)
        } else if !imageState.isFading {
            currentCrossfade = 0.0
        }

        // Calculate aspect ratios for cover mode scaling
        let outputAspect = Float(width) / Float(height)  // 16:9 = 1.777
        let currentAspect = Float(current.width) / Float(current.height)
        let next = nextImageTexture ?? current
        let nextAspect = Float(next.width) / Float(next.height)

        // Update uniforms with aspect ratios
        var imageUniforms = (currentCrossfade, outputAspect, currentAspect, nextAspect)
        if let uniformBuffer = uniformBuffer {
            memcpy(uniformBuffer.contents(), &imageUniforms, MemoryLayout<(Float, Float, Float, Float)>.stride)
        }
        
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(current, index: 0)
        encoder.setFragmentTexture(nextImageTexture ?? current, index: 1)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
}

// MARK: - Headless Renderer

/// Main headless renderer - one command buffer per frame, all tiles rendered and published together
final class HeadlessRenderer {
    // MARK: - Properties
    
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    // Tile renderers
    let shaderRenderer: ShaderRenderer
    let maskRenderer: ShaderRenderer
    let imageRenderer: ImageRenderer
    
    // SwiftUI-based text renderers
    // Set via `setSwiftUITextRenderers` from main thread after init
    private var swiftUILyricsRenderer: SwiftUITextTileRenderer?
    private var swiftUIRefrainRenderer: SwiftUITextTileRenderer?
    private var swiftUISongInfoRenderer: SwiftUITextTileRenderer?
    
    // Audio-reactive state
    private var audioTime: Float = 0
    private var rampedSpeed: Float = 0.02
    private var beatBoostAccum: Float = 0.0
    private var smoothedAudioSpeed: Float = 0.02
    
    // Smoothed mouse (exponential smoothing to eliminate jitter)
    private var smoothedMouse: SIMD2<Float> = SIMD2(0.5, 0.5)
    private var mouseVelocity: SIMD2<Float> = SIMD2(0, 0)  // For momentum
    
    // Speed constants (from VJUniverse.pde)
    private let baseSpeedFloor: Float = 0.15       // Raised from 0.02 - visible animation without audio
    private let audioSpeedMax: Float = 1.20
    private let speedRampUp: Float = 0.008
    private let speedRampDown: Float = 0.025
    private let bassBoostWeight: Float = 0.35
    private let beatBoostAmount: Float = 0.15
    private let beatBoostDecay: Float = 0.92
    private let audioSpeedSmoothing: Float = 0.85  // Raised from 0.65 - smoother transitions
    
    // Triple buffering
    private let inflightSemaphore = DispatchSemaphore(value: 3)
    
    // Frame timing
    private var lastFrameTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private(set) var frameCount: Int = 0
    
    // MARK: - Init
    
    init(device: MTLDevice, logger: ((String) -> Void)? = nil) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        
        shaderRenderer = ShaderRenderer(name: "shader", device: device)
        maskRenderer = ShaderRenderer(name: "mask", device: device)
        imageRenderer = ImageRenderer(device: device)
        
        // Wire up logger to imageRenderer
        imageRenderer.logger = logger
        logger?("[HeadlessRenderer] Initialized with 6 tiles (shader, mask, lyrics, refrain, songInfo, image)")
    }
    
    // MARK: - SwiftUI Lyrics Renderer Setup
    
    /// Set the SwiftUI-based text renderers (must be called from MainActor)
    @MainActor
    func setSwiftUITextRenderers(
        lyrics: SwiftUITextTileRenderer,
        refrain: SwiftUITextTileRenderer,
        songInfo: SwiftUITextTileRenderer
    ) {
        self.swiftUILyricsRenderer = lyrics
        self.swiftUIRefrainRenderer = refrain
        self.swiftUISongInfoRenderer = songInfo
        print("[HeadlessRenderer] SwiftUI text renderers configured")
    }
    
    /// Get the current SwiftUI lyrics renderer for state updates
    @MainActor
    func getSwiftUILyricsRenderer() -> SwiftUITextTileRenderer? {
        return swiftUILyricsRenderer
    }

    @MainActor
    func getSwiftUIRefrainRenderer() -> SwiftUITextTileRenderer? {
        return swiftUIRefrainRenderer
    }

    @MainActor
    func getSwiftUISongInfoRenderer() -> SwiftUITextTileRenderer? {
        return swiftUISongInfoRenderer
    }

    /// Thread-safe access to lyrics texture
    var lyricsTexture: MTLTexture? {
        swiftUILyricsRenderer?.texture
    }

    var refrainTexture: MTLTexture? {
        swiftUIRefrainRenderer?.texture
    }

    var songInfoTexture: MTLTexture? {
        swiftUISongInfoRenderer?.texture
    }
    
    // MARK: - Render Frame
    
    /// Render all tiles and publish to Syphon on the same command buffer
    /// Thread-safe - can be called from the headless render loop thread
    func renderFrame(
        audioState: AudioState,
        syphonManager: SyphonOutputManager?
    ) {
        // Wait for available command buffer slot (triple buffering)
        _ = inflightSemaphore.wait(timeout: .now() + .milliseconds(16))
        
        // Calculate delta time
        let now = CFAbsoluteTimeGetCurrent()
        var deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now
        frameCount += 1
        
        // Clamp deltaTime
        if deltaTime <= 0 || deltaTime > 0.1 {
            deltaTime = 1.0 / 60.0
        }
        
        // Compute audio-reactive speed
        let frameSpeed = computeAudioReactiveSpeed(audioState: audioState, deltaTime: deltaTime)
        audioTime += deltaTime * frameSpeed
        
        // Build uniforms
        var uniforms = ShaderUniforms()
        uniforms.time = audioTime
        uniforms.audioTime = audioTime
        uniforms.speed = frameSpeed
        uniforms.resolution = SIMD2<Float>(1280, 720)
        
        // Calculate target mouse position (pure function)
        let targetMouse = calcSyntheticMouseTarget(
            time: audioTime,
            energySlow: audioState.energySlow
        )
        
        // Smooth the mouse with exponential decay (eliminates jitter)
        smoothedMouse = smoothMouse(
            current: smoothedMouse,
            target: targetMouse,
            velocity: &mouseVelocity,
            deltaTime: deltaTime,
            smoothing: 0.92,  // Higher = smoother but slower response
            energyBoost: audioState.energySlow  // Faster response during high energy
        )
        uniforms.mouse = smoothedMouse
        
        uniforms.update(from: audioState)
        
        // Create single command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }
        
        // Signal semaphore when GPU completes
        let completionSemaphore = inflightSemaphore
        commandBuffer.addCompletedHandler { _ in
            completionSemaphore.signal()
        }
        
        // 1. Render all tiles to their textures (SAME command buffer)
        shaderRenderer.render(commandBuffer: commandBuffer, uniforms: uniforms)
        maskRenderer.render(commandBuffer: commandBuffer, uniforms: uniforms)
        
        // Text: SwiftUI renderers
        swiftUILyricsRenderer?.render(commandBuffer: commandBuffer, uniforms: uniforms)
        swiftUIRefrainRenderer?.render(commandBuffer: commandBuffer, uniforms: uniforms)
        swiftUISongInfoRenderer?.render(commandBuffer: commandBuffer, uniforms: uniforms)
        
        imageRenderer.render(commandBuffer: commandBuffer, uniforms: uniforms)
        
        // Handle beat-based image switching
        imageRenderer.handleBeat(beat4: Int(audioState.beat4))
        
        // 2. Publish ALL to Syphon (SAME command buffer, before commit)
        if let manager = syphonManager {
            var publishCount = 0
            if let tex = shaderRenderer.texture {
                manager.publish(name: TileConfig.shader.syphonName, texture: tex, commandBuffer: commandBuffer)
                publishCount += 1
            }
            if let tex = maskRenderer.texture {
                manager.publish(name: TileConfig.mask.syphonName, texture: tex, commandBuffer: commandBuffer)
                publishCount += 1
            }
            // Lyrics: publish SwiftUI texture only
            if let tex = swiftUILyricsRenderer?.texture {
                manager.publish(name: TileConfig.lyrics.syphonName, texture: tex, commandBuffer: commandBuffer)
                publishCount += 1
            }
            if let tex = swiftUIRefrainRenderer?.texture {
                manager.publish(name: TileConfig.refrain.syphonName, texture: tex, commandBuffer: commandBuffer)
                publishCount += 1
            }
            if let tex = swiftUISongInfoRenderer?.texture {
                manager.publish(name: TileConfig.songInfo.syphonName, texture: tex, commandBuffer: commandBuffer)
                publishCount += 1
            }
            if let tex = imageRenderer.texture {
                manager.publish(name: TileConfig.image.syphonName, texture: tex, commandBuffer: commandBuffer)
                publishCount += 1
            }
        }
        
        // 3. Single commit
        commandBuffer.commit()
    }
    
    // MARK: - Audio Reactive Speed
    
    private func computeAudioReactiveSpeed(audioState: AudioState, deltaTime: Float) -> Float {
        let hasActiveAudio = audioState.level > 0.01
        
        if !hasActiveAudio {
            rampedSpeed = lerp(rampedSpeed, baseSpeedFloor, speedRampDown)
            beatBoostAccum *= beatBoostDecay
        } else {
            let volumeDriver = audioState.level * (1.0 - bassBoostWeight) + audioState.bass * bassBoostWeight
            let clampedDriver = min(max(volumeDriver, 0), 1)
            let targetSpeed = baseSpeedFloor + clampedDriver * (audioSpeedMax - baseSpeedFloor)
            
            if targetSpeed > rampedSpeed {
                rampedSpeed = lerp(rampedSpeed, targetSpeed, speedRampUp)
            } else {
                rampedSpeed = lerp(rampedSpeed, targetSpeed, speedRampDown)
            }
            
            let beatTrigger = max(audioState.kickEnv, audioState.beatPhase) * beatBoostAmount
            beatBoostAccum = max(beatBoostAccum * beatBoostDecay, beatTrigger)
        }
        
        let rawSpeed = min(max(rampedSpeed + beatBoostAccum, baseSpeedFloor), audioSpeedMax)
        smoothedAudioSpeed = lerp(smoothedAudioSpeed, rawSpeed, 1 - audioSpeedSmoothing)
        
        return min(max(smoothedAudioSpeed, baseSpeedFloor), audioSpeedMax)
    }
}

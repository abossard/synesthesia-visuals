// MTKViewTiles.swift - Unified MTKView-based tile system
// All tiles use MTKView's built-in 60fps render loop for reliable animation
// DRY architecture: BaseMTKViewTile → specialized subclasses

import SwiftUI
import MetalKit
import CoreText
import AppKit
import SyphonKit

// MARK: - Syphon Thumbnail View (receives from app's own Syphon servers)

/// Displays a Syphon client preview - connects to this app's own Syphon servers
struct SyphonThumbnailView: NSViewRepresentable {
    let serverName: String
    
    func makeNSView(context: Context) -> SyphonClientMTKView {
        let view = SyphonClientMTKView(serverName: serverName)
        return view
    }
    
    func updateNSView(_ nsView: SyphonClientMTKView, context: Context) {}
}

/// MTKView that acts as Syphon client, displaying received frames
class SyphonClientMTKView: MTKView, MTKViewDelegate {
    private var syphonClient: SyphonMetalClient?
    private var commandQueue: MTLCommandQueue?
    private var blitPipelineState: MTLRenderPipelineState?
    private let serverName: String
    
    init(serverName: String) {
        self.serverName = serverName
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        setupView()
    }
    
    required init(coder: NSCoder) {
        self.serverName = ""
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        guard let device = self.device else { return }
        self.delegate = self
        self.isPaused = false
        self.enableSetNeedsDisplay = false
        self.preferredFramesPerSecond = 30
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1)
        commandQueue = device.makeCommandQueue()
        setupBlitPipeline()
        connectToServer()
    }
    
    private func connectToServer() {
        guard let device = self.device,
              let servers = SyphonServerDirectory.shared().servers as? [[String: Any]] else { return }
        let appName = Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "SwiftVJApp"
        for serverInfo in servers {
            let name = serverInfo[SyphonServerDescriptionNameKey] as? String ?? ""
            let app = serverInfo[SyphonServerDescriptionAppNameKey] as? String ?? ""
            if name == serverName && app == appName {
                syphonClient = SyphonMetalClient(
                    serverDescription: serverInfo,
                    device: device,
                    options: nil,
                    newFrameHandler: nil
                )
                return
            }
        }
    }
    
    private func setupBlitPipeline() {
        guard let device = self.device else { return }
        let src = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 p [[position]]; float2 t; };
        vertex V bV(uint i [[vertex_id]]) { float2 ps[4]={{-1,-1},{1,-1},{-1,1},{1,1}}; float2 ts[4]={{0,1},{1,1},{0,0},{1,0}}; V o; o.p=float4(ps[i],0,1); o.t=ts[i]; return o; }
        fragment float4 bF(V in [[stage_in]], texture2d<float> t [[texture(0)]]) { return t.sample(sampler(filter::linear), in.t); }
        """
        do {
            let lib = try device.makeLibrary(source: src, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = lib.makeFunction(name: "bV")
            d.fragmentFunction = lib.makeFunction(name: "bF")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            blitPipelineState = try device.makeRenderPipelineState(descriptor: d)
        } catch {}
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        if syphonClient == nil { connectToServer() }
        guard let cq = commandQueue, let cb = cq.makeCommandBuffer(), let drawable = view.currentDrawable else { return }
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = drawable.texture
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].storeAction = .store
        desc.colorAttachments[0].clearColor = self.clearColor
        if let client = syphonClient, client.hasNewFrame, let tex = client.newFrameImage(), let pipe = blitPipelineState {
            if let enc = cb.makeRenderCommandEncoder(descriptor: desc) {
                enc.setRenderPipelineState(pipe)
                enc.setFragmentTexture(tex, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                enc.endEncoding()
            }
        } else {
            if let enc = cb.makeRenderCommandEncoder(descriptor: desc) { enc.endEncoding() }
        }
        cb.present(drawable)
        cb.commit()
    }
}

// MARK: - Base MTKView Tile

/// Base class for all MTKView-based tiles
/// Provides: device setup, render loop, uniform buffer, Syphon-ready texture
class BaseMTKViewTile: MTKView, MTKViewDelegate {
    
    // Metal resources
    var commandQueue: MTLCommandQueue?
    var uniformBuffer: MTLBuffer?
    
    // Blit pipeline for scaled copy to drawable
    private var blitPipelineState: MTLRenderPipelineState?
    
    // Offscreen texture for Syphon output (1280x720)
    private(set) var syphonTexture: MTLTexture?
    
    // Timing
    var audioTime: Float = 0
    private var lastFrameTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private(set) var frameCount: Int = 0
    
    // Draw-loop speed computation (matches VJUniverse.pde computeAudioReactiveSpeed)
    // These MUST be computed every frame, not just on OSC updates!
    private var rampedSpeed: Float = 0.02        // Current ramped speed
    private var beatBoostAccum: Float = 0.0      // Beat boost accumulator (decays)
    private var smoothedAudioSpeed: Float = 0.02 // Final smoothed speed for time accumulation
    
    // Constants from VJUniverse.pde (SynesthesiaAudioOSC.pde)
    private let baseSpeedFloor: Float = 0.02     // BASE_SPEED_FLOOR
    private let audioSpeedMax: Float = 1.20      // AUDIO_SPEED_MAX
    private let speedRampUp: Float = 0.008       // SPEED_RAMP_UP
    private let speedRampDown: Float = 0.025     // SPEED_RAMP_DOWN
    private let bassBoostWeight: Float = 0.35    // BASS_BOOST_WEIGHT
    private let beatBoostAmount: Float = 0.15    // BEAT_BOOST_AMOUNT
    private let beatBoostDecay: Float = 0.92     // BEAT_BOOST_DECAY
    private let audioSpeedSmoothing: Float = 0.65 // AUDIO_SPEED_SMOOTHING (draw-loop)
    
    // Audio state - no lock needed: both updateNSView and draw(in:) run on main thread
    var audioState: AudioState = .silent

    // Cached audio state for current frame (snapshot at frame start for consistent reads)
    private var frameAudioState: AudioState = .silent

    // Callbacks
    var onFrameRendered: ((Int, Float) -> Void)?

    // Syphon publishing callback (set by TileManager)
    var onTextureReady: ((MTLTexture, MTLCommandBuffer) -> Void)?

    // Triple buffering semaphore to prevent GPU stalls
    private let inflightSemaphore = DispatchSemaphore(value: 3)
    
    // Tile identity
    let tileName: String
    
    required init(coder: NSCoder) {
        self.tileName = "base"
        super.init(coder: coder)
        commonInit()
    }
    
    init(tileName: String, device: MTLDevice?) {
        self.tileName = tileName
        super.init(frame: .zero, device: device)
        commonInit()
    }
    
    private func commonInit() {
        guard let device = self.device else {
            print("[BaseMTKViewTile] No Metal device!")
            return
        }
        
        self.delegate = self
        
        // Configure for continuous 60fps animation
        self.isPaused = false
        self.enableSetNeedsDisplay = false
        self.preferredFramesPerSecond = 60
        
        // Pixel format with alpha for compositing
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        // Create command queue
        commandQueue = device.makeCommandQueue()
        
        // Create uniform buffer
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<ShaderUniforms>.stride,
            options: .storageModeShared
        )
        
        // Create offscreen texture for Syphon (1280x720)
        createSyphonTexture(width: 1280, height: 720)
        
        // Create blit pipeline for scaled copy to drawable
        setupBlitPipeline()
        
        // Subclass-specific setup
        setupTile()
    }
    
    private func createSyphonTexture(width: Int, height: Int) {
        guard let device = self.device else { return }
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        
        syphonTexture = device.makeTexture(descriptor: descriptor)
    }
    
    private func setupBlitPipeline() {
        guard let device = self.device else { return }
        
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        
        vertex VertexOut blitVertex(uint vid [[vertex_id]]) {
            float2 positions[4] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };
            float2 texCoords[4] = { {0,1}, {1,1}, {0,0}, {1,0} };
            VertexOut out;
            out.position = float4(positions[vid], 0, 1);
            out.texCoord = texCoords[vid];
            return out;
        }
        
        fragment float4 blitFragment(VertexOut in [[stage_in]],
                                     texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear);
            return tex.sample(s, in.texCoord);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "blitVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "blitFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            blitPipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("[BaseMTKViewTile] Blit pipeline error: \(error)")
        }
    }
    
    /// Override in subclasses for tile-specific setup
    func setupTile() {
        // Override in subclasses
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Override in subclasses if needed
    }
    
    func draw(in view: MTKView) {
        // Wait for available command buffer slot (triple buffering)
        _ = inflightSemaphore.wait(timeout: .now() + .milliseconds(16))

        // Cache audio state once at frame start (atomic read, used throughout frame)
        frameAudioState = audioState

        // Calculate delta time
        let now = CFAbsoluteTimeGetCurrent()
        var deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now
        frameCount += 1

        // Clamp deltaTime to avoid jumps (matches VJUniverse.pde)
        if deltaTime <= 0 || deltaTime > 0.1 {
            deltaTime = 1.0 / 60.0  // Fallback to ~60fps (tighter clamp: 100ms max)
        }

        // ============================================
        // Audio-reactive speed computation (VJUniverse.pde computeAudioReactiveSpeed)
        // Uses cached frameAudioState for consistent reads
        // ============================================

        // Check if we have active audio (level > 0.01)
        let hasActiveAudio = frameAudioState.level > 0.01

        if !hasActiveAudio {
            // No audio → decay to floor
            rampedSpeed = lerp(rampedSpeed, baseSpeedFloor, speedRampDown)
            beatBoostAccum *= beatBoostDecay
        } else {
            // 1. SMOOTH (already done in AudioProcessor)
            // 2. SCALE: Map volume → target speed
            // Blend overall level with bass emphasis for "thump" response
            let volumeDriver = frameAudioState.level * (1.0 - bassBoostWeight) + frameAudioState.bass * bassBoostWeight
            let clampedDriver = min(max(volumeDriver, 0), 1)

            // Scale to speed range: floor at silence, max at loud
            let targetSpeed = baseSpeedFloor + clampedDriver * (audioSpeedMax - baseSpeedFloor)

            // 3. RAMP: Gradual buildup / faster decay
            if targetSpeed > rampedSpeed {
                // Ramp UP slowly (sustained loud builds momentum)
                rampedSpeed = lerp(rampedSpeed, targetSpeed, speedRampUp)
            } else {
                // Ramp DOWN faster (quiet sections decay quicker)
                rampedSpeed = lerp(rampedSpeed, targetSpeed, speedRampDown)
            }

            // 4. BEAT BOOST: Transient punch on kicks/beats
            // Accumulate beat energy (kick hits add boost, decays over time)
            let beatTrigger = max(frameAudioState.kickEnv, frameAudioState.beatPhase) * beatBoostAmount
            beatBoostAccum = max(beatBoostAccum * beatBoostDecay, beatTrigger)
        }

        // Compute raw speed = ramped base + beat transient
        let rawSpeed = min(max(rampedSpeed + beatBoostAccum, baseSpeedFloor), audioSpeedMax)

        // Apply final draw-loop smoothing (AUDIO_SPEED_SMOOTHING = 0.65)
        smoothedAudioSpeed = lerp(smoothedAudioSpeed, rawSpeed, 1 - audioSpeedSmoothing)

        // Clamp to valid range
        let frameSpeed = min(max(smoothedAudioSpeed, baseSpeedFloor), audioSpeedMax)

        // Accumulate audio-reactive time
        audioTime += deltaTime * frameSpeed

        // Update uniforms with cached audio state
        updateUniformsWithState(frameAudioState)

        guard let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let syphonTexture = syphonTexture else {
            inflightSemaphore.signal()
            return
        }

        // Signal semaphore when GPU completes this frame
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inflightSemaphore.signal()
        }

        // 1. SINGLE RENDER to syphonTexture (1280x720)
        renderTile(to: syphonTexture, commandBuffer: commandBuffer)

        // 2. Notify Syphon (before commit!)
        onTextureReady?(syphonTexture, commandBuffer)

        // 3. BLIT syphonTexture to drawable with scaling
        // Use nextDrawable for more predictable timing (may return nil if all in flight)
        if let drawable = view.currentDrawable,
           let blitPipeline = blitPipelineState {
            let descriptor = MTLRenderPassDescriptor()
            descriptor.colorAttachments[0].texture = drawable.texture
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.colorAttachments[0].clearColor = self.clearColor

            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) {
                encoder.setRenderPipelineState(blitPipeline)
                encoder.setFragmentTexture(syphonTexture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
        }

        commandBuffer.commit()

        // Callback (already on main thread, no dispatch needed)
        onFrameRendered?(frameCount, audioTime)
    }
    
    /// Override in subclasses to render tile content
    func renderTile(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        // Override in subclasses
    }
    
    private func updateUniforms() {
        updateUniformsWithState(audioState)
    }

    private func updateUniformsWithState(_ state: AudioState) {
        guard let buffer = uniformBuffer else { return }

        var uniforms = ShaderUniforms()
        uniforms.time = audioTime
        uniforms.audioTime = audioTime
        uniforms.speed = smoothedAudioSpeed
        // Use syphon texture size for uniforms (consistent 1280x720)
        uniforms.resolution = SIMD2<Float>(1280, 720)
        uniforms.update(from: state)

        // Use memcpy for faster copy (avoids array allocation)
        memcpy(buffer.contents(), &uniforms, MemoryLayout<ShaderUniforms>.stride)
    }
}

// MARK: - Shader MTKView Tile

/// MTKView tile that renders GLSL shaders from metallib
class ShaderMTKViewTile: BaseMTKViewTile {
    
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var metallibLibrary: MTLLibrary?
    
    private(set) var currentShaderName: String = ""
    
    override func setupTile() {
        guard let device = self.device else { return }
        
        // Create vertex buffer for fullscreen quad
        let vertices: [Float] = [
            -1,  1, 0, 0,  // top-left
             1,  1, 1, 0,  // top-right
            -1, -1, 0, 1,  // bottom-left
             1, -1, 1, 1,  // bottom-right
        ]
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        // Load metallib
        loadMetalLib()
    }
    
    private func loadMetalLib() {
        guard let device = self.device else { return }
        
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
                    print("[ShaderMTKViewTile] Loaded metallib: \(path)")
                    return
                }
            }
        }
        print("[ShaderMTKViewTile] Failed to load metallib")
    }
    
    func loadShader(name: String) {
        guard let device = self.device,
              let library = metallibLibrary else { return }
        
        let fragmentName = "fragment_\(name)"
        guard let fragmentFunction = library.makeFunction(name: fragmentName),
              let vertexFunction = library.makeFunction(name: "vertex_fullscreen") else {
            print("[ShaderMTKViewTile] Functions not found: \(fragmentName)")
            return
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            currentShaderName = name
            print("[ShaderMTKViewTile] Loaded: \(fragmentName)")
        } catch {
            print("[ShaderMTKViewTile] Pipeline error: \(error)")
        }
    }
    
    override func renderTile(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let pipelineState = pipelineState else { return }
        
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

// MARK: - Text MTKView Tile

/// MTKView tile that renders text using Core Graphics
class TextMTKViewTile: BaseMTKViewTile {
    
    // Core Graphics context for text rendering
    private var cgContext: CGContext?
    private var cgTexture: MTLTexture?
    private var copyPipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var samplerState: MTLSamplerState?
    private var needsRedraw = true
    
    // Text state (set externally)
    var textLines: [(text: String, fontSize: CGFloat, opacity: CGFloat, yPosition: CGFloat)] = [] {
        didSet { needsRedraw = true }
    }
    
    override func setupTile() {
        guard let device = self.device else { return }
        
        let width = 1280
        let height = 720
        
        // Create CG context for text rendering - BGRA format to match Metal
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        // Use premultipliedFirst (ARGB) + byteOrder32Little = BGRA in memory
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        
        cgContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )
        
        // Create texture for CG -> Metal transfer - BGRA to match CGContext
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed
        cgTexture = device.makeTexture(descriptor: descriptor)
        
        // Create vertex buffer for fullscreen quad
        let vertices: [Float] = [
            -1,  1, 0, 0,  // top-left (pos.xy, uv.xy)
             1,  1, 1, 0,  // top-right
            -1, -1, 0, 1,  // bottom-left
             1, -1, 1, 1,  // bottom-right
        ]
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
        
        // Create sampler state
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
        
        // Create texture copy pipeline using default library
        setupCopyPipeline()
    }
    
    private func setupCopyPipeline() {
        guard let device = self.device else { return }
        
        // Create simple passthrough shader inline
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };
        
        vertex VertexOut textCopyVertex(uint vid [[vertex_id]],
                                         constant float4 *vertices [[buffer(0)]]) {
            float4 v = vertices[vid];
            VertexOut out;
            out.position = float4(v.xy, 0, 1);
            out.uv = v.zw;
            return out;
        }
        
        fragment float4 textCopyFragment(VertexOut in [[stage_in]],
                                          texture2d<float> tex [[texture(0)]],
                                          sampler s [[sampler(0)]]) {
            return tex.sample(s, in.uv);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertexFunc = library.makeFunction(name: "textCopyVertex"),
                  let fragmentFunc = library.makeFunction(name: "textCopyFragment") else {
                print("[TextMTKViewTile] Failed to create shader functions")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunc
            pipelineDescriptor.fragmentFunction = fragmentFunc
            pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
            
            // Enable alpha blending
            pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            
            copyPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("[TextMTKViewTile] Pipeline error: \(error)")
        }
    }
    
    override func renderTile(to texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let ctx = cgContext,
              let cgTexture = cgTexture,
              let pipelineState = copyPipelineState,
              let vertexBuffer = vertexBuffer,
              let samplerState = samplerState else { return }
        
        // Only redraw/upload when text changes to keep main thread light
        if needsRedraw {
            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
            ctx.fill(CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))

            for line in textLines {
                drawText(line.text, fontSize: line.fontSize, opacity: line.opacity, yPosition: line.yPosition, context: ctx)
            }

            if let data = ctx.data {
                let region = MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: ctx.width, height: ctx.height, depth: 1)
                )
                cgTexture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: ctx.width * 4)
            }

            needsRedraw = false
        }
        
        // Render fullscreen quad with CG texture scaled to target size
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(cgTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
    
    private func drawText(_ text: String, fontSize: CGFloat, opacity: CGFloat, yPosition: CGFloat, context: CGContext) {
        guard !text.isEmpty, opacity > 0.01 else { return }
        
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let color = NSColor.white.withAlphaComponent(opacity / 255.0)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        
        let x = (CGFloat(context.width) - bounds.width) / 2
        let y = CGFloat(context.height) * (1 - yPosition) - bounds.height / 2
        
        context.saveGState()
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        context.restoreGState()
    }
    
    /// Auto-size font to fit within max width
    func calcAutoFitFontSize(for text: String, maxWidth: CGFloat, minSize: CGFloat = 24, maxSize: CGFloat = 96) -> CGFloat {
        var size = maxSize
        while size > minSize {
            let font = NSFont.systemFont(ofSize: size, weight: .medium)
            let textSize = (text as NSString).size(withAttributes: [.font: font])
            if textSize.width <= maxWidth {
                return size
            }
            size -= 2
        }
        return minSize
    }
}

// MARK: - Lyrics MTKView Tile

/// Specialized text tile for lyrics display with prev/current/next lines
class LyricsMTKViewTile: TextMTKViewTile {
    
    var lyricsState: LyricsDisplayState = .empty {
        didSet { updateTextLines() }
    }
    
    private func updateTextLines() {
        guard lyricsState.activeIndex >= 0 else {
            textLines = []
            return
        }
        
        let maxWidth: CGFloat = 1280 * 0.92
        let prevText = lyricsState.prevLine ?? ""
        let currText = lyricsState.currentLine ?? ""
        let nextText = lyricsState.nextLine ?? ""
        
        // Calculate auto-fit font size
        var autoSize: CGFloat = 72
        for text in [prevText, currText, nextText].filter({ !$0.isEmpty }) {
            autoSize = min(autoSize, calcAutoFitFontSize(for: text, maxWidth: maxWidth, minSize: 28, maxSize: 96))
        }
        
        var lines: [(String, CGFloat, CGFloat, CGFloat)] = []
        
        // Previous: 70% size, 35% opacity, y=0.28
        if !prevText.isEmpty {
            lines.append((prevText, autoSize * 0.7, CGFloat(lyricsState.textOpacity) * 0.35, 0.28))
        }
        
        // Current: 100% size, 100% opacity, y=0.50
        if !currText.isEmpty {
            lines.append((currText, autoSize, CGFloat(lyricsState.textOpacity), 0.50))
        }
        
        // Next: 70% size, 25% opacity, y=0.72
        if !nextText.isEmpty {
            lines.append((nextText, autoSize * 0.7, CGFloat(lyricsState.textOpacity) * 0.25, 0.72))
        }
        
        textLines = lines
    }
}

// MARK: - Refrain MTKView Tile

/// Specialized text tile for refrain/chorus display
class RefrainMTKViewTile: TextMTKViewTile {
    
    var refrainState: RefrainDisplayState = .empty {
        didSet { updateTextLines() }
    }
    
    private func updateTextLines() {
        guard !refrainState.text.isEmpty, refrainState.opacity > 0.01 else {
            textLines = []
            return
        }
        
        let maxWidth: CGFloat = 1280 * 0.85
        let fontSize = calcAutoFitFontSize(for: refrainState.text, maxWidth: maxWidth, minSize: 36, maxSize: 120)
        
        textLines = [(refrainState.text, fontSize, CGFloat(refrainState.opacity), 0.50)]
    }
}

// MARK: - Song Info MTKView Tile

/// Specialized text tile for artist/title display
class SongInfoMTKViewTile: TextMTKViewTile {
    
    var songInfoState: SongInfoDisplayState = .empty {
        didSet { updateTextLines() }
    }
    
    private func updateTextLines() {
        let opacity = songInfoState.computeOpacity()
        guard songInfoState.active, opacity > 0.01 else {
            textLines = []
            return
        }
        
        var lines: [(String, CGFloat, CGFloat, CGFloat)] = []
        let baseFontSize: CGFloat = 72
        let maxWidth: CGFloat = 1280 * 0.8
        
        // Artist: above center
        if !songInfoState.artist.isEmpty {
            let size = calcAutoFitFontSize(for: songInfoState.artist, maxWidth: maxWidth, minSize: 24, maxSize: baseFontSize * 0.65)
            lines.append((songInfoState.artist, size, CGFloat(opacity), 0.42))
        }
        
        // Title: below center
        if !songInfoState.title.isEmpty {
            let size = calcAutoFitFontSize(for: songInfoState.title, maxWidth: maxWidth, minSize: 28, maxSize: baseFontSize)
            lines.append((songInfoState.title, size, CGFloat(opacity), 0.55))
        }
        
        textLines = lines
    }
}

// MARK: - SwiftUI Wrappers

/// Generic SwiftUI wrapper for any MTKView tile
struct MTKViewTileWrapper<T: BaseMTKViewTile>: NSViewRepresentable {
    let tileFactory: (MTLDevice) -> T
    let configure: (T) -> Void
    
    @Binding var frameCount: Int
    @Binding var audioTime: Float
    var audioState: AudioState

    final class Coordinator {
        var lastUIUpdate: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeNSView(context: Context) -> T {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device")
        }
        let tile = tileFactory(device)
        tile.onFrameRendered = { frame, time in
            // Throttle UI bindings to ~10 Hz to avoid SwiftUI churn
            let now = CFAbsoluteTimeGetCurrent()
            if now - context.coordinator.lastUIUpdate >= 0.1 {
                context.coordinator.lastUIUpdate = now
                self.frameCount = frame
                self.audioTime = time
            }
        }
        configure(tile)
        return tile
    }
    
    func updateNSView(_ nsView: T, context: Context) {
        nsView.audioState = audioState
    }
}

/// Convenience: Shader tile view (wired to Syphon)
struct ShaderTileView: NSViewRepresentable {
    let shaderName: String
    let syphonName: String
    @Binding var frameCount: Int
    @Binding var audioTime: Float
    var audioState: AudioState
    
    init(shaderName: String, syphonName: String = TileConfig.shader.syphonName, frameCount: Binding<Int> = .constant(0), audioTime: Binding<Float> = .constant(0), audioState: AudioState = .silent) {
        self.shaderName = shaderName
        self.syphonName = syphonName
        self._frameCount = frameCount
        self._audioTime = audioTime
        self.audioState = audioState
    }
    
    func makeNSView(context: Context) -> ShaderMTKViewTile {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device")
        }
        let tile = ShaderMTKViewTile(tileName: "shader", device: device)
        tile.loadShader(name: shaderName)
        tile.onFrameRendered = { frame, time in
            // Throttle UI bindings to ~10 Hz to avoid SwiftUI churn
            struct Holder { static var last: CFAbsoluteTime = CFAbsoluteTimeGetCurrent() }
            let now = CFAbsoluteTimeGetCurrent()
            if now - Holder.last >= 0.1 {
                Holder.last = now
                self.frameCount = frame
                self.audioTime = time
            }
        }
        // Wire to Syphon - synchronous call since MTKView draw is on main thread
        let syphonServerName = syphonName
        tile.onTextureReady = { texture, commandBuffer in
            SyphonOutputManager.shared.publish(name: syphonServerName, texture: texture, commandBuffer: commandBuffer)
        }
        return tile
    }
    
    func updateNSView(_ nsView: ShaderMTKViewTile, context: Context) {
        nsView.audioState = audioState
        if nsView.currentShaderName != shaderName {
            nsView.loadShader(name: shaderName)
        }
    }
}

/// Convenience: Lyrics tile view (wired to Syphon)
struct LyricsTileView: NSViewRepresentable {
    var lyricsState: LyricsDisplayState
    var audioState: AudioState
    
    func makeNSView(context: Context) -> LyricsMTKViewTile {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device")
        }
        let tile = LyricsMTKViewTile(tileName: "lyrics", device: device)
        tile.lyricsState = lyricsState
        // Wire to Syphon - synchronous call since MTKView draw is on main thread
        tile.onTextureReady = { texture, commandBuffer in
            SyphonOutputManager.shared.publish(name: TileConfig.lyrics.syphonName, texture: texture, commandBuffer: commandBuffer)
        }
        return tile
    }
    
    func updateNSView(_ nsView: LyricsMTKViewTile, context: Context) {
        nsView.lyricsState = lyricsState
        nsView.audioState = audioState
    }
}

/// Convenience: Refrain tile view (wired to Syphon)
struct RefrainTileView: NSViewRepresentable {
    var refrainState: RefrainDisplayState
    var audioState: AudioState
    
    func makeNSView(context: Context) -> RefrainMTKViewTile {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device")
        }
        let tile = RefrainMTKViewTile(tileName: "refrain", device: device)
        tile.refrainState = refrainState
        // Wire to Syphon - synchronous call since MTKView draw is on main thread
        tile.onTextureReady = { texture, commandBuffer in
            SyphonOutputManager.shared.publish(name: TileConfig.refrain.syphonName, texture: texture, commandBuffer: commandBuffer)
        }
        return tile
    }
    
    func updateNSView(_ nsView: RefrainMTKViewTile, context: Context) {
        nsView.refrainState = refrainState
        nsView.audioState = audioState
    }
}

/// Convenience: Song Info tile view (wired to Syphon)
struct SongInfoTileView: NSViewRepresentable {
    var songInfoState: SongInfoDisplayState
    var audioState: AudioState
    
    func makeNSView(context: Context) -> SongInfoMTKViewTile {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device")
        }
        let tile = SongInfoMTKViewTile(tileName: "songInfo", device: device)
        tile.songInfoState = songInfoState
        // Wire to Syphon - synchronous call since MTKView draw is on main thread
        tile.onTextureReady = { texture, commandBuffer in
            SyphonOutputManager.shared.publish(name: TileConfig.songInfo.syphonName, texture: texture, commandBuffer: commandBuffer)
        }
        return tile
    }
    
    func updateNSView(_ nsView: SongInfoMTKViewTile, context: Context) {
        nsView.songInfoState = songInfoState
        nsView.audioState = audioState
    }
}

/// Convenience: Mask shader tile view (wired to Syphon, independent from main shader)
struct MaskTileView: NSViewRepresentable {
    let shaderName: String
    var audioState: AudioState
    
    init(shaderName: String, audioState: AudioState = .silent) {
        self.shaderName = shaderName
        self.audioState = audioState
    }
    
    func makeNSView(context: Context) -> ShaderMTKViewTile {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("No Metal device")
        }
        let tile = ShaderMTKViewTile(tileName: "mask", device: device)
        tile.loadShader(name: shaderName)
        // Wire to Syphon - synchronous call since MTKView draw is on main thread
        tile.onTextureReady = { texture, commandBuffer in
            SyphonOutputManager.shared.publish(name: TileConfig.mask.syphonName, texture: texture, commandBuffer: commandBuffer)
        }
        return tile
    }
    
    func updateNSView(_ nsView: ShaderMTKViewTile, context: Context) {
        nsView.audioState = audioState
        if nsView.currentShaderName != shaderName {
            nsView.loadShader(name: shaderName)
        }
    }
}

// MARK: - Preview

#Preview("All Tiles") {
    VStack(spacing: 20) {
        GroupBox("Shader") {
            ShaderTileView(shaderName: "3isacrowd")
                .aspectRatio(16/9, contentMode: .fit)
                .frame(height: 200)
        }
        
        GroupBox("Lyrics") {
            LyricsTileView(
                lyricsState: LyricsDisplayState(
                    lines: [
                        LyricLine(id: 0, timeSec: 0, text: "Previous line here"),
                        LyricLine(id: 1, timeSec: 1, text: "Current line is displayed"),
                        LyricLine(id: 2, timeSec: 2, text: "Next line coming up")
                    ],
                    activeIndex: 1,
                    textOpacity: 255,
                    fadeDelayMs: 5000,
                    fadeDurationMs: 1000,
                    lastChangeTime: Date()
                ),
                audioState: .silent
            )
            .aspectRatio(16/9, contentMode: .fit)
            .frame(height: 150)
            .background(Color.black)
        }
        
        GroupBox("Refrain") {
            RefrainTileView(
                refrainState: RefrainDisplayState(
                    text: "♪ This is the chorus! ♪",
                    opacity: 255,
                    active: true,
                    lastChangeTime: Date()
                ),
                audioState: .silent
            )
            .aspectRatio(16/9, contentMode: .fit)
            .frame(height: 100)
            .background(Color.black)
        }
        
        GroupBox("Song Info") {
            SongInfoTileView(
                songInfoState: SongInfoDisplayState(
                    artist: "Artist Name",
                    title: "Song Title",
                    album: "Album",
                    opacity: 255,
                    displayTime: 0,
                    active: true,
                    lastChangeTime: Date()
                ),
                audioState: .silent
            )
            .aspectRatio(16/9, contentMode: .fit)
            .frame(height: 100)
            .background(Color.black)
        }
    }
    .padding()
    .frame(width: 800)
}

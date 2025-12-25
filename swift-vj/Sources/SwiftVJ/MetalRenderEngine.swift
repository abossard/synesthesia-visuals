import Foundation
import Metal
import MetalKit
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Main Metal rendering engine for shader + text overlay + Syphon output
/// Handles shader compilation, rendering, and multiple Syphon channels
class MetalRenderEngine: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let mtkView: MTKView
    
    // Shader state
    private var currentShaderPipeline: MTLRenderPipelineState?
    private var shaderStartTime: Date = Date()
    private var currentShaderName: String = ""
    
    // Audio reactive uniforms
    private var audioUniforms = AudioUniforms()
    
    // Karaoke state
    private var karaokeState = KaraokeState()
    
    // Syphon servers (will be initialized via bridging header in full implementation)
    // For now, we'll prepare the infrastructure
    private var syphonServers: [String: Any] = [:]
    
    // Offscreen render targets for each Syphon channel
    private var shaderRenderTarget: MTLTexture?
    private var fullLyricsTarget: MTLTexture?
    private var refrainTarget: MTLTexture?
    private var songInfoTarget: MTLTexture?
    
    // Text rendering
    private var textRenderer: TextRenderer?
    
    // Mouse state (synthetic + real mouse blending)
    private var mousePosition: (x: Float, y: Float) = (0.5, 0.5)
    private var synthMouseEnabled: Bool = true
    private var synthMouseBlend: Float = 0.85  // 0 = real mouse, 1 = full synthetic
    private var synthMouseSpeed: Float = 0.3
    
    // Screenshot functionality
    private var screenshotScheduled: Bool = false
    private var screenshotTime: Date?
    private var screenshotShaderName: String = ""
    private let screenshotDelay: TimeInterval = 1.0  // seconds
    private let screenshotsDirectory: String
    
    init?(frame: NSRect) {
        // Setup screenshots directory
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        screenshotsDirectory = homeDir.appendingPathComponent("SwiftVJ_Screenshots").path
        // Get default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            NSLog("ERROR: Metal is not supported on this device")
            return nil
        }
        
        self.device = device
        
        // Create command queue
        guard let queue = device.makeCommandQueue() else {
            NSLog("ERROR: Failed to create Metal command queue")
            return nil
        }
        self.commandQueue = queue
        
        // Create MTKView
        mtkView = MTKView(frame: frame, device: device)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.framebufferOnly = false  // Allow texture readback for Syphon
        
        super.init()
        
        mtkView.delegate = self
        
        // Initialize text renderer
        textRenderer = TextRenderer(device: device)
        
        // Create screenshots directory if needed
        try? FileManager.default.createDirectory(atPath: screenshotsDirectory, 
                                                  withIntermediateDirectories: true, 
                                                  attributes: nil)
        
        // Create render targets
        createRenderTargets(width: Int(frame.width), height: Int(frame.height))
        
        // Initialize with a default shader
        loadDefaultShader()
        
        NSLog("MetalRenderEngine initialized")
    }
    
    /// Create offscreen render targets for each Syphon channel
    private func createRenderTargets(width: Int, height: Int) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        
        shaderRenderTarget = device.makeTexture(descriptor: descriptor)
        fullLyricsTarget = device.makeTexture(descriptor: descriptor)
        refrainTarget = device.makeTexture(descriptor: descriptor)
        songInfoTarget = device.makeTexture(descriptor: descriptor)
    }
    
    /// Load default shader (simple gradient)
    private func loadDefaultShader() {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        
        vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
            VertexOut out;
            float2 positions[6] = {
                float2(-1, -1), float2(1, -1), float2(-1, 1),
                float2(-1, 1), float2(1, -1), float2(1, 1)
            };
            out.position = float4(positions[vertexID], 0, 1);
            out.texCoord = positions[vertexID] * 0.5 + 0.5;
            return out;
        }
        
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                     constant float &time [[buffer(0)]],
                                     constant float2 &resolution [[buffer(1)]],
                                     constant float &bass [[buffer(2)]],
                                     constant float &mid [[buffer(3)]],
                                     constant float &high [[buffer(4)]],
                                     constant float2 &mouse [[buffer(5)]]) {
            float2 uv = in.texCoord;
            float2 mouseOffset = (mouse - 0.5) * 0.2;
            uv += mouseOffset;
            float3 color = 0.5 + 0.5 * cos(time + uv.xyx + float3(0, 2, 4));
            return float4(color, 1.0);
        }
        """
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let vertexFunction = library.makeFunction(name: "vertex_main"),
                  let fragmentFunction = library.makeFunction(name: "fragment_main") else {
                NSLog("ERROR: Failed to get shader functions")
                return
            }
            
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            
            currentShaderPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            currentShaderName = "default_gradient"
            shaderStartTime = Date()
            NSLog("Default shader loaded successfully")
        } catch {
            NSLog("ERROR: Failed to compile default shader: \(error)")
        }
    }
    
    /// Set shader from GLSL file (requires conversion to Metal Shading Language)
    func setShader(name: String, glslPath: String) {
        // TODO: Implement GLSL to MSL conversion or load pre-converted MSL shaders
        NSLog("Loading shader: \(name) from \(glslPath)")
        currentShaderName = name
        shaderStartTime = Date()
        
        // Schedule screenshot for new shader
        scheduleScreenshot(shaderName: name)
    }
    
    /// Calculate synthetic mouse position (audio-reactive figure-8 Lissajous curve)
    /// Based on VJUniverse's calcSynthMousePosition
    private func calculateSynthMouse(time: Float, energySlow: Float, bass: Float, mid: Float, beatPhase: Float) -> (x: Float, y: Float) {
        // Base rotation with configurable speed
        var t = time * synthMouseSpeed
        
        // Phase shift on beat for rhythmic variation
        let phaseOffset = beatPhase * 0.4
        t += phaseOffset
        
        // Figure-8 Lissajous curve: x = sin(t), y = sin(2t)
        let fig8X = sin(t)
        let fig8Y = sin(t * 2.0)
        
        // Audio-modulated amplitude (smooth, avoids jitter)
        let baseRadius: Float = 0.12 + energySlow * 0.18  // 0.12-0.30 range
        let radiusX = baseRadius + bass * 0.12             // Bass widens X
        let radiusY = baseRadius + mid * 0.08              // Mids affect Y
        
        // Final position (centered at 0.5, clamped to valid range)
        let x = min(max(0.5 + fig8X * radiusX, 0.05), 0.95)
        let y = min(max(0.5 + fig8Y * radiusY, 0.05), 0.95)
        
        return (x, y)
    }
    
    /// Update mouse position (blend real and synthetic)
    func updateMouse(realX: Float, realY: Float) {
        let realMouseX = realX
        let realMouseY = realY
        
        // Calculate synthetic mouse position
        let elapsedTime = Float(Date().timeIntervalSince(shaderStartTime))
        let synthPos = calculateSynthMouse(
            time: elapsedTime,
            energySlow: 0.5,  // TODO: Get from audio analysis
            bass: audioUniforms.bassLevel,
            mid: audioUniforms.midLevel,
            beatPhase: 0.0    // TODO: Get from audio analysis
        )
        
        // Blend real and synthetic mouse
        let blendAmt = synthMouseEnabled ? synthMouseBlend : 0.0
        let mx = realMouseX * (1.0 - blendAmt) + synthPos.x * blendAmt
        let my = realMouseY * (1.0 - blendAmt) + synthPos.y * blendAmt
        
        mousePosition = (mx, my)
    }
    
    /// Schedule screenshot for current shader
    private func scheduleScreenshot(shaderName: String) {
        // Check if screenshot already exists
        let safeName = shaderName.replacingOccurrences(of: "/", with: "_")
                                 .replacingOccurrences(of: "\\", with: "_")
        let screenshotPath = "\(screenshotsDirectory)/\(safeName).png"
        
        if FileManager.default.fileExists(atPath: screenshotPath) {
            NSLog("Screenshot already exists: \(screenshotPath)")
            return
        }
        
        screenshotScheduled = true
        screenshotTime = Date().addingTimeInterval(screenshotDelay)
        screenshotShaderName = shaderName
        NSLog("Screenshot scheduled for shader: \(shaderName) in \(screenshotDelay)s")
    }
    
    /// Take screenshot if scheduled time has passed
    private func checkAndTakeScreenshot(texture: MTLTexture?) {
        guard screenshotScheduled,
              let scheduledTime = screenshotTime,
              Date() >= scheduledTime,
              let texture = texture else {
            return
        }
        
        takeScreenshot(texture: texture, shaderName: screenshotShaderName)
        screenshotScheduled = false
        screenshotTime = nil
    }
    
    /// Save screenshot of rendered shader
    private func takeScreenshot(texture: MTLTexture, shaderName: String) {
        let safeName = shaderName.replacingOccurrences(of: "/", with: "_")
                                 .replacingOccurrences(of: "\\", with: "_")
        let screenshotPath = "\(screenshotsDirectory)/\(safeName).png"
        
        // Get texture data
        let width = texture.width
        let height = texture.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let imageByteCount = bytesPerRow * height
        
        var imageBytes = [UInt8](repeating: 0, count: imageByteCount)
        let region = MTLRegionMake2D(0, 0, width, height)
        
        texture.getBytes(&imageBytes,
                        bytesPerRow: bytesPerRow,
                        from: region,
                        mipmapLevel: 0)
        
        // Create CGImage from raw bytes
        guard let dataProvider = CGDataProvider(data: Data(imageBytes) as CFData),
              let cgImage = CGImage(width: width,
                                   height: height,
                                   bitsPerComponent: 8,
                                   bitsPerPixel: 32,
                                   bytesPerRow: bytesPerRow,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: dataProvider,
                                   decode: nil,
                                   shouldInterpolate: false,
                                   intent: .defaultIntent) else {
            NSLog("ERROR: Failed to create CGImage for screenshot")
            return
        }
        
        // Save to PNG file
        let url = URL(fileURLWithPath: screenshotPath)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil) else {
            NSLog("ERROR: Failed to create image destination")
            return
        }
        
        CGImageDestinationAddImage(destination, cgImage, nil)
        
        if CGImageDestinationFinalize(destination) {
            NSLog("📸 Screenshot saved: \(screenshotPath)")
        } else {
            NSLog("ERROR: Failed to save screenshot")
        }
    }
    
    /// Update karaoke text for a specific channel
    func setText(channel: String, text: String) {
        switch channel {
        case "full":
            karaokeState.fullLyrics = text
        case "refrain":
            karaokeState.refrain = text
        case "songinfo":
            karaokeState.songInfo = text
        default:
            NSLog("WARNING: Unknown text channel: \(channel)")
        }
    }
    
    /// Update audio uniforms
    func updateAudioUniforms(bass: Float, mid: Float, high: Float, bpm: Float) {
        audioUniforms.bassLevel = bass
        audioUniforms.midLevel = mid
        audioUniforms.highLevel = high
        audioUniforms.bpm = bpm
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        createRenderTargets(width: Int(size.width), height: Int(size.height))
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor else {
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        // Calculate time uniforms
        let elapsedTime = Float(Date().timeIntervalSince(shaderStartTime))
        var timeUniform = elapsedTime
        var resolutionUniform = simd_float2(Float(view.drawableSize.width), 
                                           Float(view.drawableSize.height))
        
        // Update mouse position (blend synthetic and real)
        updateMouse(realX: 0.5, realY: 0.5)  // TODO: Get real mouse from window events
        var mouseUniform = simd_float2(mousePosition.x, 1.0 - mousePosition.y)  // Y-flipped
        
        // Audio uniforms
        var bassUniform = audioUniforms.bassLevel
        var midUniform = audioUniforms.midLevel
        var highUniform = audioUniforms.highLevel
        
        // Render shader to main view
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
           let pipeline = currentShaderPipeline {
            renderEncoder.setRenderPipelineState(pipeline)
            renderEncoder.setFragmentBytes(&timeUniform, length: MemoryLayout<Float>.stride, index: 0)
            renderEncoder.setFragmentBytes(&resolutionUniform, length: MemoryLayout<simd_float2>.stride, index: 1)
            renderEncoder.setFragmentBytes(&bassUniform, length: MemoryLayout<Float>.stride, index: 2)
            renderEncoder.setFragmentBytes(&midUniform, length: MemoryLayout<Float>.stride, index: 3)
            renderEncoder.setFragmentBytes(&highUniform, length: MemoryLayout<Float>.stride, index: 4)
            renderEncoder.setFragmentBytes(&mouseUniform, length: MemoryLayout<simd_float2>.stride, index: 5)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            renderEncoder.endEncoding()
        }
        
        // TODO: Render text overlays to separate targets
        // TODO: Publish to Syphon servers
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // Check if we need to take a screenshot
        checkAndTakeScreenshot(texture: drawable.texture)
    }
    
    func cleanup() {
        // Cleanup Syphon servers and resources
        syphonServers.removeAll()
    }
}

// MARK: - Supporting Types

struct AudioUniforms {
    var bassLevel: Float = 0.0
    var midLevel: Float = 0.0
    var highLevel: Float = 0.0
    var bpm: Float = 120.0
}

struct KaraokeState {
    var fullLyrics: String = ""
    var refrain: String = ""
    var songInfo: String = ""
    var artist: String = ""
    var title: String = ""
    var position: Float = 0.0
    var duration: Float = 0.0
}

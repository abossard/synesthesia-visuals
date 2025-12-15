import Foundation
import Metal
import MetalKit
import CoreText

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
    
    init?(frame: NSRect) {
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
                                     constant float2 &resolution [[buffer(1)]]) {
            float2 uv = in.texCoord;
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
        
        // Render shader to main view
        if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
           let pipeline = currentShaderPipeline {
            renderEncoder.setRenderPipelineState(pipeline)
            renderEncoder.setFragmentBytes(&timeUniform, length: MemoryLayout<Float>.stride, index: 0)
            renderEncoder.setFragmentBytes(&resolutionUniform, length: MemoryLayout<simd_float2>.stride, index: 1)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            renderEncoder.endEncoding()
        }
        
        // TODO: Render text overlays to separate targets
        // TODO: Publish to Syphon servers
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
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

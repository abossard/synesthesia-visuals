// MetalShaderView.swift - MTKView wrapper for continuous shader rendering
// Uses MTKView's built-in render loop for proper 60fps animation

import SwiftUI
import MetalKit

// MARK: - Standalone Shader MTKView

/// MTKView subclass that renders a single shader continuously
/// Self-contained - does not require RenderEngine's render loop
class ShaderMTKView: MTKView, MTKViewDelegate {
    
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    
    // Shader state
    private var currentShaderName: String = ""
    private var audioTime: Float = 0
    private var lastFrameTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var frameCount: Int = 0
    
    // Audio state (can be updated externally)
    var audioState: AudioState = .silent
    
    // Callback for frame updates
    var onFrameRendered: ((Int, Float) -> Void)?
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    init(device: MTLDevice?) {
        super.init(frame: .zero, device: device)
        commonInit()
    }
    
    private func commonInit() {
        guard let device = self.device else {
            print("[ShaderMTKView] No Metal device!")
            return
        }
        
        self.delegate = self
        
        // Configure for continuous animation (KEY SETTINGS!)
        self.isPaused = false
        self.enableSetNeedsDisplay = false
        self.preferredFramesPerSecond = 60
        
        // Pixel format
        self.colorPixelFormat = .bgra8Unorm
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        // Create command queue
        commandQueue = device.makeCommandQueue()
        
        // Create vertex buffer for fullscreen quad
        createVertexBuffer()
        
        // Create uniform buffer
        uniformBuffer = device.makeBuffer(length: MemoryLayout<ShaderUniforms>.stride, options: .storageModeShared)
        
        print("[ShaderMTKView] Initialized with continuous 60fps render loop")
    }
    
    private func createVertexBuffer() {
        // Fullscreen quad vertices: position (x,y) + texcoord (u,v)
        let vertices: [Float] = [
            -1,  1, 0, 0,  // top-left
             1,  1, 1, 0,  // top-right
            -1, -1, 0, 1,  // bottom-left
             1, -1, 1, 1,  // bottom-right
        ]
        vertexBuffer = device?.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared)
    }
    
    /// Load a shader from the precompiled metallib
    func loadShader(name: String) {
        guard let device = self.device else { return }
        
        // Search paths for metallib (same as ShaderTile)
        let execURL = Bundle.main.bundleURL
        let searchPaths = [
            // Development paths
            execURL.appendingPathComponent("Shaders.metallib").path,
            execURL.appendingPathComponent("Contents/Resources/Shaders.metallib").path,
            // SwiftPM bundle resource path
            Bundle.main.path(forResource: "Shaders", ofType: "metallib") ?? "",
            // Fallback absolute paths
            "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJApp/Resources/Shaders.metallib",
            "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Build/Shaders.metallib"
        ].filter { !$0.isEmpty }
        
        var library: MTLLibrary?
        var loadedPath = ""
        
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                if let lib = try? device.makeLibrary(URL: URL(fileURLWithPath: path)) {
                    library = lib
                    loadedPath = path
                    break
                }
            }
        }
        
        guard let library = library else {
            print("[ShaderMTKView] Failed to load metallib from any of \(searchPaths.count) paths")
            return
        }
        
        print("[ShaderMTKView] Loaded metallib from: \(loadedPath)")
        
        let fragmentName = "fragment_\(name)"
        guard let fragmentFunction = library.makeFunction(name: fragmentName) else {
            print("[ShaderMTKView] Fragment function '\(fragmentName)' not found")
            return
        }
        
        guard let vertexFunction = library.makeFunction(name: "vertex_fullscreen") else {
            print("[ShaderMTKView] Vertex function 'vertex_fullscreen' not found")
            return
        }
        
        // Create pipeline
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            currentShaderName = name
            print("[ShaderMTKView] Loaded shader: \(fragmentName)")
        } catch {
            print("[ShaderMTKView] Pipeline creation failed: \(error)")
        }
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle resize - nothing special needed
    }
    
    func draw(in view: MTKView) {
        // Calculate delta time
        let now = CFAbsoluteTimeGetCurrent()
        let deltaTime = Float(now - lastFrameTime)
        lastFrameTime = now
        frameCount += 1
        
        // Update audio time with proper speed
        let baseSpeed: Float = 1.0
        let audioSpeedBoost: Float = 0.5 + audioState.level * 0.5
        audioTime += deltaTime * baseSpeed * audioSpeedBoost
        
        guard let drawable = view.currentDrawable,
              let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let pipelineState = pipelineState else {
            return
        }
        
        // Update uniforms
        updateUniforms(deltaTime: deltaTime)
        
        // Create render pass
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return
        }
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // Notify frame rendered
        onFrameRendered?(frameCount, audioTime)
    }
    
    private func updateUniforms(deltaTime: Float) {
        guard let buffer = uniformBuffer else { return }
        
        var uniforms = ShaderUniforms()
        uniforms.time = audioTime
        uniforms.resolution = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        uniforms.update(from: audioState)
        
        buffer.contents().copyMemory(from: [uniforms], byteCount: MemoryLayout<ShaderUniforms>.stride)
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI wrapper for ShaderMTKView
struct MetalShaderView: NSViewRepresentable {
    let shaderName: String
    @Binding var frameCount: Int
    @Binding var audioTime: Float
    var audioState: AudioState
    
    init(shaderName: String, frameCount: Binding<Int> = .constant(0), audioTime: Binding<Float> = .constant(0), audioState: AudioState = .silent) {
        self.shaderName = shaderName
        self._frameCount = frameCount
        self._audioTime = audioTime
        self.audioState = audioState
    }
    
    func makeNSView(context: Context) -> ShaderMTKView {
        let device = MTLCreateSystemDefaultDevice()
        let mtkView = ShaderMTKView(device: device)
        
        // Load shader
        mtkView.loadShader(name: shaderName)
        
        // Set up frame callback
        mtkView.onFrameRendered = { frame, time in
            DispatchQueue.main.async {
                self.frameCount = frame
                self.audioTime = time
            }
        }
        
        return mtkView
    }
    
    func updateNSView(_ nsView: ShaderMTKView, context: Context) {
        // Update audio state
        nsView.audioState = audioState
        
        // Reload shader if changed
        // (skip if same shader to avoid recompilation)
    }
}

// MARK: - Preview

struct MetalShaderView_Previews: PreviewProvider {
    static var previews: some View {
        MetalShaderView(shaderName: "3isacrowd")
            .frame(width: 640, height: 360)
    }
}

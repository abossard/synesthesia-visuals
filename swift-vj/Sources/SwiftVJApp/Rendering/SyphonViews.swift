// SyphonViews.swift - SwiftUI views for displaying Syphon server output
// UI preview components that consume headless rendering via Syphon clients

import SwiftUI
import Metal
import MetalKit
import SyphonKit
import Combine

// MARK: - Syphon MTKView (60fps GPU-direct rendering)

/// NSViewRepresentable wrapper for SyphonMTKViewImpl
/// Renders Syphon textures directly on GPU at 60fps with no CPU readback
struct SyphonMTKView: NSViewRepresentable {
    let serverName: String

    func makeNSView(context: Context) -> SyphonMTKViewImpl {
        let view = SyphonMTKViewImpl()
        view.connect(serverName: serverName)
        return view
    }

    func updateNSView(_ nsView: SyphonMTKViewImpl, context: Context) {
        // Reconnect if server name changed
        if nsView.currentServerName != serverName {
            nsView.connect(serverName: serverName)
        }
    }
}

/// MTKView subclass that displays Syphon textures at 60fps
@MainActor
final class SyphonMTKViewImpl: MTKView, MTKViewDelegate {
    private var receiver: SyphonReceiver?
    private var commandQueue: MTLCommandQueue?
    private var blitPipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var samplerState: MTLSamplerState?
    private var currentTexture: MTLTexture?
    private var cancellables = Set<AnyCancellable>()

    private(set) var currentServerName: String = ""

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        let device = device ?? MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: device)
        setup()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        self.device = MTLCreateSystemDefaultDevice()
        setup()
    }

    convenience init() {
        self.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
    }

    private func setup() {
        guard let device = device else { return }

        // Configure MTKView
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        delegate = self
        isPaused = false
        enableSetNeedsDisplay = false
        preferredFramesPerSecond = 60

        // Create command queue (reused every frame)
        commandQueue = device.makeCommandQueue()

        // Create blit pipeline for texture copy
        setupBlitPipeline(device: device)

        // Create vertex buffer for fullscreen quad
        let vertices: [Float] = [
            -1,  1, 0, 0,   // top-left
             1,  1, 1, 0,   // top-right
            -1, -1, 0, 1,   // bottom-left
             1, -1, 1, 1,   // bottom-right
        ]
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: .storageModeShared)

        // Create sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    private func setupBlitPipeline(device: MTLDevice) {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };

        vertex VertexOut syphonBlitVertex(uint vid [[vertex_id]],
                                          constant float4* vertices [[buffer(0)]]) {
            VertexOut out;
            float4 v = vertices[vid];
            out.position = float4(v.xy, 0, 1);
            out.texCoord = v.zw;
            return out;
        }

        fragment float4 syphonBlitFragment(VertexOut in [[stage_in]],
                                           texture2d<float> tex [[texture(0)]],
                                           sampler s [[sampler(0)]]) {
            return tex.sample(s, in.texCoord);
        }
        """

        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunc = library.makeFunction(name: "syphonBlitVertex"),
              let fragmentFunc = library.makeFunction(name: "syphonBlitFragment") else {
            print("[SyphonMTKView] Failed to create shader library")
            return
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            blitPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("[SyphonMTKView] Pipeline error: \(error)")
        }
    }

    func connect(serverName: String) {
        guard let device = device else { return }

        currentServerName = serverName

        // Disconnect existing receiver
        receiver?.disconnect()
        cancellables.removeAll()

        // Create new receiver
        receiver = SyphonReceiver(device: device)

        // Subscribe to frame updates
        receiver?.framePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] texture in
                self?.currentTexture = texture
            }
            .store(in: &cancellables)

        // Try to connect (may retry if server not ready)
        attemptConnection()
    }

    private func attemptConnection(retryCount: Int = 0) {
        guard let receiver = receiver else {
            print("[SyphonMTKView] No receiver for \(currentServerName)")
            return
        }

        // Log available servers on first attempt
        if retryCount == 0 {
            let servers = SyphonReceiver.availableServers()
            print("[SyphonMTKView] Available servers: \(servers.map { $0.displayName })")
        }

        if receiver.connect(appName: nil, serverName: currentServerName) {
            print("[SyphonMTKView] Connected to \(currentServerName)")
        } else if retryCount < 10 {
            print("[SyphonMTKView] Connection attempt \(retryCount + 1)/10 failed for \(currentServerName)")
            // Retry after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.attemptConnection(retryCount: retryCount + 1)
            }
        } else {
            print("[SyphonMTKView] Failed to connect to \(currentServerName) after 10 attempts")
        }
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // Get current frame from Syphon (or use cached texture)
        let texture = receiver?.currentFrame() ?? currentTexture

        guard let drawable = currentDrawable,
              let renderPassDescriptor = currentRenderPassDescriptor,
              let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            // Debug: log why we're not drawing
            if currentDrawable == nil {
                // Only log occasionally to avoid spam
                if Int.random(in: 0..<60) == 0 {
                    print("[SyphonMTKView] No drawable for \(currentServerName) - size: \(drawableSize)")
                }
            }
            return
        }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // If we have a texture, blit it to the view
        if let texture = texture,
           let pipelineState = blitPipelineState,
           let vertexBuffer = vertexBuffer,
           let samplerState = samplerState {
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        } else if texture == nil && Int.random(in: 0..<60) == 0 {
            // Debug: log when no texture
            print("[SyphonMTKView] No texture for \(currentServerName) - connected: \(receiver?.isConnected ?? false)")
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    deinit {}
}

// MARK: - Syphon Thumbnail View

/// SwiftUI view that displays a Syphon server's output
/// This is the ONLY way UI should display rendered tiles - via Syphon client
struct SyphonThumbnailView: View {
    let serverName: String
    
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black
                SyphonMTKView(serverName: serverName)
                    .id(serverName)
            }
        }
    }
}

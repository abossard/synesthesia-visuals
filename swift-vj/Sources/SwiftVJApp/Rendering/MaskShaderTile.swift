// MaskShaderTile.swift - Mask shader rendering tile
// Renders black/white masks for compositing in OBS/Resolume

import Foundation
import Metal
import simd

/// Mask shader tile - renders grayscale masks for compositing
/// Similar to ShaderTile but uses masks directory and outputs B/W
final class MaskShaderTile: BaseTile {
    // MARK: - State

    private var state: ShaderDisplayState = .empty

    // Shader pipeline
    private var currentPipelineState: MTLRenderPipelineState?
    private var uniformBuffer: MTLBuffer?
    private var vertexBuffer: MTLBuffer?

    // Audio-reactive time
    private var audioTime: Float = 0
    private var syntheticMouse: SIMD2<Float> = SIMD2(0.5, 0.5)

    // Shader library cache
    private var shaderCache: [String: MTLRenderPipelineState] = [:]

    // Default mask shader
    private var defaultPipelineState: MTLRenderPipelineState?

    // MARK: - Init

    init(device: MTLDevice) {
        super.init(device: device, config: .mask)
        setupBuffers()
        setupDefaultShader()
    }

    private func setupBuffers() {
        // Create uniform buffer
        uniformBuffer = commandQueue.device.makeBuffer(
            length: MemoryLayout<ShaderUniforms>.stride,
            options: .storageModeShared
        )

        // Create fullscreen quad vertices (position + uv)
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,
             1.0, -1.0, 1.0, 1.0,
            -1.0,  1.0, 0.0, 0.0,
             1.0,  1.0, 1.0, 0.0
        ]
        vertexBuffer = commandQueue.device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }

    private func setupDefaultShader() {
        // Default mask shader - radial gradient modulated by audio
        let defaultShaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        struct Uniforms {
            float time;
            float2 resolution;
            float2 mouse;
            float speed;
            float bass;
            float lowMid;
            float mid;
            float highs;
            float level;
            float kickEnv;
            float kickPulse;
            float beat;
            float energyFast;
            float energySlow;
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
                                      constant Uniforms &u [[buffer(0)]]) {
            float2 uv = in.uv;
            float2 center = float2(0.5, 0.5);

            // Distance from center
            float d = distance(uv, center);

            // Audio-reactive radius
            float radius = 0.3 + u.bass * 0.2 + u.level * 0.1;

            // Create mask with soft edge
            float edge = 0.05 + u.energySlow * 0.05;
            float mask = 1.0 - smoothstep(radius - edge, radius + edge, d);

            // Beat pulse
            mask += u.kickEnv * 0.2;

            // Output grayscale (B/W mask)
            return float4(float3(clamp(mask, 0.0, 1.0)), 1.0);
        }
        """

        do {
            let library = try commandQueue.device.makeLibrary(source: defaultShaderSource, options: nil)
            let vertexFunction = library.makeFunction(name: "vertex_main")
            let fragmentFunction = library.makeFunction(name: "fragment_main")

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

            defaultPipelineState = try commandQueue.device.makeRenderPipelineState(descriptor: descriptor)
            currentPipelineState = defaultPipelineState
        } catch {
            print("[MaskShaderTile] Failed to create default shader: \(error)")
        }
    }

    // MARK: - State Updates

    func updateState(_ newState: ShaderDisplayState) {
        let oldState = state
        state = newState

        // Load shader if changed
        if let current = newState.current,
           current.name != oldState.current?.name {
            loadShader(info: current)
        }
    }

    // MARK: - Shader Loading

    func loadShader(info: ShaderInfo) {
        // Check cache first
        if let cached = shaderCache[info.name] {
            currentPipelineState = cached
            state = ShaderDisplayState(
                current: info,
                isLoaded: true,
                error: nil,
                audioTime: state.audioTime,
                syntheticMouse: state.syntheticMouse
            )
            return
        }

        Task {
            do {
                let glslSource = try String(contentsOf: info.path, encoding: .utf8)
                let metalSource = convertGLSLToMetal(glslSource)

                let library = try await commandQueue.device.makeLibrary(source: metalSource, options: nil)
                let vertexFunction = library.makeFunction(name: "vertex_main")
                let fragmentFunction = library.makeFunction(name: "fragment_main")

                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertexFunction
                descriptor.fragmentFunction = fragmentFunction
                descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

                let pipelineState = try await commandQueue.device.makeRenderPipelineState(descriptor: descriptor)

                await MainActor.run {
                    self.shaderCache[info.name] = pipelineState
                    self.currentPipelineState = pipelineState
                    self.state = ShaderDisplayState(
                        current: info,
                        isLoaded: true,
                        error: nil,
                        audioTime: self.state.audioTime,
                        syntheticMouse: self.state.syntheticMouse
                    )
                }
            } catch {
                await MainActor.run {
                    self.state = ShaderDisplayState(
                        current: info,
                        isLoaded: false,
                        error: error.localizedDescription,
                        audioTime: self.state.audioTime,
                        syntheticMouse: self.state.syntheticMouse
                    )
                    self.currentPipelineState = self.defaultPipelineState
                }
                print("[MaskShaderTile] Failed to load \(info.name): \(error)")
            }
        }
    }

    // MARK: - GLSL to Metal Conversion

    func convertGLSLToMetal(_ glslSource: String) -> String {
        // Same conversion as ShaderTile but outputs grayscale
        return """
        #include <metal_stdlib>
        using namespace metal;

        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };

        struct Uniforms {
            float time;
            float2 resolution;
            float2 mouse;
            float speed;
            float bass;
            float lowMid;
            float mid;
            float highs;
            float level;
            float kickEnv;
            float kickPulse;
            float beat;
            float energyFast;
            float energySlow;
        };

        vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                     constant float4 *vertices [[buffer(0)]]) {
            VertexOut out;
            float4 v = vertices[vertexID];
            out.position = float4(v.xy, 0.0, 1.0);
            out.uv = v.zw;
            return out;
        }

        // Mask shader - outputs grayscale
        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant Uniforms &u [[buffer(0)]]) {
            float2 uv = in.uv;
            float t = u.time;

            // Concentric rings modulated by audio
            float d = distance(uv, float2(0.5, 0.5));
            float rings = sin(d * 20.0 - t * u.speed * 2.0) * 0.5 + 0.5;

            // Audio modulation
            rings *= 0.5 + u.level * 0.5;
            rings += u.kickEnv * 0.3;

            // Output grayscale mask
            float gray = clamp(rings, 0.0, 1.0);
            return float4(float3(gray), 1.0);
        }
        """
    }

    // MARK: - Tile Protocol

    override func update(audioState: AudioState, deltaTime: Float) {
        audioTime += deltaTime * audioState.speed

        syntheticMouse = calcSyntheticMouse(
            time: audioTime,
            energySlow: audioState.energySlow,
            bass: audioState.bass,
            mid: audioState.mid,
            beatPhase: audioState.beatPhase
        )

        updateUniforms(audioState: audioState)
    }

    private func updateUniforms(audioState: AudioState) {
        guard let buffer = uniformBuffer else { return }

        var uniforms = ShaderUniforms()
        uniforms.time = audioTime
        uniforms.resolution = SIMD2<Float>(Float(config.width), Float(config.height))
        uniforms.mouse = syntheticMouse
        uniforms.update(from: audioState)

        let ptr = buffer.contents().bindMemory(to: ShaderUniforms.self, capacity: 1)
        ptr.pointee = uniforms
    }

    override func render(commandBuffer: MTLCommandBuffer) {
        guard let renderPassDesc = renderPassDescriptor,
              let pipelineState = currentPipelineState,
              let vertexBuffer = vertexBuffer,
              let uniformBuffer = uniformBuffer else { return }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        encoder.endEncoding()
    }

    override var statusString: String {
        if let error = state.error {
            return "Error: \(error)"
        }
        if let current = state.current {
            return "Mask: \(current.name)"
        }
        return "Default mask"
    }
}

// MARK: - Mask State Manager

/// Manages MaskShaderTile state
@MainActor
final class MaskStateManager: ObservableObject {
    @Published private(set) var state: ShaderDisplayState = .empty
    @Published private(set) var availableMasks: [ShaderInfo] = []
    @Published private(set) var currentIndex: Int = 0

    private var masksDirectory: URL?

    init() {}

    func loadMaskDirectory(_ url: URL) {
        masksDirectory = url

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return }

        availableMasks = contents
            .filter { isShaderFile($0.lastPathComponent) }
            .map { ShaderInfo(name: stripExtension($0.lastPathComponent), path: $0) }
            .sorted { $0.name < $1.name }
    }

    func selectMask(at index: Int) {
        guard index >= 0, index < availableMasks.count else { return }
        currentIndex = index
        let mask = availableMasks[index]
        state = ShaderDisplayState(
            current: mask,
            isLoaded: false,
            error: nil,
            audioTime: state.audioTime,
            syntheticMouse: state.syntheticMouse
        )
    }

    func selectMask(name: String) {
        if let index = availableMasks.firstIndex(where: { $0.name == name }) {
            selectMask(at: index)
        }
    }

    func nextMask() {
        guard !availableMasks.isEmpty else { return }
        selectMask(at: (currentIndex + 1) % availableMasks.count)
    }

    func prevMask() {
        guard !availableMasks.isEmpty else { return }
        selectMask(at: (currentIndex - 1 + availableMasks.count) % availableMasks.count)
    }

    private func isShaderFile(_ filename: String) -> Bool {
        let extensions = ["glsl", "frag", "txt"]
        let ext = filename.lowercased().components(separatedBy: ".").last ?? ""
        return extensions.contains(ext)
    }

    private func stripExtension(_ filename: String) -> String {
        let extensions = [".glsl", ".frag", ".txt"]
        var name = filename
        for ext in extensions {
            if name.lowercased().hasSuffix(ext) {
                name = String(name.dropLast(ext.count))
                break
            }
        }
        return name
    }
}

// ShaderTile.swift - GLSL shader rendering tile
// Port of ShaderTile and ShaderManager.pde to Swift/Metal

import Foundation
import Metal
import simd

/// GLSL shader rendering tile using Metal
/// Port of ShaderTile from Tile.pde with shader management from ShaderManager.pde
final class ShaderTile: BaseTile {
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

    // Default shader (fallback)
    private var defaultPipelineState: MTLRenderPipelineState?

    // MARK: - Init

    init(device: MTLDevice) {
        super.init(device: device, config: .shader)
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
            // position (x, y), texcoord (u, v)
            -1.0, -1.0, 0.0, 1.0,  // bottom-left
             1.0, -1.0, 1.0, 1.0,  // bottom-right
            -1.0,  1.0, 0.0, 0.0,  // top-left
             1.0,  1.0, 1.0, 0.0   // top-right
        ]
        vertexBuffer = commandQueue.device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }

    private func setupDefaultShader() {
        // Create a simple default shader for when no GLSL is loaded
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
                                      constant Uniforms &uniforms [[buffer(0)]]) {
            float2 uv = in.uv;

            // Simple audio-reactive gradient
            float3 col = float3(0.0);
            col.r = uv.x * (0.3 + uniforms.bass * 0.7);
            col.g = uv.y * (0.3 + uniforms.mid * 0.7);
            col.b = (1.0 - uv.x) * (0.3 + uniforms.highs * 0.7);

            // Beat pulse
            col += uniforms.kickEnv * 0.2;

            // Time-based modulation
            float t = uniforms.time * uniforms.speed;
            col *= 0.8 + 0.2 * sin(t + uv.x * 3.14159);

            return float4(col, 1.0);
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
            print("[ShaderTile] Failed to create default shader: \(error)")
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
                    // Fall back to default shader
                    self.currentPipelineState = self.defaultPipelineState
                }
                print("[ShaderTile] Failed to load \(info.name): \(error)")
            }
        }
    }

    // MARK: - GLSL to Metal Conversion

    /// Convert GLSL fragment shader to Metal
    /// Simplified conversion - full implementation would need proper parsing
    func convertGLSLToMetal(_ glslSource: String) -> String {
        // This is a simplified converter. A full implementation would need:
        // 1. Proper GLSL parsing
        // 2. Type conversions (vec2 -> float2, etc.)
        // 3. Function remapping (texture2D -> texture.sample, etc.)
        // 4. Built-in variable handling (gl_FragCoord -> in.position, etc.)

        // For now, return a wrapper that calls a default implementation
        // Real shaders would need spirv-cross or similar for proper conversion

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

        // GLSL compatibility helpers
        #define vec2 float2
        #define vec3 float3
        #define vec4 float4
        #define mat2 float2x2
        #define mat3 float3x3
        #define mat4 float4x4
        #define fract fract
        #define mix lerp
        #define mod fmod
        #define atan(y, x) atan2(y, x)

        // Fragment shader with GLSL source embedded
        // Note: This is a placeholder - real conversion would parse and transform the GLSL

        fragment float4 fragment_main(VertexOut in [[stage_in]],
                                      constant Uniforms &u [[buffer(0)]]) {
            float2 fragCoord = in.position.xy;
            float2 resolution = u.resolution;
            float2 uv = fragCoord / resolution;

            // Simple procedural pattern using uniforms
            float t = u.time;
            float2 p = uv * 2.0 - 1.0;
            p.x *= resolution.x / resolution.y;

            // Audio-reactive parameters
            float r = length(p);
            float a = atan2(p.y, p.x);

            // Create pattern
            float3 col = float3(0.0);

            // Bass circle
            float bassRing = smoothstep(0.5 + u.bass * 0.3, 0.52 + u.bass * 0.3, r);
            bassRing *= 1.0 - smoothstep(0.52 + u.bass * 0.3, 0.54 + u.bass * 0.3, r);
            col.r += bassRing;

            // Mid spiral
            float spiral = sin(a * 6.0 + t * u.speed * 2.0 + r * 10.0);
            col.g += spiral * 0.5 + 0.5;
            col.g *= u.mid * 0.7 + 0.3;

            // Highs sparkle
            float sparkle = fract(sin(dot(uv * 100.0, float2(12.9898, 78.233))) * 43758.5453);
            col.b += sparkle * u.highs * u.energyFast;

            // Beat pulse
            col += u.kickEnv * 0.15;

            // Energy glow
            col *= 0.7 + u.energySlow * 0.3;

            return float4(col, 1.0);
        }
        """
    }

    // MARK: - Tile Protocol

    override func update(audioState: AudioState, deltaTime: Float) {
        // Update audio-reactive time
        audioTime += deltaTime * audioState.speed

        // Update synthetic mouse (Lissajous curve)
        syntheticMouse = calcSyntheticMouse(
            time: audioTime,
            energySlow: audioState.energySlow,
            bass: audioState.bass,
            mid: audioState.mid,
            beatPhase: audioState.beatPhase
        )

        // Update uniforms
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
            return current.name
        }
        return "No shader"
    }
}

// MARK: - Shader State Manager

/// Manages ShaderTile state and shader library
@MainActor
final class ShaderStateManager: ObservableObject {
    @Published private(set) var state: ShaderDisplayState = .empty
    @Published private(set) var availableShaders: [ShaderInfo] = []
    @Published private(set) var currentIndex: Int = 0

    private var shadersDirectory: URL?

    init() {}

    func loadShaderDirectory(_ url: URL) {
        shadersDirectory = url

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return }

        availableShaders = contents
            .filter { isShaderFile($0.lastPathComponent) }
            .map { ShaderInfo(name: stripExtension($0.lastPathComponent), path: $0) }
            .sorted { $0.name < $1.name }
    }

    func selectShader(at index: Int) {
        guard index >= 0, index < availableShaders.count else { return }
        currentIndex = index
        let shader = availableShaders[index]
        state = ShaderDisplayState(
            current: shader,
            isLoaded: false,
            error: nil,
            audioTime: state.audioTime,
            syntheticMouse: state.syntheticMouse
        )
    }

    func selectShader(name: String) {
        if let index = availableShaders.firstIndex(where: { $0.name == name }) {
            selectShader(at: index)
        }
    }

    func nextShader() {
        guard !availableShaders.isEmpty else { return }
        selectShader(at: (currentIndex + 1) % availableShaders.count)
    }

    func prevShader() {
        guard !availableShaders.isEmpty else { return }
        selectShader(at: (currentIndex - 1 + availableShaders.count) % availableShaders.count)
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

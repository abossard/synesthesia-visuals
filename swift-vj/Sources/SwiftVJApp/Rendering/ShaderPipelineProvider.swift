// ShaderPipelineProvider.swift - Deep module for shader pipeline acquisition
// Hides metallib lookup, runtime compilation, and caching behind one method.
// Follows "define errors out of existence" — callers never see compilation details.

import Foundation
import Metal
import ShaderRepository

/// Provides ready-to-use Metal render pipeline states for shaders.
///
/// Deep module with one public method: `pipeline(for:)`.
/// Internally resolves shaders through three strategies:
/// 1. In-memory cache (instant)
/// 2. Pre-compiled metallib lookup (fast)
/// 3. Runtime GLSL→Metal compilation (slow, ~80ms, no Xcode needed)
///
/// Thread-safe via actor isolation. Callers never deal with
/// compilation, metallib loading, or GLSL source resolution.
actor ShaderPipelineProvider {

    private let device: MTLDevice
    private let metallibLibrary: MTLLibrary?
    private let vertexFunction: MTLFunction?
    private let glslSourceDirs: [URL]
    private var cache: [String: MTLRenderPipelineState] = [:]

    /// Create a provider backed by a Metal device.
    /// - Parameters:
    ///   - device: Metal device for pipeline creation
    ///   - metallibPaths: Search paths for pre-compiled Shaders.metallib
    ///   - glslSourceDirs: Directories containing `<name>.txt` GLSL source files
    init(device: MTLDevice, metallibPaths: [String] = [], glslSourceDirs: [URL] = []) {
        self.device = device
        self.glslSourceDirs = glslSourceDirs

        // Try to load metallib (optional — runtime compilation works without it)
        var lib: MTLLibrary? = nil
        let searchPaths = metallibPaths + Self.defaultMetallibPaths
        for path in searchPaths where !path.isEmpty {
            if FileManager.default.fileExists(atPath: path),
               let loaded = try? device.makeLibrary(URL: URL(fileURLWithPath: path)) {
                lib = loaded
                print("[PipelineProvider] ✓ Metallib: \(path)")
                break
            }
        }
        if lib == nil {
            print("[PipelineProvider] No metallib found — using runtime compilation")
        }
        self.metallibLibrary = lib
        self.vertexFunction = lib?.makeFunction(name: "vertex_fullscreen")
    }

    // MARK: - Public API (the only public method)

    /// Get a ready-to-use pipeline state for a shader.
    ///
    /// Resolution order: cache → metallib → runtime GLSL compile.
    /// Returns nil only if the shader doesn't exist in any source.
    func pipeline(for shaderName: String) async -> MTLRenderPipelineState? {
        // 1. Cache hit (instant)
        if let cached = cache[shaderName] {
            return cached
        }

        // 2. Metallib lookup
        if let pipeline = pipelineFromMetallib(shaderName) {
            cache[shaderName] = pipeline
            return pipeline
        }

        // 3. Runtime GLSL→Metal compilation
        if let pipeline = await pipelineFromGLSLSource(shaderName) {
            cache[shaderName] = pipeline
            return pipeline
        }

        return nil
    }

    /// Check if a shader can be resolved (without compiling).
    func canResolve(_ shaderName: String) -> Bool {
        if cache[shaderName] != nil { return true }
        if metallibHasShader(shaderName) { return true }
        if findGLSLSource(shaderName) != nil { return true }
        return false
    }

    /// Pre-warm the cache for a set of shader names.
    func precompile(_ shaderNames: [String]) async -> Int {
        var compiled = 0
        for name in shaderNames where cache[name] == nil {
            if await pipeline(for: name) != nil {
                compiled += 1
            }
        }
        return compiled
    }

    // MARK: - Metallib Path (fast)

    private func metallibHasShader(_ name: String) -> Bool {
        guard let lib = metallibLibrary else { return false }
        let funcName = "fragment_\(ShaderCompiler.sanitize(name))"
        return lib.functionNames.contains(funcName)
    }

    private func pipelineFromMetallib(_ shaderName: String) -> MTLRenderPipelineState? {
        guard let lib = metallibLibrary, let vtx = vertexFunction else { return nil }
        let funcName = "fragment_\(ShaderCompiler.sanitize(shaderName))"
        guard let frag = lib.makeFunction(name: funcName) else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vtx
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            let pipeline = try device.makeRenderPipelineState(descriptor: desc)
            print("[PipelineProvider] ✓ Metallib: \(shaderName)")
            return pipeline
        } catch {
            print("[PipelineProvider] ⚠ Metallib pipeline error for '\(shaderName)': \(error)")
            return nil
        }
    }

    // MARK: - Runtime GLSL Compilation Path (slow, ~80ms)

    private func pipelineFromGLSLSource(_ shaderName: String) async -> MTLRenderPipelineState? {
        guard let glslSource = findGLSLSource(shaderName) else { return nil }

        do {
            let result = try await ShaderCompiler.compileToMSL(source: glslSource, name: shaderName)
            guard result.success else {
                print("[PipelineProvider] ❌ Compile failed for '\(shaderName)': \(result.errors.joined(separator: "; "))")
                return nil
            }

            let library = try await device.makeLibrary(source: result.mslSource, options: nil)

            guard let frag = library.makeFunction(name: result.fragmentFunctionName) else {
                print("[PipelineProvider] ❌ Fragment function '\(result.fragmentFunctionName)' not found")
                return nil
            }
            guard let vtx = library.makeFunction(name: "vertex_fullscreen") else {
                print("[PipelineProvider] ❌ Vertex function not found in runtime library")
                return nil
            }

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vtx
            desc.fragmentFunction = frag
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm

            let pipeline = try await device.makeRenderPipelineState(descriptor: desc)
            print("[PipelineProvider] ✓ Runtime compiled: \(shaderName) (\(String(format: "%.0f", result.duration * 1000))ms)")
            return pipeline
        } catch {
            print("[PipelineProvider] ❌ Runtime compilation error for '\(shaderName)': \(error)")
            return nil
        }
    }

    private func findGLSLSource(_ shaderName: String) -> String? {
        let fm = FileManager.default
        for dir in glslSourceDirs {
            let path = dir.appendingPathComponent("\(shaderName).txt")
            if fm.fileExists(atPath: path.path),
               let source = try? String(contentsOf: path, encoding: .utf8) {
                return source
            }
        }
        return nil
    }

    // MARK: - Default Paths

    private static var defaultMetallibPaths: [String] {
        let execURL = Bundle.main.bundleURL
        return [
            execURL.appendingPathComponent("Shaders.metallib").path,
            execURL.appendingPathComponent("Contents/Resources/Shaders.metallib").path,
            Bundle.main.path(forResource: "Shaders", ofType: "metallib") ?? "",
        ].filter { !$0.isEmpty }
    }
}

// ShadertoyRuntime.swift - Module exports and convenience API
// Shadertoy Runtime for SwiftUI + Metal

import Foundation
import Metal
import MetalKit

// MARK: - Module Exports

// Re-export all public types from the module

// Metadata types
public typealias STSizeMode = SizeMode
public typealias STSamplerType = SamplerType
public typealias STFilterMode = FilterMode
public typealias STWrapMode = WrapMode
public typealias STChannelSource = ChannelSource
public typealias STPassName = PassName
public typealias STChannelConfig = ChannelConfig
public typealias STOutputConfig = OutputConfig
public typealias STPassConfig = PassConfig
public typealias STGlobalConfig = GlobalConfig
public typealias STShaderMetadata = ShaderMetadata
public typealias STShaderFolder = ShaderFolder

// Uniforms
public typealias STUniforms = ShadertoyUniforms
public typealias STUniformBuffer = ShadertoyUniformBuffer

// Wrapper generation
public typealias STWrapperGenerator = GLSLWrapperGenerator
public typealias STLegacyConverter = LegacyShaderConverter

// Compilation
public typealias STCompilationPipeline = ShaderCompilationPipeline
public typealias STCompilationResult = ShaderCompilationResult
public typealias STPassCompilationResult = PassCompilationResult
public typealias STReflectionData = ReflectionData

// Bindings
public typealias STResourceManager = ResourceManager
public typealias STDummyResources = DummyResources
public typealias STSamplerCache = SamplerCache
public typealias STPassResourceSet = PassResourceSet

// Rendering
public typealias STRenderer = ShadertoyRenderer
public typealias STShaderInstance = ShaderInstance
public typealias STRenderPassState = RenderPassState

// Diagnostics
public typealias STDiagnostic = Diagnostic
public typealias STDiagnosticSeverity = DiagnosticSeverity
public typealias STPassDiagnosticReport = PassDiagnosticReport
public typealias STShaderDiagnosticReport = ShaderDiagnosticReport
public typealias STBatchDiagnosticReport = BatchDiagnosticReport

// MARK: - Convenience Factory

/// Factory for creating Shadertoy runtime components
public enum ShadertoyFactory {

    /// Create a renderer for the default Metal device
    public static func createRenderer() -> ShadertoyRenderer? {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        return ShadertoyRenderer(device: device)
    }

    /// Create a compilation pipeline with default paths
    public static func createCompilationPipeline(buildDirectory: URL) -> ShaderCompilationPipeline {
        ShaderCompilationPipeline(buildDirectory: buildDirectory)
    }

    /// Load a shader folder
    public static func loadShader(from url: URL) throws -> ShaderFolder {
        try ShaderFolder(url: url)
    }

    /// Generate default metadata for a shader folder
    public static func generateDefaultMetadata(for shaderFolder: ShaderFolder) -> ShaderMetadata {
        shaderFolder.metadata
    }

    /// Create a wrapper generator for a pass
    public static func createWrapperGenerator(for pass: PassConfig) -> GLSLWrapperGenerator {
        WrapperGeneratorFactory.generator(for: pass)
    }
}

// MARK: - Runtime Configuration

/// Configuration options for the Shadertoy runtime
public struct ShadertoyConfiguration: Sendable {
    /// Enable compatibility mode for older shaders
    public var compatibilityMode: Bool

    /// Target frame rate
    public var targetFrameRate: Int

    /// Enable debug overlays
    public var debugMode: Bool

    /// Use argument buffers for binding (when available)
    public var useArgumentBuffers: Bool

    /// Enable shader caching
    public var enableCaching: Bool

    /// Maximum parallel compilation tasks
    public var maxParallelTasks: Int

    public init(
        compatibilityMode: Bool = true,
        targetFrameRate: Int = 60,
        debugMode: Bool = false,
        useArgumentBuffers: Bool = true,
        enableCaching: Bool = true,
        maxParallelTasks: Int = 8
    ) {
        self.compatibilityMode = compatibilityMode
        self.targetFrameRate = targetFrameRate
        self.debugMode = debugMode
        self.useArgumentBuffers = useArgumentBuffers
        self.enableCaching = enableCaching
        self.maxParallelTasks = maxParallelTasks
    }

    public static let `default` = ShadertoyConfiguration()
    public static let debug = ShadertoyConfiguration(debugMode: true)
    public static let performance = ShadertoyConfiguration(
        targetFrameRate: 120,
        debugMode: false,
        useArgumentBuffers: true
    )
}

// MARK: - Version Information

/// Shadertoy Runtime version information
public enum ShadertoyRuntimeVersion {
    public static let major = 1
    public static let minor = 0
    public static let patch = 0

    public static var string: String {
        "\(major).\(minor).\(patch)"
    }

    public static var schemaVersion: String {
        ShaderJSONSchema.schemaVersion
    }
}

// MARK: - Documentation

/**
 # Shadertoy Runtime for SwiftUI + Metal

 A production-grade pipeline for running Shadertoy-style GLSL shaders on macOS/iOS using Metal.

 ## Features

 - **Zero modifications** to original shader source files
 - **Multi-pass support**: Buffer A-D + Image
 - **Feedback/ping-pong** for temporal effects
 - **Stable ABI** across hundreds of shaders
 - **Automatic compatibility** fixes for common Shadertoy issues

 ## Quick Start

 ```swift
 import ShadertoyRuntime
 import SwiftUI

 struct ContentView: View {
     @State private var renderer: ShadertoyRenderer?

     var body: some View {
         ShadertoyView(
             renderer: $renderer,
             shaderFolder: try? ShaderFolder(url: shaderURL)
         )
     }
 }
 ```

 ## Folder Structure

 Each shader should be in its own folder:
 ```
 ShaderName/
   image.glsl           (required) - Main image pass
   bufa.glsl            (optional) - Buffer A
   bufb.glsl            (optional) - Buffer B
   bufc.glsl            (optional) - Buffer C
   bufd.glsl            (optional) - Buffer D
   common.glsl          (optional) - Shared code
   shader.json          (required, auto-generated if missing)
 ```

 ## Uniforms

 All standard Shadertoy uniforms are available:
 - `iResolution` - Viewport resolution
 - `iTime` - Playback time
 - `iTimeDelta` - Frame time
 - `iFrame` - Frame counter
 - `iMouse` - Mouse position
 - `iDate` - Current date
 - `iChannel0-3` - Input textures

 ## Compilation Pipeline

 The offline compilation pipeline converts GLSL to Metal:
 1. Generate wrapper GLSL with compatibility shims
 2. Compile to SPIR-V using glslangValidator
 3. Convert to MSL using SPIRV-Cross
 4. Create Metal pipeline states at runtime

 ## References

 - Shadertoy: https://www.shadertoy.com/howto
 - glslang: https://github.com/KhronosGroup/glslang
 - SPIRV-Cross: https://github.com/KhronosGroup/SPIRV-Cross
 - Metal: https://developer.apple.com/metal/
 */
public enum ShadertoyRuntimeDocumentation {}

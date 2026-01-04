// ShaderCompilationPipeline.swift - GLSL -> SPIR-V -> MSL compilation
// Uses glslangValidator and SPIRV-Cross for cross-compilation

import Foundation

// MARK: - Compilation Result Types

/// Result of a single compilation step
public struct CompilationStepResult: Sendable {
    public let success: Bool
    public let output: String
    public let errors: [String]
    public let warnings: [String]
    public let duration: TimeInterval

    public init(success: Bool, output: String = "", errors: [String] = [], warnings: [String] = [], duration: TimeInterval = 0) {
        self.success = success
        self.output = output
        self.errors = errors
        self.warnings = warnings
        self.duration = duration
    }
}

/// Complete compilation result for a shader pass
public struct PassCompilationResult: Sendable {
    public let passName: PassName
    public let wrapperGeneration: CompilationStepResult
    public let spirvCompilation: CompilationStepResult
    public let mslConversion: CompilationStepResult
    public let reflection: ReflectionData?

    public var success: Bool {
        wrapperGeneration.success && spirvCompilation.success && mslConversion.success
    }

    public var allErrors: [String] {
        wrapperGeneration.errors + spirvCompilation.errors + mslConversion.errors
    }

    public var allWarnings: [String] {
        wrapperGeneration.warnings + spirvCompilation.warnings + mslConversion.warnings
    }
}

/// Complete compilation result for a shader folder
public struct ShaderCompilationResult: Sendable {
    public let shaderName: String
    public let shaderPath: URL
    public let passes: [PassCompilationResult]
    public let totalDuration: TimeInterval

    public var success: Bool {
        passes.allSatisfy { $0.success }
    }

    public var failedPasses: [PassName] {
        passes.filter { !$0.success }.map { $0.passName }
    }
}

// MARK: - Reflection Data

/// Parsed reflection data from SPIRV-Cross
public struct ReflectionData: Sendable, Codable {
    public let uniforms: [UniformInfo]
    public let textures: [TextureInfo]
    public let samplers: [SamplerInfo]
    public let pushConstants: [PushConstantInfo]

    public struct UniformInfo: Sendable, Codable {
        public let name: String
        public let type: String
        public let binding: Int
        public let set: Int
        public let offset: Int
        public let size: Int
    }

    public struct TextureInfo: Sendable, Codable {
        public let name: String
        public let binding: Int
        public let set: Int
        public let type: String  // "texture2d", "texturecube"
    }

    public struct SamplerInfo: Sendable, Codable {
        public let name: String
        public let binding: Int
        public let set: Int
    }

    public struct PushConstantInfo: Sendable, Codable {
        public let name: String
        public let offset: Int
        public let size: Int
    }
}

// MARK: - Compilation Pipeline

/// Orchestrates shader compilation: GLSL -> SPIR-V -> MSL
public actor ShaderCompilationPipeline {

    // MARK: - Configuration

    /// Path to glslangValidator executable
    public let glslangPath: String

    /// Path to spirv-cross executable
    public let spirvCrossPath: String

    /// Build output directory
    public let buildDirectory: URL

    /// Cache directory for content-hashed artifacts
    public let cacheDirectory: URL

    /// Enable parallel compilation
    public let parallelCompilation: Bool

    /// Maximum parallel tasks
    public let maxParallelTasks: Int

    // MARK: - Initialization

    public init(
        glslangPath: String = "/usr/local/bin/glslangValidator",
        spirvCrossPath: String = "/usr/local/bin/spirv-cross",
        buildDirectory: URL,
        cacheDirectory: URL? = nil,
        parallelCompilation: Bool = true,
        maxParallelTasks: Int = 8
    ) {
        self.glslangPath = glslangPath
        self.spirvCrossPath = spirvCrossPath
        self.buildDirectory = buildDirectory
        self.cacheDirectory = cacheDirectory ?? buildDirectory.appendingPathComponent("cache")
        self.parallelCompilation = parallelCompilation
        self.maxParallelTasks = maxParallelTasks
    }

    // MARK: - Public API

    /// Compile a single shader folder
    public func compile(shaderFolder: ShaderFolder) async throws -> ShaderCompilationResult {
        let startTime = Date()

        // Create output directory
        let outputDir = buildDirectory.appendingPathComponent(shaderFolder.name)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Load common.glsl if present
        var commonSource: String? = nil
        if let commonURL = shaderFolder.commonURL {
            commonSource = try String(contentsOf: commonURL, encoding: .utf8)
        }

        // Compile each pass
        var passResults: [PassCompilationResult] = []

        for passConfig in shaderFolder.metadata.sortedPasses {
            guard let sourceURL = shaderFolder.sourceURL(for: passConfig.name) else {
                // Pass not found - skip with error
                passResults.append(PassCompilationResult(
                    passName: passConfig.name,
                    wrapperGeneration: CompilationStepResult(success: false, errors: ["Source file not found"]),
                    spirvCompilation: CompilationStepResult(success: false),
                    mslConversion: CompilationStepResult(success: false),
                    reflection: nil
                ))
                continue
            }

            let result = try await compilePass(
                passConfig: passConfig,
                sourceURL: sourceURL,
                commonSource: commonSource,
                outputDir: outputDir
            )
            passResults.append(result)
        }

        let totalDuration = Date().timeIntervalSince(startTime)

        return ShaderCompilationResult(
            shaderName: shaderFolder.name,
            shaderPath: shaderFolder.url,
            passes: passResults,
            totalDuration: totalDuration
        )
    }

    /// Compile all shaders in a directory
    public func compileAll(shadersDirectory: URL) async throws -> [ShaderCompilationResult] {
        let fm = FileManager.default

        // Find all shader folders
        let contents = try fm.contentsOfDirectory(at: shadersDirectory, includingPropertiesForKeys: [.isDirectoryKey])

        var shaderFolders: [ShaderFolder] = []

        for url in contents {
            // Check if it's a directory
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                do {
                    let folder = try ShaderFolder(url: url)
                    shaderFolders.append(folder)
                } catch {
                    print("Skipping \(url.lastPathComponent): \(error)")
                }
            }
        }

        // Compile all shaders
        if parallelCompilation {
            return try await withThrowingTaskGroup(of: ShaderCompilationResult.self) { group in
                for folder in shaderFolders {
                    group.addTask {
                        try await self.compile(shaderFolder: folder)
                    }
                }

                var results: [ShaderCompilationResult] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }
        } else {
            var results: [ShaderCompilationResult] = []
            for folder in shaderFolders {
                let result = try await compile(shaderFolder: folder)
                results.append(result)
            }
            return results
        }
    }

    // MARK: - Private Compilation Steps

    /// Compile a single pass
    private func compilePass(
        passConfig: PassConfig,
        sourceURL: URL,
        commonSource: String?,
        outputDir: URL
    ) async throws -> PassCompilationResult {

        let passName = passConfig.name.rawValue

        // Step 1: Generate wrapper GLSL
        let wrapperResult = try generateWrapper(
            passConfig: passConfig,
            sourceURL: sourceURL,
            commonSource: commonSource,
            outputDir: outputDir
        )

        guard wrapperResult.success else {
            return PassCompilationResult(
                passName: passConfig.name,
                wrapperGeneration: wrapperResult,
                spirvCompilation: CompilationStepResult(success: false),
                mslConversion: CompilationStepResult(success: false),
                reflection: nil
            )
        }

        // Step 2: Compile to SPIR-V
        let wrapperPath = outputDir.appendingPathComponent("\(passName).glsl")
        let spvPath = outputDir.appendingPathComponent("\(passName).spv")

        let spirvResult = try await compileSPIRV(
            inputPath: wrapperPath,
            outputPath: spvPath
        )

        guard spirvResult.success else {
            return PassCompilationResult(
                passName: passConfig.name,
                wrapperGeneration: wrapperResult,
                spirvCompilation: spirvResult,
                mslConversion: CompilationStepResult(success: false),
                reflection: nil
            )
        }

        // Step 3: Convert to MSL
        let mslPath = outputDir.appendingPathComponent("\(passName).metal")
        let reflectPath = outputDir.appendingPathComponent("\(passName).reflect.json")

        let mslResult = try await convertToMSL(
            inputPath: spvPath,
            outputPath: mslPath,
            reflectionPath: reflectPath
        )

        // Load reflection data
        var reflection: ReflectionData? = nil
        if FileManager.default.fileExists(atPath: reflectPath.path) {
            if let data = try? Data(contentsOf: reflectPath),
               let parsed = try? JSONDecoder().decode(ReflectionData.self, from: data) {
                reflection = parsed
            }
        }

        return PassCompilationResult(
            passName: passConfig.name,
            wrapperGeneration: wrapperResult,
            spirvCompilation: spirvResult,
            mslConversion: mslResult,
            reflection: reflection
        )
    }

    /// Generate wrapper GLSL file
    private func generateWrapper(
        passConfig: PassConfig,
        sourceURL: URL,
        commonSource: String?,
        outputDir: URL
    ) throws -> CompilationStepResult {
        let startTime = Date()

        do {
            let originalSource = try String(contentsOf: sourceURL, encoding: .utf8)

            let generator = WrapperGeneratorFactory.generator(for: passConfig)
            let wrappedSource = generator.generateWrapper(
                originalSource: originalSource,
                commonSource: commonSource
            )

            let outputPath = outputDir.appendingPathComponent("\(passConfig.name.rawValue).glsl")
            try wrappedSource.write(to: outputPath, atomically: true, encoding: .utf8)

            let duration = Date().timeIntervalSince(startTime)
            return CompilationStepResult(success: true, output: outputPath.path, duration: duration)

        } catch {
            let duration = Date().timeIntervalSince(startTime)
            return CompilationStepResult(success: false, errors: [error.localizedDescription], duration: duration)
        }
    }

    /// Compile GLSL to SPIR-V using glslangValidator
    private func compileSPIRV(inputPath: URL, outputPath: URL) async throws -> CompilationStepResult {
        let startTime = Date()

        // glslangValidator arguments
        // Reference: https://manpages.debian.org/testing/glslang-tools/glslangValidator.1.en.html
        let arguments = [
            "-V",                           // Generate SPIR-V for Vulkan
            "-S", "frag",                   // Fragment shader stage
            "-o", outputPath.path,          // Output file
            "--target-env", "vulkan1.1",    // Target environment
            "-g",                           // Include debug info
            inputPath.path                  // Input file
        ]

        let result = try await runProcess(executable: glslangPath, arguments: arguments)

        let duration = Date().timeIntervalSince(startTime)

        if result.exitCode == 0 {
            return CompilationStepResult(
                success: true,
                output: outputPath.path,
                warnings: parseGlslangWarnings(result.stderr),
                duration: duration
            )
        } else {
            return CompilationStepResult(
                success: false,
                errors: parseGlslangErrors(result.stderr + result.stdout),
                warnings: parseGlslangWarnings(result.stderr),
                duration: duration
            )
        }
    }

    /// Convert SPIR-V to MSL using spirv-cross
    private func convertToMSL(inputPath: URL, outputPath: URL, reflectionPath: URL) async throws -> CompilationStepResult {
        let startTime = Date()

        // spirv-cross arguments for Metal
        // Reference: https://manpages.ubuntu.com/manpages/jammy/man1/spirv-cross.1.html
        // Reference for argument buffers: spirv_msl.hpp force_active_argument_buffer_resources
        let arguments = [
            inputPath.path,
            "--msl",                                    // Output MSL
            "--msl-version", "20200",                   // Metal 2.2 (macOS 10.15+)
            "--msl-argument-buffers",                   // Use argument buffers
            "--msl-force-active-argument-buffer-resources", // Force all resources active for stable ABI
            "--msl-decoration-binding",                 // Honor binding decorations
            "--msl-texture-buffer-native",              // Native texture buffer support
            "-o", outputPath.path,                      // Output file
            "--reflect",                                // Generate reflection
            "--output", reflectionPath.path.replacingOccurrences(of: ".json", with: ".reflect")
        ]

        let result = try await runProcess(executable: spirvCrossPath, arguments: arguments)

        let duration = Date().timeIntervalSince(startTime)

        if result.exitCode == 0 {
            // Parse reflection output and convert to JSON
            try await generateReflectionJSON(from: outputPath, to: reflectionPath)

            return CompilationStepResult(
                success: true,
                output: outputPath.path,
                warnings: parseSpirvCrossWarnings(result.stderr),
                duration: duration
            )
        } else {
            return CompilationStepResult(
                success: false,
                errors: [result.stderr, result.stdout].filter { !$0.isEmpty },
                duration: duration
            )
        }
    }

    /// Generate reflection JSON from MSL source
    private func generateReflectionJSON(from mslPath: URL, to jsonPath: URL) async throws {
        // Parse the MSL to extract binding information
        // This is a simplified implementation - full version would parse MSL AST

        let mslSource = try String(contentsOf: mslPath, encoding: .utf8)

        var uniforms: [ReflectionData.UniformInfo] = []
        var textures: [ReflectionData.TextureInfo] = []
        var samplers: [ReflectionData.SamplerInfo] = []

        // Extract uniform buffer bindings
        let uniformPattern = "\\[\\[buffer\\((\\d+)\\)\\]\\]"
        if let regex = try? NSRegularExpression(pattern: uniformPattern, options: []) {
            let matches = regex.matches(in: mslSource, options: [], range: NSRange(mslSource.startIndex..., in: mslSource))
            for match in matches {
                if let bindingRange = Range(match.range(at: 1), in: mslSource) {
                    if let binding = Int(mslSource[bindingRange]) {
                        uniforms.append(ReflectionData.UniformInfo(
                            name: "uniforms",
                            type: "struct",
                            binding: binding,
                            set: 0,
                            offset: 0,
                            size: 256
                        ))
                    }
                }
            }
        }

        // Extract texture bindings
        let texturePattern = "texture2d<[^>]+>\\s+\\w+\\s+\\[\\[texture\\((\\d+)\\)\\]\\]"
        if let regex = try? NSRegularExpression(pattern: texturePattern, options: []) {
            let matches = regex.matches(in: mslSource, options: [], range: NSRange(mslSource.startIndex..., in: mslSource))
            for (index, match) in matches.enumerated() {
                if let bindingRange = Range(match.range(at: 1), in: mslSource) {
                    if let binding = Int(mslSource[bindingRange]) {
                        textures.append(ReflectionData.TextureInfo(
                            name: "iChannel\(index)",
                            binding: binding,
                            set: 0,
                            type: "texture2d"
                        ))
                    }
                }
            }
        }

        // Extract sampler bindings
        let samplerPattern = "sampler\\s+\\w+\\s+\\[\\[sampler\\((\\d+)\\)\\]\\]"
        if let regex = try? NSRegularExpression(pattern: samplerPattern, options: []) {
            let matches = regex.matches(in: mslSource, options: [], range: NSRange(mslSource.startIndex..., in: mslSource))
            for (index, match) in matches.enumerated() {
                if let bindingRange = Range(match.range(at: 1), in: mslSource) {
                    if let binding = Int(mslSource[bindingRange]) {
                        samplers.append(ReflectionData.SamplerInfo(
                            name: "sampler\(index)",
                            binding: binding,
                            set: 0
                        ))
                    }
                }
            }
        }

        let reflection = ReflectionData(
            uniforms: uniforms,
            textures: textures,
            samplers: samplers,
            pushConstants: []
        )

        let jsonData = try JSONEncoder().encode(reflection)
        try jsonData.write(to: jsonPath)
    }

    // MARK: - Process Execution

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcess(executable: String, arguments: [String]) async throws -> ProcessResult {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                ))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Error Parsing

    private func parseGlslangErrors(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .filter { $0.contains("ERROR:") }
    }

    private func parseGlslangWarnings(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .filter { $0.contains("WARNING:") }
    }

    private func parseSpirvCrossWarnings(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .filter { $0.lowercased().contains("warning") }
    }
}

// MARK: - Content Hashing for Caching

extension ShaderCompilationPipeline {

    /// Generate content hash for cache lookup
    public func contentHash(for source: String) -> String {
        var hasher = Hasher()
        hasher.combine(source)
        let hash = hasher.finalize()
        return String(format: "%016llx", UInt64(bitPattern: Int64(hash)))
    }

    /// Check if cached artifact exists
    public func cachedArtifact(hash: String, type: String) -> URL? {
        let cachePath = cacheDirectory.appendingPathComponent("\(hash).\(type)")
        if FileManager.default.fileExists(atPath: cachePath.path) {
            return cachePath
        }
        return nil
    }

    /// Store artifact in cache
    public func cacheArtifact(data: Data, hash: String, type: String) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let cachePath = cacheDirectory.appendingPathComponent("\(hash).\(type)")
        try data.write(to: cachePath)
    }
}

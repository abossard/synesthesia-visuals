// ShaderCompiler.swift - Compile GLSL shaders to Metal library
// Pure functions wrapping external tools (glslangValidator, spirv-cross, xcrun)

import Foundation

// MARK: - ShaderCompiler

/// Compile GLSL shaders to Metal library
public enum ShaderCompiler {
    
    // MARK: - Configuration
    
    /// Compiler configuration
    public struct Config: Sendable {
        public let glslangPath: String
        public let spirvCrossPath: String
        public let xcrunPath: String
        public let buildDirectory: URL
        public let shadersDirectory: URL
        public let metallibName: String
        public let outputDirectory: URL?
        
        public init(
            glslangPath: String = "/opt/homebrew/bin/glslangValidator",
            spirvCrossPath: String = "/opt/homebrew/bin/spirv-cross",
            xcrunPath: String = "/usr/bin/xcrun",
            buildDirectory: URL,
            shadersDirectory: URL,
            metallibName: String = "Shaders.metallib",
            outputDirectory: URL? = nil
        ) {
            self.glslangPath = glslangPath
            self.spirvCrossPath = spirvCrossPath
            self.xcrunPath = xcrunPath
            self.buildDirectory = buildDirectory
            self.shadersDirectory = shadersDirectory
            self.metallibName = metallibName
            self.outputDirectory = outputDirectory
        }
        
        /// Final metallib output path
        public var metallibURL: URL {
            (outputDirectory ?? buildDirectory).appendingPathComponent(metallibName)
        }
    }
    
    /// Compilation result for a single shader
    public struct ShaderResult: Sendable {
        public let shaderName: String
        public let success: Bool
        public let metalPath: URL?
        public let errors: [String]
        public let duration: TimeInterval
    }
    
    /// Complete compilation result
    public struct CompilationResult: Sendable {
        public let shaders: [ShaderResult]
        public let metallibPath: URL?
        public let totalDuration: TimeInterval
        
        public var successCount: Int { shaders.filter { $0.success }.count }
        public var failCount: Int { shaders.filter { !$0.success }.count }
        public var success: Bool { metallibPath != nil }
    }
    
    // MARK: - GLSL Wrapper Template
    
    /// GLSL wrapper prefix for flat shaders (matches convert-flat-glsl.sh)
    static let glslWrapperPrefix = """
        #version 450

        layout(binding = 0) uniform Uniforms {
            float time;
            vec2 resolution;
            vec2 mouse;
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
            float bassPresence;
            float midPresence;
            float highPresence;
            float bpmTwitcher;
            float bpmSin4;
            float bpmConfidence;
            float audioTime;
            float bin0;
            float bin1;
            float bin2;
            float zoom;
        } _uniforms_;

        layout(binding = 1) uniform sampler2D backbuffer;

        layout(location = 0) out vec4 fragColor;

        // Y-flip for Metal coordinate system
        vec4 _flipped_FragCoord() {
            return vec4(gl_FragCoord.x, _uniforms_.resolution.y - gl_FragCoord.y, gl_FragCoord.zw);
        }

        // GLSL compatibility macros - remap uniforms to block members
        #define time _uniforms_.time
        #define resolution _uniforms_.resolution
        #define mouse _uniforms_.mouse
        #define speed _uniforms_.speed
        #define bass _uniforms_.bass
        #define lowMid _uniforms_.lowMid
        #define mid _uniforms_.mid
        #define highs _uniforms_.highs
        #define level _uniforms_.level
        #define kickEnv _uniforms_.kickEnv
        #define kickPulse _uniforms_.kickPulse
        #define beat _uniforms_.beat
        #define energyFast _uniforms_.energyFast
        #define energySlow _uniforms_.energySlow
        #define bassPresence _uniforms_.bassPresence
        #define midPresence _uniforms_.midPresence
        #define highPresence _uniforms_.highPresence
        #define bpmTwitcher _uniforms_.bpmTwitcher
        #define bpmSin4 _uniforms_.bpmSin4
        #define bpmConfidence _uniforms_.bpmConfidence
        #define audioTime _uniforms_.audioTime
        #define bin0 _uniforms_.bin0
        #define bin1 _uniforms_.bin1
        #define bin2 _uniforms_.bin2
        #define zoom _uniforms_.zoom
        #define texture2D texture
        #define lowp
        #define mediump
        #define highp

        """
    
    // MARK: - Compilation Pipeline
    
    /// Compile all shaders in the configured directories to a metallib
    public static func compileAll(config: Config) async throws -> CompilationResult {
        let startTime = Date()
        let fm = FileManager.default
        
        // Create build directories
        let airDir = config.buildDirectory.appendingPathComponent("air")
        try fm.createDirectory(at: config.buildDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: airDir, withIntermediateDirectories: true)
        
        // Find all shader folders (glsl, masks)
        let shaderFolders = ["glsl", "masks"]
        var shaderResults: [ShaderResult] = []
        var metalFiles: [URL] = []
        
        for folder in shaderFolders {
            let folderURL = config.shadersDirectory.appendingPathComponent(folder)
            guard fm.fileExists(atPath: folderURL.path) else { continue }
            
            let files = try fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
            let txtFiles = files.filter { $0.pathExtension == "txt" }
            
            for txtFile in txtFiles {
                let result = await compileShader(
                    sourceURL: txtFile,
                    buildDirectory: config.buildDirectory,
                    config: config
                )
                shaderResults.append(result)
                
                if result.success, let metalPath = result.metalPath {
                    metalFiles.append(metalPath)
                }
            }
        }
        
        // Copy SharedVertex.metal if it exists
        let sharedVertexSource = config.shadersDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftVJApp/Resources/SharedVertex.metal")
        let sharedVertexDest = config.buildDirectory.appendingPathComponent("SharedVertex.metal")
        
        if fm.fileExists(atPath: sharedVertexSource.path) {
            try? fm.copyItem(at: sharedVertexSource, to: sharedVertexDest)
            metalFiles.append(sharedVertexDest)
        }
        
        // Compile to .air files
        var airFiles: [URL] = []
        for metalFile in metalFiles {
            let airFile = airDir.appendingPathComponent(
                metalFile.deletingPathExtension().lastPathComponent + ".air"
            )
            
            let result = try await runProcess(
                executable: config.xcrunPath,
                arguments: ["metal", "-c", metalFile.path, "-o", airFile.path]
            )
            
            if result.exitCode == 0 {
                airFiles.append(airFile)
            }
        }
        
        // Link metallib
        var metallibPath: URL? = nil
        if !airFiles.isEmpty {
            let outputPath = config.metallibURL
            
            // Ensure output directory exists
            try fm.createDirectory(at: outputPath.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            let result = try await runProcess(
                executable: config.xcrunPath,
                arguments: ["metallib"] + airFiles.map { $0.path } + ["-o", outputPath.path]
            )
            
            if result.exitCode == 0 {
                metallibPath = outputPath
            }
        }
        
        let totalDuration = Date().timeIntervalSince(startTime)
        
        return CompilationResult(
            shaders: shaderResults,
            metallibPath: metallibPath,
            totalDuration: totalDuration
        )
    }
    
    /// Compile a single shader file
    public static func compileShader(
        sourceURL: URL,
        buildDirectory: URL,
        config: Config
    ) async -> ShaderResult {
        let startTime = Date()
        let shaderName = sourceURL.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        
        // Create temp directory for intermediate files
        let tempDir = buildDirectory.appendingPathComponent("temp_\(shaderName)")
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        
        do {
            // Step 1: Read and wrap GLSL
            let originalSource = try String(contentsOf: sourceURL, encoding: .utf8)
            let wrappedSource = wrapGLSL(source: originalSource)
            
            let wrappedPath = tempDir.appendingPathComponent("wrapped.frag")
            try wrappedSource.write(to: wrappedPath, atomically: true, encoding: .utf8)
            
            // Step 2: Compile to SPIR-V
            let spvPath = tempDir.appendingPathComponent("shader.spv")
            let glslResult = try await runProcess(
                executable: config.glslangPath,
                arguments: ["-V", "-S", "frag", wrappedPath.path, "-o", spvPath.path]
            )
            
            if glslResult.exitCode != 0 {
                return ShaderResult(
                    shaderName: shaderName,
                    success: false,
                    metalPath: nil,
                    errors: parseErrors(glslResult.stderr + glslResult.stdout),
                    duration: Date().timeIntervalSince(startTime)
                )
            }
            
            // Step 3: Convert to Metal
            let funcName = "fragment_" + sanitizeFunctionName(shaderName)
            let metalPath = buildDirectory.appendingPathComponent("\(shaderName).metal")
            
            let spirvResult = try await runProcess(
                executable: config.spirvCrossPath,
                arguments: [
                    "--msl", spvPath.path,
                    "--rename-entry-point", "main", funcName, "frag",
                    "--output", metalPath.path
                ]
            )
            
            if spirvResult.exitCode != 0 {
                return ShaderResult(
                    shaderName: shaderName,
                    success: false,
                    metalPath: nil,
                    errors: parseErrors(spirvResult.stderr),
                    duration: Date().timeIntervalSince(startTime)
                )
            }
            
            return ShaderResult(
                shaderName: shaderName,
                success: true,
                metalPath: metalPath,
                errors: [],
                duration: Date().timeIntervalSince(startTime)
            )
            
        } catch {
            return ShaderResult(
                shaderName: shaderName,
                success: false,
                metalPath: nil,
                errors: [error.localizedDescription],
                duration: Date().timeIntervalSince(startTime)
            )
        }
    }
    
    // MARK: - GLSL Processing
    
    /// Wrap flat GLSL shader with compatibility header
    public static func wrapGLSL(source: String) -> String {
        // Clean up source (remove incompatible constructs)
        var cleaned = source
        
        // Remove GL_ES blocks
        cleaned = removeGLESBlocks(from: cleaned)
        
        // Remove uniform declarations (we provide them in the wrapper)
        cleaned = removeLines(matching: "^\\s*uniform\\s+", from: cleaned)
        
        // Remove precision qualifiers
        cleaned = removeLines(matching: "^\\s*precision\\s+", from: cleaned)
        
        // Remove varying/attribute
        cleaned = removeLines(matching: "^\\s*(varying|attribute)\\s+", from: cleaned)
        
        // Remove conflicting #define statements for uniform names we inject
        cleaned = removeConflictingDefines(from: cleaned)
        
        // Replace gl_FragColor -> fragColor
        cleaned = cleaned.replacingOccurrences(of: "gl_FragColor", with: "fragColor")
        
        // Replace gl_FragCoord -> _flipped_FragCoord()
        cleaned = cleaned.replacingOccurrences(of: "gl_FragCoord", with: "_flipped_FragCoord()")
        
        // Handle local variable shadowing
        cleaned = renameShadowedVariables(in: cleaned)
        
        // Rename conflicting built-in functions
        cleaned = renameConflictingFunctions(in: cleaned)
        
        return glslWrapperPrefix + cleaned
    }
    
    /// Remove #define statements that conflict with our uniform macros
    private static func removeConflictingDefines(from source: String) -> String {
        // Names we define as macros in the wrapper - if shader has its own #define for these, remove them
        let uniformNames = [
            "time", "resolution", "mouse", "speed", "bass", "lowMid", "mid", "highs",
            "level", "kickEnv", "kickPulse", "beat", "energyFast", "energySlow",
            "bassPresence", "midPresence", "highPresence", "bpmTwitcher", "bpmSin4",
            "bpmConfidence", "audioTime", "bin0", "bin1", "bin2", "zoom"
        ]
        
        var result = source
        for name in uniformNames {
            // Remove lines like "#define speed 0.25"
            result = removeLines(matching: "^\\s*#define\\s+\(name)\\s+", from: result)
        }
        return result
    }
    
    /// Remove #ifdef GL_ES ... #endif blocks
    private static func removeGLESBlocks(from source: String) -> String {
        var result = source
        
        // Simple pattern matching for GL_ES blocks
        while let startRange = result.range(of: "#ifdef GL_ES") {
            if let endRange = result.range(of: "#endif", range: startRange.upperBound..<result.endIndex) {
                result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
            } else {
                break
            }
        }
        
        return result
    }
    
    /// Remove lines matching a regex pattern
    private static func removeLines(matching pattern: String, from source: String) -> String {
        let lines = source.components(separatedBy: .newlines)
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        
        let filtered = lines.filter { line in
            guard let regex = regex else { return true }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            return regex.firstMatch(in: line, options: [], range: range) == nil
        }
        
        return filtered.joined(separator: "\n")
    }
    
    /// Rename local variables that shadow uniforms
    private static func renameShadowedVariables(in source: String) -> String {
        var result = source
        
        // First, strip comments to avoid false matches
        let sourceWithoutComments = stripComments(from: result)
        
        // Handle specific patterns where local variables shadow uniforms
        // Pattern: "float time = time;" or "vec2 mouse = ... mouse ..."
        // We need to rename the LOCAL variable, not uses of the uniform
        
        // For "float time = time;" pattern - rename LHS declaration only, keep RHS as uniform
        // After: "float _localTime = time;" where time becomes _uniforms_.time via macro
        result = handleSelfAssignment(in: result, sourceWithoutComments: sourceWithoutComments, 
                                       varName: "time", typeName: "float", localName: "_localTime")
        result = handleSelfAssignment(in: result, sourceWithoutComments: sourceWithoutComments,
                                       varName: "mouse", typeName: "vec2", localName: "_localMouse")
        result = handleSelfAssignment(in: result, sourceWithoutComments: sourceWithoutComments,
                                       varName: "zoom", typeName: "float", localName: "_localZoom")
        result = handleSelfAssignment(in: result, sourceWithoutComments: sourceWithoutComments,
                                       varName: "speed", typeName: "float", localName: "_localSpeed")
        
        // Handle function parameters: "void foo(float time)" -> "void foo(float _t)"
        let paramPatterns = [
            ("\\(float time(\\s*[,)])", "(float _t$1"),
            (",\\s*float time(\\s*[,)])", ", float _t$1"),
            ("\\(float speed(\\s*[,)])", "(float _spd$1"),
            (",\\s*float speed(\\s*[,)])", ", float _spd$1"),
            ("\\(float zoom(\\s*[,)])", "(float _zm$1"),
            (",\\s*float zoom(\\s*[,)])", ", float _zm$1"),
            ("\\(vec2 mouse(\\s*[,)])", "(vec2 _m$1"),
            (",\\s*vec2 mouse(\\s*[,)])", ", vec2 _m$1"),
        ]
        
        for (pattern, replacement) in paramPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..<result.endIndex, in: result),
                    withTemplate: replacement
                )
            }
        }
        
        // Other specific patterns
        let otherPatterns = [
            // Reserved word: filter - used as variable name
            ("float filter(\\s*=)", "float _filter$1"),
            ("([^_a-zA-Z0-9])filter([^_a-zA-Z0-9(])", "$1_filter$2"),
            // Rename 'bb' sampler to 'backbuffer'  
            ("sampler2D bb([^a-zA-Z0-9])", "sampler2D backbuffer$1"),
            ("texture2D\\(bb,", "texture(backbuffer,"),
            ("texture\\(bb,", "texture(backbuffer,"),
            ("([^_a-zA-Z0-9])bb([^_a-zA-Z0-9])", "$1backbuffer$2"),
        ]
        
        for (pattern, replacement) in otherPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..<result.endIndex, in: result),
                    withTemplate: replacement
                )
            }
        }
        
        return result
    }
    
    /// Handle pattern like "float time = time;" -> "float _localTime = time;" 
    /// and rename subsequent uses in the same scope
    private static func handleSelfAssignment(in source: String, sourceWithoutComments: String,
                                              varName: String, typeName: String, localName: String) -> String {
        // Check if shader has "type varName = ..." as a local variable (not in comments)
        // Must NOT be a function declaration like "vec2 zoom(vec2 p, float f)"
        let localDeclPattern = "\(typeName)\\s+\(varName)\\s*="
        guard let declRegex = try? NSRegularExpression(pattern: localDeclPattern, options: []),
              declRegex.firstMatch(in: sourceWithoutComments, options: [], 
                                   range: NSRange(sourceWithoutComments.startIndex..<sourceWithoutComments.endIndex, 
                                                  in: sourceWithoutComments)) != nil else {
            return source  // No local declaration found
        }
        
        var result = source
        
        // Step 1: Rename the declaration. Handle "type name = name;" specially to preserve RHS
        // Pattern: "float time = time" -> "float _localTime = time"
        let selfAssignPattern = "(\(typeName)\\s+)\(varName)(\\s*=\\s*)\(varName)([^_a-zA-Z0-9])"
        if let selfRegex = try? NSRegularExpression(pattern: selfAssignPattern, options: []) {
            result = selfRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..<result.endIndex, in: result),
                withTemplate: "$1\(localName)$2\(varName)$3"
            )
        }
        
        // Step 2: Rename other declarations: "type name = expr" -> "type _local = expr"
        let otherDeclPattern = "(\(typeName)\\s+)\(varName)(\\s*=)"
        if let otherRegex = try? NSRegularExpression(pattern: otherDeclPattern, options: []) {
            result = otherRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..<result.endIndex, in: result),
                withTemplate: "$1\(localName)$2"
            )
        }
        
        // Step 3: Rename assignment targets: "name = ..." -> "_local = ..." (modification of local)
        // Only match at start of statement (after ; or { or newline)
        let assignPattern = "([;{}\\n]\\s*)\(varName)(\\s*[+\\-*/]?=)"
        if let assignRegex = try? NSRegularExpression(pattern: assignPattern, options: []) {
            result = assignRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..<result.endIndex, in: result),
                withTemplate: "$1\(localName)$2"
            )
        }
        
        return result
    }
    
    /// Strip C-style comments from source for pattern matching
    private static func stripComments(from source: String) -> String {
        var result = source
        
        // Remove single-line comments
        if let regex = try? NSRegularExpression(pattern: "//.*$", options: .anchorsMatchLines) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..<result.endIndex, in: result),
                withTemplate: ""
            )
        }
        
        // Remove multi-line comments
        if let regex = try? NSRegularExpression(pattern: "/\\*.*?\\*/", options: .dotMatchesLineSeparators) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..<result.endIndex, in: result),
                withTemplate: ""
            )
        }
        
        return result
    }
    
    /// Rename functions that conflict with GLSL 4.5 built-ins
    private static func renameConflictingFunctions(in source: String) -> String {
        var result = source
        
        // Functions that conflict with GLSL 4.5+
        let conflicting = ["round", "sinh", "cosh", "tanh"]
        
        for name in conflicting {
            // Rename function definitions: "float round(" -> "float _round("
            let defPattern = "(float|vec\\d|int)\\s+\(name)\\s*\\("
            if let regex = try? NSRegularExpression(pattern: defPattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..<result.endIndex, in: result),
                    withTemplate: "$1 _\(name)("
                )
            }
            
            // Rename function calls: "round(" -> "_round(" (but not "ground(" etc)
            let callPattern = "([^_a-zA-Z0-9])\(name)\\("
            if let regex = try? NSRegularExpression(pattern: callPattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..<result.endIndex, in: result),
                    withTemplate: "$1_\(name)("
                )
            }
        }
        
        return result
    }
    
    /// Sanitize shader name for use as Metal function name
    private static func sanitizeFunctionName(_ name: String) -> String {
        var result = ""
        for char in name {
            if char.isLetter || char.isNumber || char == "_" {
                result.append(char)
            } else {
                result.append("_")
            }
        }
        return result
    }
    
    // MARK: - Process Execution
    
    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }
    
    private static func runProcess(executable: String, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
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
    
    private static func parseErrors(_ output: String) -> [String] {
        output.components(separatedBy: .newlines)
            .filter { $0.contains("ERROR:") || $0.contains("error:") }
    }
}

// MARK: - CLI Support

extension ShaderCompiler {
    
    /// Print compilation report to stdout
    public static func printReport(_ result: CompilationResult) {
        print("Shader Compilation Report")
        print("=========================")
        print("Success: \(result.successCount), Failed: \(result.failCount)")
        print("Duration: \(String(format: "%.2f", result.totalDuration))s")
        print("")
        
        if result.failCount > 0 {
            print("Failed shaders:")
            for shader in result.shaders where !shader.success {
                print("  - \(shader.shaderName)")
                for error in shader.errors {
                    print("    \(error)")
                }
            }
            print("")
        }
        
        if let metallib = result.metallibPath {
            print("Output: \(metallib.path)")
            if let attrs = try? FileManager.default.attributesOfItem(atPath: metallib.path),
               let size = attrs[.size] as? Int {
                print("Size: \(size / 1024) KB")
            }
        }
    }
}

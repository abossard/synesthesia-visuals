// SPDX-License-Identifier: MIT
// CompileShaders CLI - compile GLSL shaders to Metal
//
// Usage: swift run compile-shaders [--shaders-dir DIR] [--build-dir DIR] [--output FILE]

import ArgumentParser
import Foundation
import ShaderRepository

@main
struct CompileShaders: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compile GLSL shaders to Metal metallib",
        discussion: """
            Converts all .txt GLSL shaders in the shaders directory to Metal,
            compiling them into a single .metallib file.
            
            Pipeline: GLSL → SPIR-V → Metal → AIR → metallib
            """
    )
    
    @Option(name: .shortAndLong, help: "Root shaders directory (must contain glsl/ and/or masks/ subdirs)")
    var shadersDir: String = "Shaders"
    
    @Option(name: .shortAndLong, help: "Build directory for intermediate files")
    var buildDir: String = "Build/Shaders"
    
    @Option(name: .shortAndLong, help: "Output metallib file path")
    var output: String = "Sources/SwiftVJApp/Resources/Shaders.metallib"
    
    @Flag(name: .shortAndLong, help: "Show verbose output")
    var verbose: Bool = false
    
    @Flag(name: .long, help: "Clean build directory before compiling")
    var clean: Bool = false
    
    func run() async throws {
        print("Starting shader compilation...")
        
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath
        
        // Resolve paths
        let shadersURL = URL(fileURLWithPath: shadersDir, relativeTo: URL(fileURLWithPath: currentDir))
        let buildURL = URL(fileURLWithPath: buildDir, relativeTo: URL(fileURLWithPath: currentDir))
        let outputURL = URL(fileURLWithPath: output, relativeTo: URL(fileURLWithPath: currentDir))
        
        print("🔧 Shader Compilation")
        print("   Shaders: \(shadersURL.path)")
        print("   Build:   \(buildURL.path)")
        print("   Output:  \(outputURL.path)")
        print()
        
        // Clean if requested
        if clean && fileManager.fileExists(atPath: buildURL.path) {
            try fileManager.removeItem(at: buildURL)
            if verbose { print("   Cleaned build directory") }
        }
        
        // Create build directory
        try fileManager.createDirectory(at: buildURL, withIntermediateDirectories: true)
        
        // Configure compiler
        let config = ShaderCompiler.Config(
            buildDirectory: buildURL,
            shadersDirectory: shadersURL,
            metallibName: outputURL.lastPathComponent,
            outputDirectory: outputURL.deletingLastPathComponent()
        )
        
        // Compile
        let result = try await ShaderCompiler.compileAll(config: config)
        
        // Print results
        ShaderCompiler.printReport(result)
        
        // Exit with error only if metallib wasn't created
        if !result.success {
            throw ExitCode.failure
        }
        
        print("✅ Done!")
    }
}

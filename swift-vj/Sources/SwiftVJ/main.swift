// SwiftVJ CLI - Command-line entry point
// Each module supports standalone execution for testing

import ArgumentParser
import SwiftVJCore
import ShaderRepository
import Foundation
import Metal

@main
struct SwiftVJCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-vj",
        abstract: "Swift VJ Control Application",
        version: swiftVJVersion,
        subcommands: [
            LyricsCommand.self,
            LaunchpadTestCommand.self,
            LaunchpadE2ECommand.self,
            RuntimeShaderCommand.self,
            // PipelineCommand.self,  // TODO: Implement
            // PlaybackCommand.self,  // TODO: Implement
            // ShadersCommand.self,   // TODO: Implement
        ],
        defaultSubcommand: nil
    )
}

// MARK: - Lyrics Command

struct LyricsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lyrics",
        abstract: "Fetch and parse lyrics for a song"
    )

    @Option(name: [.short, .long], help: "Artist name")
    var artist: String

    @Option(name: [.short, .long], help: "Song title")
    var title: String

    @Option(name: .long, help: "Album name (optional)")
    var album: String = ""

    @Flag(name: .long, help: "Show detailed line-by-line output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Parse local LRC file instead of fetching")
    var local: Bool = false

    func run() async throws {
        print("SwiftVJ Lyrics Module")
        print(String(repeating: "=", count: 60))
        print("Artist: \(artist)")
        print("Title: \(title)")
        if !album.isEmpty {
            print("Album: \(album)")
        }
        print()

        if local {
            // Demo: parse sample LRC
            let sampleLRC = """
            [00:05.12]Is this the real life
            [00:08.34]Is this just fantasy
            [00:11.56]Caught in a landslide
            [00:14.78]No escape from reality
            [00:18.00]Open your eyes
            [00:21.22]Look up to the skies and see
            """

            let lines = parseLRC(sampleLRC)
            let analyzed = analyzeLyrics(lines)

            print("Parsed \(analyzed.count) lines")
            print()

            for (index, line) in analyzed.enumerated() {
                let refrain = line.isRefrain ? " [REFRAIN]" : ""
                let keywords = line.keywords.isEmpty ? "" : " (\(line.keywords))"
                if verbose {
                    print(String(format: "%3d | %6.2f | %@%@%@",
                                index, line.timeSec, line.text, refrain, keywords))
                } else {
                    print("[\(String(format: "%02d:%05.2f", Int(line.timeSec) / 60, line.timeSec.truncatingRemainder(dividingBy: 60)))] \(line.text)\(refrain)")
                }
            }

            print()
            print("Refrains: \(analyzed.filter { $0.isRefrain }.count) lines")
        } else {
            print("TODO: Implement LRCLIB fetch")
            print("Use --local to demo LRC parsing with sample data")
        }
    }
}

// MARK: - Launchpad Test Command

struct LaunchpadTestCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launchpad-test",
        abstract: "Interactive hardware tests for Launchpad Mini MK3"
    )
    
    @Argument(help: "Test number (1-8) or 'all'")
    var test: String?
    
    func run() throws {
        print()
        print("🎹 LAUNCHPAD MINI MK3 - INTERACTIVE TESTS")
        print(String(repeating: "=", count: 50))
        print()
        print("Make sure Launchpad is connected and in PROGRAMMER mode:")
        print("  → Hold Session → Press orange button → Release")
        print()
        
        let testNumber: Int?
        if let t = test {
            if t.lowercased() == "all" {
                testNumber = nil  // Will run menu which has 'all' option
            } else if let num = Int(t), num >= 1, num <= 8 {
                testNumber = num
            } else {
                print("Invalid test: \(t)")
                print("Use 1-8 or 'all'")
                return
            }
        } else {
            testNumber = nil
        }
        
        runLaunchpadInteractiveTests(testNumber: testNumber)
    }
}

// MARK: - Launchpad E2E Command

struct LaunchpadE2ECommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launchpad-e2e",
        abstract: "End-to-end guided test for all Launchpad features"
    )
    
    func run() async throws {
        await runLaunchpadE2ETest()
    }
}

// MARK: - Runtime Shader Command (PoC)

struct RuntimeShaderCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runtime-shader",
        abstract: "Compile a GLSL shader at runtime (no Xcode/metallib needed)"
    )

    @Option(name: [.short, .long], help: "Path to GLSL shader file (.txt)")
    var file: String

    @Flag(name: .long, help: "Show generated MSL source")
    var showMSL: Bool = false

    func run() async throws {
        print()
        print("⚡ RUNTIME SHADER COMPILATION")
        print(String(repeating: "=", count: 50))

        // Step 1: Read GLSL source
        let fileURL = URL(fileURLWithPath: file)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("❌ File not found: \(file)")
            throw ExitCode.failure
        }
        let glslSource = try String(contentsOf: fileURL, encoding: .utf8)
        let shaderName = fileURL.deletingPathExtension().lastPathComponent
        print("📄 Shader: \(shaderName) (\(glslSource.count) chars)")

        // Step 2: Check tools
        let glslang = ShaderCompiler.findTool("glslangValidator")
        let spirvCross = ShaderCompiler.findTool("spirv-cross")
        print("🔧 glslangValidator: \(glslang)")
        print("🔧 spirv-cross: \(spirvCross)")

        // Step 3: GLSL → MSL
        print()
        print("Step 1: GLSL → SPIR-V → MSL...")
        let result = try await ShaderCompiler.compileToMSL(
            source: glslSource,
            name: shaderName,
            glslangPath: glslang,
            spirvCrossPath: spirvCross
        )

        guard result.success else {
            print("❌ Compilation failed:")
            for error in result.errors {
                print("  \(error)")
            }
            throw ExitCode.failure
        }
        print("✓ MSL generated (\(result.mslSource.count) chars, \(String(format: "%.0f", result.duration * 1000))ms)")
        print("  Fragment function: \(result.fragmentFunctionName)")

        if showMSL {
            print()
            print("--- Generated MSL ---")
            print(result.mslSource)
            print("--- End MSL ---")
        }

        // Step 4: Metal runtime compilation
        print()
        print("Step 2: MSL → Metal library (runtime)...")
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ No Metal device available")
            throw ExitCode.failure
        }
        print("  Device: \(device.name)")

        let library = try await device.makeLibrary(source: result.mslSource, options: nil)
        print("✓ Metal library compiled")
        print("  Functions: \(library.functionNames)")

        // Step 5: Create render pipeline state
        print()
        print("Step 3: Create render pipeline state...")
        guard let fragmentFn = library.makeFunction(name: result.fragmentFunctionName) else {
            print("❌ Fragment function '\(result.fragmentFunctionName)' not found")
            throw ExitCode.failure
        }
        guard let vertexFn = library.makeFunction(name: "vertex_fullscreen") else {
            print("❌ Vertex function 'vertex_fullscreen' not found")
            throw ExitCode.failure
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFn
        descriptor.fragmentFunction = fragmentFn
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        let pipelineState = try await device.makeRenderPipelineState(descriptor: descriptor)

        print("✓ Pipeline state created")
        print()
        print(String(repeating: "=", count: 50))
        print("🎉 SUCCESS — Runtime compilation works!")
        print("   No Xcode, no metallib, no pre-compile step.")
        print("   Pipeline state: \(pipelineState)")
        print()
    }
}

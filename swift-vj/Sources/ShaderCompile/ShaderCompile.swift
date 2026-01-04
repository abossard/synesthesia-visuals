// ShaderCompile.swift - CLI tool for batch shader compilation
// Compiles Shadertoy GLSL shaders to Metal via SPIR-V

import ArgumentParser
import Foundation
import ShadertoyRuntime

@main
struct ShaderCompile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shader-compile",
        abstract: "Compile Shadertoy GLSL shaders to Metal",
        version: "1.0.0",
        subcommands: [
            CompileCommand.self,
            ValidateCommand.self,
            GenerateMetadataCommand.self,
            ReportCommand.self
        ],
        defaultSubcommand: CompileCommand.self
    )
}

// MARK: - Compile Command

struct CompileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compile",
        abstract: "Compile shaders from a directory"
    )

    @Argument(help: "Path to shader directory or specific shader folder")
    var inputPath: String

    @Option(name: .shortAndLong, help: "Output build directory")
    var output: String = "./Build"

    @Option(name: .long, help: "Path to glslangValidator")
    var glslang: String = "/usr/local/bin/glslangValidator"

    @Option(name: .long, help: "Path to spirv-cross")
    var spirvCross: String = "/usr/local/bin/spirv-cross"

    @Option(name: .shortAndLong, help: "Maximum parallel compilation tasks")
    var parallel: Int = 8

    @Flag(name: .long, help: "Generate detailed reports")
    var report: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputURL = URL(fileURLWithPath: output)

        print("Shadertoy Shader Compiler v1.0.0")
        print("================================")
        print("Input:  \(inputURL.path)")
        print("Output: \(outputURL.path)")
        print("")

        // Create output directory
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        // Create compilation pipeline
        let pipeline = ShaderCompilationPipeline(
            glslangPath: glslang,
            spirvCrossPath: spirvCross,
            buildDirectory: outputURL,
            parallelCompilation: parallel > 1,
            maxParallelTasks: parallel
        )

        // Check if input is a single shader or directory
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
            print("Error: Input path does not exist: \(inputURL.path)")
            throw ExitCode.failure
        }

        let startTime = Date()

        if isDirectory.boolValue {
            // Check if it's a shader folder or a directory of shaders
            let hasImageGLSL = FileManager.default.fileExists(atPath: inputURL.appendingPathComponent("image.glsl").path)
            let hasShaderJSON = FileManager.default.fileExists(atPath: inputURL.appendingPathComponent("shader.json").path)

            if hasImageGLSL || hasShaderJSON {
                // Single shader folder
                print("Compiling single shader: \(inputURL.lastPathComponent)")
                let folder = try ShaderFolder(url: inputURL)
                let result = try await pipeline.compile(shaderFolder: folder)
                printResult(result, verbose: verbose)

                if report {
                    try writeReport(for: [result], outputDir: outputURL)
                }
            } else {
                // Directory of shaders
                print("Scanning for shaders...")
                let results = try await pipeline.compileAll(shadersDirectory: inputURL)

                print("\nCompilation Results:")
                print("-------------------")

                var successCount = 0
                var failCount = 0

                for result in results {
                    if result.success {
                        successCount += 1
                        if verbose {
                            printResult(result, verbose: verbose)
                        }
                    } else {
                        failCount += 1
                        printResult(result, verbose: true)  // Always show failures
                    }
                }

                let totalTime = Date().timeIntervalSince(startTime)

                print("\nSummary:")
                print("--------")
                print("Total shaders: \(results.count)")
                print("Successful:    \(successCount)")
                print("Failed:        \(failCount)")
                print("Total time:    \(String(format: "%.2f", totalTime))s")

                if report {
                    try writeReport(for: results, outputDir: outputURL)
                }

                if failCount > 0 {
                    throw ExitCode.failure
                }
            }
        } else {
            print("Error: Input must be a directory")
            throw ExitCode.failure
        }

        print("\nDone!")
    }

    private func printResult(_ result: ShaderCompilationResult, verbose: Bool) {
        let status = result.success ? "OK" : "FAILED"
        print("[\(status)] \(result.shaderName) (\(String(format: "%.2f", result.totalDuration))s)")

        if verbose || !result.success {
            for pass in result.passes {
                let passStatus = pass.success ? "ok" : "error"
                print("  - \(pass.passName.rawValue): \(passStatus)")

                for error in pass.allErrors {
                    print("    ! \(error)")
                }
            }
        }
    }

    private func writeReport(for results: [ShaderCompilationResult], outputDir: URL) throws {
        // Create diagnostic reports
        let shaderReports = results.map { result -> ShaderDiagnosticReport in
            let passReports = result.passes.map { pass -> PassDiagnosticReport in
                PassDiagnosticReport(
                    passName: pass.passName.rawValue,
                    wrapperDiagnostics: pass.wrapperGeneration.errors.map {
                        Diagnostic(severity: .error, message: $0)
                    },
                    glslangDiagnostics: DiagnosticParser.parseGlslang(
                        output: pass.spirvCompilation.errors.joined(separator: "\n"),
                        file: pass.passName.rawValue + ".glsl"
                    ),
                    spirvCrossDiagnostics: DiagnosticParser.parseSpirvCross(
                        output: pass.mslConversion.errors.joined(separator: "\n"),
                        file: pass.passName.rawValue + ".spv"
                    ),
                    metalDiagnostics: [],
                    mitigationsApplied: []
                )
            }

            return ShaderDiagnosticReport(
                shaderName: result.shaderName,
                shaderPath: result.shaderPath.path,
                passes: passReports,
                compilationTime: result.totalDuration,
                timestamp: Date()
            )
        }

        let batch = BatchDiagnosticReport(
            shaders: shaderReports,
            totalTime: results.reduce(0) { $0 + $1.totalDuration }
        )

        // Write JSON report
        let jsonPath = outputDir.appendingPathComponent("compilation_report.json")
        let jsonData = try JSONEncoder().encode(batch)
        try jsonData.write(to: jsonPath)
        print("JSON report: \(jsonPath.path)")

        // Write HTML report
        let htmlPath = outputDir.appendingPathComponent("compilation_report.html")
        var htmlContent = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Shader Compilation Report</title>
            <style>
                body { font-family: system-ui; margin: 20px; }
                .summary { background: #f0f0f0; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
                .shader { margin: 10px 0; padding: 10px; border: 1px solid #ddd; border-radius: 4px; }
                .shader.success { background: #f0fff0; }
                .shader.failed { background: #fff0f0; }
                .error { color: #d00; margin-left: 20px; }
            </style>
        </head>
        <body>
            <h1>Shader Compilation Report</h1>
            <div class="summary">
                <p><strong>Total:</strong> \(batch.totalShaders) shaders</p>
                <p><strong>Success:</strong> \(batch.successCount)</p>
                <p><strong>Failed:</strong> \(batch.failedCount)</p>
                <p><strong>Success Rate:</strong> \(String(format: "%.1f", batch.successRate))%</p>
                <p><strong>Total Time:</strong> \(String(format: "%.2f", batch.totalTime))s</p>
            </div>
        """

        for shader in shaderReports {
            let cssClass = shader.success ? "success" : "failed"
            htmlContent += """
            <div class="shader \(cssClass)">
                <strong>\(shader.shaderName)</strong>
                [\(shader.success ? "OK" : "FAILED")]
                (\(String(format: "%.2f", shader.compilationTime))s)
            """

            for pass in shader.passes where pass.hasErrors {
                htmlContent += "<div class=\"error\">"
                for diag in pass.glslangDiagnostics + pass.spirvCrossDiagnostics {
                    htmlContent += "<p>\(diag.message)</p>"
                }
                htmlContent += "</div>"
            }

            htmlContent += "</div>"
        }

        htmlContent += "</body></html>"

        try htmlContent.write(to: htmlPath, atomically: true, encoding: .utf8)
        print("HTML report: \(htmlPath.path)")
    }
}

// MARK: - Validate Command

struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate shader.json files without compiling"
    )

    @Argument(help: "Path to shader directory")
    var inputPath: String

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: inputPath)

        print("Validating shader metadata...")

        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: [.isDirectoryKey])

        var validCount = 0
        var invalidCount = 0

        for url in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            do {
                let folder = try ShaderFolder(url: url)
                print("[OK] \(folder.name)")

                if let global = folder.metadata.global {
                    if let name = global.name {
                        print("     Name: \(name)")
                    }
                    if let author = global.author {
                        print("     Author: \(author)")
                    }
                }

                print("     Passes: \(folder.metadata.passes.map { $0.name.rawValue }.joined(separator: ", "))")
                validCount += 1
            } catch {
                print("[INVALID] \(url.lastPathComponent): \(error)")
                invalidCount += 1
            }
        }

        print("\nSummary: \(validCount) valid, \(invalidCount) invalid")
    }
}

// MARK: - Generate Metadata Command

struct GenerateMetadataCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-metadata",
        abstract: "Generate default shader.json files for shaders missing them"
    )

    @Argument(help: "Path to shader directory")
    var inputPath: String

    @Flag(name: .long, help: "Overwrite existing shader.json files")
    var overwrite: Bool = false

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        let fm = FileManager.default

        print("Generating shader metadata...")

        let contents = try fm.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: [.isDirectoryKey])

        var generatedCount = 0
        var skippedCount = 0

        for url in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let metadataPath = url.appendingPathComponent("shader.json")
            let hasMetadata = fm.fileExists(atPath: metadataPath.path)

            if hasMetadata && !overwrite {
                skippedCount += 1
                continue
            }

            // Try to create folder and extract metadata
            do {
                let folder = try ShaderFolder(url: url)

                // Write metadata
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(folder.metadata)
                try data.write(to: metadataPath)

                print("[GENERATED] \(url.lastPathComponent)")
                generatedCount += 1
            } catch {
                print("[SKIPPED] \(url.lastPathComponent): \(error)")
                skippedCount += 1
            }
        }

        print("\nGenerated: \(generatedCount), Skipped: \(skippedCount)")
    }
}

// MARK: - Report Command

struct ReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Generate a report of all shaders in a directory"
    )

    @Argument(help: "Path to shader directory")
    var inputPath: String

    @Option(name: .shortAndLong, help: "Output format (text, json, html)")
    var format: String = "text"

    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: inputPath)
        let fm = FileManager.default

        let contents = try fm.contentsOfDirectory(at: inputURL, includingPropertiesForKeys: [.isDirectoryKey])

        var shaders: [(name: String, passes: [String], multiPass: Bool, hasFeedback: Bool)] = []

        for url in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            do {
                let folder = try ShaderFolder(url: url)
                let passes = folder.metadata.passes.map { $0.name.rawValue }
                let multiPass = folder.metadata.isMultiPass
                let hasFeedback = folder.metadata.passes.contains { $0.requiresPingPong }

                shaders.append((folder.name, passes, multiPass, hasFeedback))
            } catch {
                continue
            }
        }

        shaders.sort { $0.name < $1.name }

        switch format {
        case "json":
            let data = try JSONSerialization.data(withJSONObject: shaders.map {
                ["name": $0.name, "passes": $0.passes, "multiPass": $0.multiPass, "feedback": $0.hasFeedback]
            }, options: .prettyPrinted)
            print(String(data: data, encoding: .utf8) ?? "")

        case "html":
            print("""
            <!DOCTYPE html>
            <html>
            <head><title>Shader Report</title></head>
            <body>
            <h1>Shader Report (\(shaders.count) shaders)</h1>
            <table border="1">
            <tr><th>Name</th><th>Passes</th><th>Multi-Pass</th><th>Feedback</th></tr>
            """)
            for shader in shaders {
                print("<tr><td>\(shader.name)</td><td>\(shader.passes.joined(separator: ", "))</td><td>\(shader.multiPass)</td><td>\(shader.hasFeedback)</td></tr>")
            }
            print("</table></body></html>")

        default:
            print("Shader Report")
            print("=============")
            print("Total: \(shaders.count) shaders")
            print("")

            let multiPassCount = shaders.filter { $0.multiPass }.count
            let feedbackCount = shaders.filter { $0.hasFeedback }.count

            print("Single-pass: \(shaders.count - multiPassCount)")
            print("Multi-pass:  \(multiPassCount)")
            print("Feedback:    \(feedbackCount)")
            print("")

            for shader in shaders {
                var flags = ""
                if shader.multiPass { flags += " [multi]" }
                if shader.hasFeedback { flags += " [feedback]" }
                print("\(shader.name)\(flags)")
                print("  Passes: \(shader.passes.joined(separator: " -> "))")
            }
        }
    }
}

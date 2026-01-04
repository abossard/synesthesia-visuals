// ShaderDiagnostics.swift - Robustness and error reporting for shader compilation
// Provides detailed reports and automatic mitigations for common issues

import Foundation

// MARK: - Diagnostic Types

/// Severity level for diagnostic messages
public enum DiagnosticSeverity: String, Codable, Sendable {
    case error = "error"
    case warning = "warning"
    case info = "info"
    case hint = "hint"
}

/// A single diagnostic message
public struct Diagnostic: Codable, Sendable, Identifiable {
    public let id: UUID
    public let severity: DiagnosticSeverity
    public let message: String
    public let file: String?
    public let line: Int?
    public let column: Int?
    public let code: String?
    public let suggestion: String?

    public init(
        severity: DiagnosticSeverity,
        message: String,
        file: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        code: String? = nil,
        suggestion: String? = nil
    ) {
        self.id = UUID()
        self.severity = severity
        self.message = message
        self.file = file
        self.line = line
        self.column = column
        self.code = code
        self.suggestion = suggestion
    }
}

/// Compilation report for a single pass
public struct PassDiagnosticReport: Codable, Sendable {
    public let passName: String
    public let wrapperDiagnostics: [Diagnostic]
    public let glslangDiagnostics: [Diagnostic]
    public let spirvCrossDiagnostics: [Diagnostic]
    public let metalDiagnostics: [Diagnostic]
    public let mitigationsApplied: [String]

    public var hasErrors: Bool {
        let allDiagnostics = wrapperDiagnostics + glslangDiagnostics + spirvCrossDiagnostics + metalDiagnostics
        return allDiagnostics.contains { $0.severity == .error }
    }

    public var errorCount: Int {
        let allDiagnostics = wrapperDiagnostics + glslangDiagnostics + spirvCrossDiagnostics + metalDiagnostics
        return allDiagnostics.filter { $0.severity == .error }.count
    }

    public var warningCount: Int {
        let allDiagnostics = wrapperDiagnostics + glslangDiagnostics + spirvCrossDiagnostics + metalDiagnostics
        return allDiagnostics.filter { $0.severity == .warning }.count
    }
}

/// Complete diagnostic report for a shader
public struct ShaderDiagnosticReport: Codable, Sendable {
    public let shaderName: String
    public let shaderPath: String
    public let passes: [PassDiagnosticReport]
    public let compilationTime: TimeInterval
    public let timestamp: Date

    public var success: Bool {
        !passes.contains { $0.hasErrors }
    }

    public var totalErrors: Int {
        passes.reduce(0) { $0 + $1.errorCount }
    }

    public var totalWarnings: Int {
        passes.reduce(0) { $0 + $1.warningCount }
    }
}

// MARK: - Diagnostic Parser

/// Parses compiler output into structured diagnostics
public struct DiagnosticParser {

    /// Parse glslangValidator output
    public static func parseGlslang(output: String, file: String) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        // Pattern: ERROR: file:line: message
        // Pattern: WARNING: file:line: message
        let pattern = "(ERROR|WARNING):\\s*([^:]+):(\\d+):\\s*(.+)"

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: output, options: [], range: NSRange(output.startIndex..., in: output))

            for match in matches {
                guard match.numberOfRanges >= 5 else { continue }

                let severityRange = Range(match.range(at: 1), in: output)!
                let lineRange = Range(match.range(at: 3), in: output)!
                let messageRange = Range(match.range(at: 4), in: output)!

                let severityStr = String(output[severityRange]).lowercased()
                let severity: DiagnosticSeverity = severityStr.contains("error") ? .error : .warning
                let line = Int(output[lineRange])
                let message = String(output[messageRange]).trimmingCharacters(in: .whitespaces)

                let suggestion = suggestFix(for: message)

                diagnostics.append(Diagnostic(
                    severity: severity,
                    message: message,
                    file: file,
                    line: line,
                    suggestion: suggestion
                ))
            }
        }

        return diagnostics
    }

    /// Parse spirv-cross output
    public static func parseSpirvCross(output: String, file: String) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        // SPIRV-Cross errors are usually plain text
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.lowercased().contains("error") {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    message: trimmed,
                    file: file
                ))
            } else if trimmed.lowercased().contains("warning") {
                diagnostics.append(Diagnostic(
                    severity: .warning,
                    message: trimmed,
                    file: file
                ))
            }
        }

        return diagnostics
    }

    /// Parse Metal compiler output
    public static func parseMetal(output: String, file: String) -> [Diagnostic] {
        var diagnostics: [Diagnostic] = []

        // Pattern: file:line:column: error/warning: message
        let pattern = "([^:]+):(\\d+):(\\d+):\\s*(error|warning):\\s*(.+)"

        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: output, options: [], range: NSRange(output.startIndex..., in: output))

            for match in matches {
                guard match.numberOfRanges >= 6 else { continue }

                let lineRange = Range(match.range(at: 2), in: output)!
                let columnRange = Range(match.range(at: 3), in: output)!
                let severityRange = Range(match.range(at: 4), in: output)!
                let messageRange = Range(match.range(at: 5), in: output)!

                let line = Int(output[lineRange])
                let column = Int(output[columnRange])
                let severityStr = String(output[severityRange]).lowercased()
                let severity: DiagnosticSeverity = severityStr == "error" ? .error : .warning
                let message = String(output[messageRange])

                diagnostics.append(Diagnostic(
                    severity: severity,
                    message: message,
                    file: file,
                    line: line,
                    column: column
                ))
            }
        }

        return diagnostics
    }

    /// Suggest fixes for common errors
    private static func suggestFix(for message: String) -> String? {
        let lowered = message.lowercased()

        if lowered.contains("undeclared identifier") {
            if lowered.contains("texture2d") {
                return "Add '#define texture2D texture' to compatibility shim"
            }
            if lowered.contains("iglobaltime") {
                return "Add '#define iGlobalTime iTime' to compatibility shim"
            }
        }

        if lowered.contains("precision") {
            return "Add precision qualifiers for GLSL ES compatibility"
        }

        if lowered.contains("gl_fragcolor") {
            return "Use output variable 'fragColor' instead of gl_FragColor"
        }

        if lowered.contains("mainimage") && lowered.contains("undefined") {
            return "Ensure mainImage function is defined with correct signature: void mainImage(out vec4, in vec2)"
        }

        return nil
    }
}

// MARK: - Automatic Mitigations

/// Applies automatic fixes for common Shadertoy GLSL issues
public struct ShaderMitigations {

    /// Common mitigation types
    public enum MitigationType: String, Codable, Sendable {
        case precisionQualifiers = "precision_qualifiers"
        case texture2DAlias = "texture2d_alias"
        case iGlobalTimeAlias = "iglobaltime_alias"
        case glFragColorReplace = "gl_fragcolor_replace"
        case mainImageWrapper = "mainimage_wrapper"
        case missingVersion = "missing_version"
    }

    /// Apply all applicable mitigations to source
    public static func applyMitigations(to source: String, compatibilityMode: Bool = true) -> (source: String, applied: [MitigationType]) {
        var result = source
        var applied: [MitigationType] = []

        // Add version if missing
        if !source.contains("#version") {
            result = "#version 450\n\n" + result
            applied.append(.missingVersion)
        }

        // Add precision qualifiers for GLSL ES
        if !source.contains("precision ") && source.contains("#ifdef GL_ES") {
            let precisionBlock = """
            #ifdef GL_ES
            precision highp float;
            precision highp int;
            #endif

            """
            // Insert after #version
            if let versionEnd = result.range(of: "\n", options: [], range: result.range(of: "#version")?.upperBound..<result.endIndex) {
                result.insert(contentsOf: "\n" + precisionBlock, at: versionEnd.lowerBound)
                applied.append(.precisionQualifiers)
            }
        }

        if compatibilityMode {
            // texture2D -> texture alias
            if source.contains("texture2D") && !source.contains("#define texture2D") {
                applied.append(.texture2DAlias)
            }

            // iGlobalTime -> iTime alias
            if source.contains("iGlobalTime") && !source.contains("#define iGlobalTime") {
                applied.append(.iGlobalTimeAlias)
            }

            // gl_FragColor handling
            if source.contains("gl_FragColor") {
                applied.append(.glFragColorReplace)
            }

            // mainImage wrapper
            if !source.contains("void main") && source.contains("mainImage") {
                applied.append(.mainImageWrapper)
            }
        }

        return (result, applied)
    }

    /// Generate compatibility defines based on detected issues
    public static func generateCompatibilityDefines(for mitigations: [MitigationType]) -> String {
        var defines = "// Compatibility defines\n"

        for mitigation in mitigations {
            switch mitigation {
            case .texture2DAlias:
                defines += "#define texture2D texture\n"
                defines += "#define textureCube texture\n"
            case .iGlobalTimeAlias:
                defines += "#define iGlobalTime iTime\n"
            case .glFragColorReplace:
                defines += "#define gl_FragColor fragColor\n"
            case .precisionQualifiers:
                defines += "#ifdef GL_ES\n"
                defines += "precision highp float;\n"
                defines += "precision highp int;\n"
                defines += "#endif\n"
            default:
                break
            }
        }

        return defines
    }
}

// MARK: - Report Generator

/// Generates human-readable and machine-readable reports
public struct ReportGenerator {

    /// Generate a text summary report
    public static func generateTextReport(_ report: ShaderDiagnosticReport) -> String {
        var output = """
        ================================================================================
        Shader Compilation Report: \(report.shaderName)
        ================================================================================
        Path: \(report.shaderPath)
        Time: \(String(format: "%.2f", report.compilationTime))s
        Status: \(report.success ? "SUCCESS" : "FAILED")
        Errors: \(report.totalErrors)  Warnings: \(report.totalWarnings)
        ================================================================================

        """

        for pass in report.passes {
            output += "\n--- Pass: \(pass.passName) ---\n"

            if pass.hasErrors {
                output += "Status: FAILED\n"
            } else {
                output += "Status: OK\n"
            }

            if !pass.mitigationsApplied.isEmpty {
                output += "Mitigations: \(pass.mitigationsApplied.joined(separator: ", "))\n"
            }

            let allDiagnostics = pass.wrapperDiagnostics + pass.glslangDiagnostics + pass.spirvCrossDiagnostics + pass.metalDiagnostics

            for diagnostic in allDiagnostics {
                let location = [diagnostic.file, diagnostic.line.map(String.init), diagnostic.column.map(String.init)]
                    .compactMap { $0 }
                    .joined(separator: ":")

                output += "[\(diagnostic.severity.rawValue.uppercased())] "
                if !location.isEmpty {
                    output += "\(location): "
                }
                output += "\(diagnostic.message)\n"

                if let suggestion = diagnostic.suggestion {
                    output += "  Suggestion: \(suggestion)\n"
                }
            }
        }

        return output
    }

    /// Generate JSON report
    public static func generateJSONReport(_ report: ShaderDiagnosticReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(report)
    }

    /// Generate HTML report
    public static func generateHTMLReport(_ report: ShaderDiagnosticReport) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Shader Report: \(report.shaderName)</title>
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; margin: 20px; }
                .header { background: #f0f0f0; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
                .pass { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 8px; }
                .pass.error { border-color: #ff6b6b; background: #fff5f5; }
                .pass.success { border-color: #51cf66; background: #f8fff8; }
                .diagnostic { margin: 5px 0; padding: 8px; border-radius: 4px; }
                .diagnostic.error { background: #ffe0e0; }
                .diagnostic.warning { background: #fff3cd; }
                .diagnostic.info { background: #e7f5ff; }
                .suggestion { color: #228be6; font-style: italic; margin-left: 20px; }
                .stats { display: flex; gap: 20px; }
                .stat { background: #e9ecef; padding: 10px 15px; border-radius: 4px; }
            </style>
        </head>
        <body>
            <div class="header">
                <h1>\(report.shaderName)</h1>
                <p><strong>Path:</strong> \(report.shaderPath)</p>
                <div class="stats">
                    <div class="stat">Time: \(String(format: "%.2f", report.compilationTime))s</div>
                    <div class="stat">Errors: \(report.totalErrors)</div>
                    <div class="stat">Warnings: \(report.totalWarnings)</div>
                    <div class="stat">Status: \(report.success ? "SUCCESS" : "FAILED")</div>
                </div>
            </div>
        """

        for pass in report.passes {
            let passClass = pass.hasErrors ? "error" : "success"
            html += """
            <div class="pass \(passClass)">
                <h2>\(pass.passName)</h2>
            """

            if !pass.mitigationsApplied.isEmpty {
                html += "<p><strong>Mitigations:</strong> \(pass.mitigationsApplied.joined(separator: ", "))</p>"
            }

            let allDiagnostics = pass.wrapperDiagnostics + pass.glslangDiagnostics + pass.spirvCrossDiagnostics + pass.metalDiagnostics

            for diagnostic in allDiagnostics {
                html += """
                <div class="diagnostic \(diagnostic.severity.rawValue)">
                    <strong>[\(diagnostic.severity.rawValue.uppercased())]</strong>
                """

                if let file = diagnostic.file, let line = diagnostic.line {
                    html += " \(file):\(line)"
                    if let col = diagnostic.column {
                        html += ":\(col)"
                    }
                }

                html += " \(diagnostic.message)"

                if let suggestion = diagnostic.suggestion {
                    html += "<div class=\"suggestion\">Suggestion: \(suggestion)</div>"
                }

                html += "</div>"
            }

            html += "</div>"
        }

        html += """
        </body>
        </html>
        """

        return html
    }
}

// MARK: - Batch Report

/// Aggregated report for multiple shaders
public struct BatchDiagnosticReport: Codable, Sendable {
    public let totalShaders: Int
    public let successCount: Int
    public let failedCount: Int
    public let totalErrors: Int
    public let totalWarnings: Int
    public let totalTime: TimeInterval
    public let shaders: [ShaderDiagnosticReport]

    public init(shaders: [ShaderDiagnosticReport], totalTime: TimeInterval) {
        self.shaders = shaders
        self.totalShaders = shaders.count
        self.successCount = shaders.filter { $0.success }.count
        self.failedCount = shaders.filter { !$0.success }.count
        self.totalErrors = shaders.reduce(0) { $0 + $1.totalErrors }
        self.totalWarnings = shaders.reduce(0) { $0 + $1.totalWarnings }
        self.totalTime = totalTime
    }

    public var successRate: Double {
        guard totalShaders > 0 else { return 0 }
        return Double(successCount) / Double(totalShaders) * 100
    }
}

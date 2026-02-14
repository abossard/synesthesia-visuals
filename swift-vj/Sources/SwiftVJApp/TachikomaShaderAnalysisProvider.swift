import Foundation
import SwiftVJCore

actor TachikomaShaderAnalysisProvider: ShaderAnalysisProvider {
    private let llmClient: LLMClient
    private let logger: @Sendable (String, LogLevel) -> Void

    init(
        llmClient: LLMClient = LLMClient(),
        logger: @escaping @Sendable (String, LogLevel) -> Void
    ) {
        self.llmClient = llmClient
        self.logger = logger
    }

    nonisolated var providerName: String { "Tachikoma" }

    func isAvailable() async -> Bool {
        await llmClient.start()
        let available = await llmClient.isAvailable
        if available {
            let backend = await llmClient.backendInfo
            logger("  ✓ Tachikoma backend ready: \(backend)", .info)
        }
        return available
    }

    func analyzeShader(
        shaderName: String,
        shaderSource: String,
        screenshotPath: URL?
    ) async -> ShaderAnalysisResult? {
        let screenshotData: Data?
        if let screenshotPath {
            screenshotData = try? Data(contentsOf: screenshotPath)
            if screenshotData == nil {
                logger("  ⚠️ Could not read screenshot for \(shaderName)", .warning)
            }
        } else {
            screenshotData = nil
        }

        let analysis = await llmClient.analyzeShader(
            shaderName: shaderName,
            shaderSource: shaderSource,
            screenshotData: screenshotData
        )

        if let error = analysis.error {
            logger("  ✗ Tachikoma shader analysis failed: \(error)", .error)
            return nil
        }

        return ShaderAnalysisResult(
            title: analysis.title.isEmpty ? shaderName : analysis.title,
            description: analysis.description,
            mood: analysis.mood,
            energy: analysis.energy,
            colors: analysis.colors,
            effects: analysis.effects,
            geometry: analysis.geometry,
            objects: analysis.objects,
            complexity: analysis.complexity,
            visualMetadata: analysis.visualMetadata,
            djPhases: analysis.djPhases.isEmpty ? nil : analysis.djPhases
        )
    }
}

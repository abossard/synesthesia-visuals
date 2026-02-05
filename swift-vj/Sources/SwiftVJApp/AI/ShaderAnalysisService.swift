// ShaderAnalysisService.swift - Facade for shader AI providers

import Foundation

protocol ShaderAnalysisProvider: Sendable {
    var providerName: String { get }
    func isAvailable() async -> Bool
    func analyzeShader(shaderName: String, shaderSource: String, screenshotPath: URL?) async -> ShaderAnalysisResult?
}

actor ShaderAnalysisService {
    private let providers: [any ShaderAnalysisProvider]
    private let logger: @Sendable (String, LogLevel) -> Void
    private var activeProviderIndex: Int?

    init(
        providers: [any ShaderAnalysisProvider],
        logger: @escaping @Sendable (String, LogLevel) -> Void
    ) {
        self.providers = providers
        self.logger = logger
    }

    func isAvailable() async -> Bool {
        return await resolveProvider() != nil
    }

    func activeProviderName() async -> String? {
        guard let provider = await resolveProvider() else { return nil }
        return provider.providerName
    }

    func analyzeShader(
        shaderName: String,
        shaderSource: String,
        screenshotPath: URL?
    ) async -> ShaderAnalysisResult? {
        guard let provider = await resolveProvider() else { return nil }
        return await provider.analyzeShader(
            shaderName: shaderName,
            shaderSource: shaderSource,
            screenshotPath: screenshotPath
        )
    }

    private func resolveProvider() async -> (any ShaderAnalysisProvider)? {
        if let index = activeProviderIndex, index < providers.count {
            let provider = providers[index]
            if await provider.isAvailable() {
                return provider
            }
            activeProviderIndex = nil
        }

        for (index, provider) in providers.enumerated() {
            if await provider.isAvailable() {
                if activeProviderIndex != index {
                    logger("  ✓ AI provider selected: \(provider.providerName)", .info)
                }
                activeProviderIndex = index
                return provider
            }
        }

        activeProviderIndex = nil
        return nil
    }
}

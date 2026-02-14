import Foundation
import Tachikoma

public enum TachikomaProviderKind: String, Codable, Sendable, CaseIterable {
    case lmstudio
    case openai
    case anthropic
    case azureOpenAI = "azure_openai"
    case ollama
}

public struct TachikomaProviderConfig: Codable, Equatable, Sendable {
    public var provider: TachikomaProviderKind
    public var model: String
    public var baseURL: String?
    public var apiKey: String?
    public var azureResource: String?
    public var azureEndpoint: String?
    public var azureAPIVersion: String?

    public init(
        provider: TachikomaProviderKind,
        model: String,
        baseURL: String? = nil,
        apiKey: String? = nil,
        azureResource: String? = nil,
        azureEndpoint: String? = nil,
        azureAPIVersion: String? = nil
    ) {
        self.provider = provider
        self.model = model
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.azureResource = azureResource
        self.azureEndpoint = azureEndpoint
        self.azureAPIVersion = azureAPIVersion
    }

    public static let localLMStudio = TachikomaProviderConfig(
        provider: .lmstudio,
        model: "current",
        baseURL: "http://localhost:1234/v1"
    )
}

public struct TachikomaLLMRuntimeConfig: Codable, Equatable, Sendable {
    public var songAnalysis: TachikomaProviderConfig
    public var shaderAnalysis: TachikomaProviderConfig

    public init(
        songAnalysis: TachikomaProviderConfig = .localLMStudio,
        shaderAnalysis: TachikomaProviderConfig = .localLMStudio
    ) {
        self.songAnalysis = songAnalysis
        self.shaderAnalysis = shaderAnalysis
    }

    public static let `default` = TachikomaLLMRuntimeConfig()

    public static func load(from fileURL: URL?) -> TachikomaLLMRuntimeConfig? {
        guard let fileURL else {
            return nil
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? JSONDecoder().decode(TachikomaLLMRuntimeConfig.self, from: data)
    }

    public func makeTachikomaConfiguration(loadFromEnvironment: Bool = true) -> TachikomaConfiguration {
        let configuration = TachikomaConfiguration(loadFromEnvironment: loadFromEnvironment)
        for provider in [songAnalysis, shaderAnalysis] {
            if let baseURL = provider.baseURL, !baseURL.isEmpty {
                configuration.setBaseURL(baseURL, for: provider.provider.tachikomaProvider)
            }
            if let apiKey = provider.apiKey, !apiKey.isEmpty {
                configuration.setAPIKey(apiKey, for: provider.provider.tachikomaProvider)
            }
        }
        return configuration
    }
}

extension TachikomaProviderConfig {
    var languageModel: LanguageModel {
        switch provider {
        case .lmstudio:
            if model.lowercased() == "current" {
                return .lmstudio(.current)
            }
            return .lmstudio(.custom(model))
        case .openai:
            return .openai(.custom(model))
        case .anthropic:
            return .anthropic(.custom(model))
        case .azureOpenAI:
            return .azureOpenAI(
                deployment: model,
                resource: azureResource,
                apiVersion: azureAPIVersion,
                endpoint: azureEndpoint
            )
        case .ollama:
            return .ollama(.custom(model))
        }
    }

    var displayName: String {
        let providerName = provider.tachikomaProvider.displayName
        return "\(providerName) (\(model))"
    }
}

extension TachikomaProviderKind {
    var tachikomaProvider: Provider {
        switch self {
        case .lmstudio:
            return .lmstudio
        case .openai:
            return .openai
        case .anthropic:
            return .anthropic
        case .azureOpenAI:
            return .azureOpenAI
        case .ollama:
            return .ollama
        }
    }
}

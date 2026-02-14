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

    public static var defaultFileURL: URL {
        Config.dataDirectory.appendingPathComponent("tachikoma.json")
    }

    public static func load(from fileURL: URL? = nil) -> TachikomaLLMRuntimeConfig {
        for url in candidateConfigURLs(explicit: fileURL) {
            guard let data = try? Data(contentsOf: url) else {
                continue
            }
            if let parsed = try? JSONDecoder().decode(TachikomaLLMRuntimeConfig.self, from: data) {
                return parsed
            }
        }
        return .default
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

private extension TachikomaLLMRuntimeConfig {
    static func candidateConfigURLs(explicit: URL?) -> [URL] {
        if let explicit {
            return [explicit]
        }

        var urls: [URL] = []
        let process = ProcessInfo.processInfo

        if let envPath = process.environment["SWIFTVJ_TACHIKOMA_CONFIG"], !envPath.isEmpty {
            urls.append(URL(fileURLWithPath: envPath))
        }

        // When running as app bundle, prioritize sibling tachikoma.json in repo folder.
        // Example: <repo>/Swift VJ.app -> <repo>/tachikoma.json
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            let bundleParent = bundleURL.deletingLastPathComponent()
            urls.append(bundleParent.appendingPathComponent("tachikoma.json"))
            if let root = repositoryRoot(from: bundleParent) {
                urls.append(root.appendingPathComponent("tachikoma.json"))
            }
        }

        if let root = repositoryRoot(from: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
            urls.append(root.appendingPathComponent("tachikoma.json"))
        }

        if let executableURL = Bundle.main.executableURL,
           let root = repositoryRoot(from: executableURL.deletingLastPathComponent()) {
            urls.append(root.appendingPathComponent("tachikoma.json"))
        } else if let executableURL = process.arguments.first.map({ URL(fileURLWithPath: $0) }),
                  let root = repositoryRoot(from: executableURL.deletingLastPathComponent()) {
            urls.append(root.appendingPathComponent("tachikoma.json"))
        }

        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tachikoma.json"))
        urls.append(defaultFileURL)
        return dedup(urls)
    }

    static func repositoryRoot(from start: URL) -> URL? {
        var cursor = start.standardizedFileURL.resolvingSymlinksInPath()
        let fileManager = FileManager.default

        while true {
            if fileManager.fileExists(atPath: cursor.appendingPathComponent("Package.swift").path) {
                return cursor
            }
            if cursor.path == "/" {
                return nil
            }
            let parent = cursor.deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath()
            if parent.path == cursor.path || parent.path.isEmpty {
                return nil
            }
            cursor = parent
        }
    }

    static func dedup(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
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

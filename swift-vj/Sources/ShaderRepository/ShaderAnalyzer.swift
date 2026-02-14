import Foundation
import Tachikoma

public enum ShaderAnalyzer {
    public static func isAvailable(config: LLMServiceConfig = .defaultLocal) async -> Bool {
        let tachikomaConfig = makeTachikomaConfiguration(from: config)
        let provider = config.provider.tachikomaProvider
        if let inlineKey = config.apiKey, !inlineKey.isEmpty {
            return true
        }
        if provider.requiresAPIKey {
            return tachikomaConfig.hasAPIKey(for: provider)
        }
        return true
    }

    public static func analyze(
        shader: Shader,
        shaderSource: String,
        screenshotData: Data?,
        config: LLMServiceConfig = .defaultLocal
    ) async throws -> ShaderAnalysis {
        let prompt = buildPrompt(
            shaderName: shader.name,
            shaderSource: shaderSource,
            hasScreenshot: screenshotData != nil
        )

        let response = try await chatCompletion(
            prompt: prompt,
            imageBase64: screenshotData?.base64EncodedString(),
            config: config
        )

        return try parseAnalysis(from: response)
    }

    public static func analyze(
        shader: Shader,
        config: LLMServiceConfig = .defaultLocal
    ) async throws -> ShaderAnalysis {
        let source = try String(contentsOf: shader.sourceURL, encoding: .utf8)
        let screenshotData = shader.screenshotURL.flatMap { try? Data(contentsOf: $0) }
        return try await analyze(
            shader: shader,
            shaderSource: source,
            screenshotData: screenshotData,
            config: config
        )
    }
}

extension ShaderAnalyzer {
    private static func chatCompletion(
        prompt: String,
        imageBase64: String?,
        config: LLMServiceConfig
    ) async throws -> String {
        let model = config.languageModel
        let tachikomaConfig = makeTachikomaConfiguration(from: config)
        let settings = GenerationSettings(
            maxTokens: config.maxTokens,
            temperature: config.temperature
        )

        if let imageBase64 {
            let image = ModelMessage.ContentPart.ImageContent(data: imageBase64, mimeType: "image/png")
            let messages = [ModelMessage.user(text: prompt, images: [image])]
            let result = try await generateText(
                model: model,
                messages: messages,
                settings: settings,
                timeout: config.timeout,
                configuration: tachikomaConfig
            )
            return result.text
        }

        let result = try await generateText(
            model: model,
            messages: [.user(prompt)],
            settings: settings,
            timeout: config.timeout,
            configuration: tachikomaConfig
        )
        return result.text
    }

    private static func parseAnalysis(from content: String) throws -> ShaderAnalysis {
        guard let jsonStart = content.firstIndex(of: "{"),
              let jsonEnd = content.lastIndex(of: "}") else {
            throw AnalyzerError.parseError("No JSON found in response")
        }

        let jsonString = String(content[jsonStart...jsonEnd])
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw AnalyzerError.parseError("Could not convert JSON to data")
        }
        return try JSONDecoder().decode(ShaderAnalysis.self, from: jsonData)
    }

    static let analysisPrompt = """
        Analyze this GLSL shader for VJ music visualization matching.

        Shader name: %SHADER_NAME%

        GLSL source code (first 2000 chars):
        %SHADER_SOURCE%

        %SCREENSHOT_NOTE%

        Provide a JSON analysis with:
        {
          "title": "A catchy VJ-friendly title (3-5 words)",
          "description": "Brief description of visual style (1-2 sentences)",
          "mood": "Primary mood (energetic|calm|dark|bright|psychedelic|dreamy|aggressive|peaceful|hypnotic)",
          "energy": 0.0-1.0 (calm=0, intense=1),
          "colors": ["color1", "color2", "color3"] (dominant colors: neon, cyan, purple, warm, cool, rainbow, etc.),
          "effects": ["effect1", "effect2"] (geometric, fluid, particles, raymarching, fractal, kaleidoscope, tunnel, vortex, etc.),
          "geometry": ["shape1", "shape2"] (triangles, circles, spirals, cubes, spheres, etc.),
          "objects": ["object1", "object2"] (stars, waves, shapes, grid, etc.),
          "complexity": "low|medium|high",
          "visual_metadata": {
            "contrast": "low|medium|high",
            "saturation": "muted|normal|vibrant",
            "motion": "static|slow|medium|fast",
            "symmetry": "none|radial|bilateral|kaleidoscopic"
          },
          "dj_phases": ["phase1", "phase2"] (which DJ set phases this shader fits)
        }

        DJ Phases (select 1-3 that fit best):
        - disco: Warm, inviting, flowing visuals for starter songs
        - buildup: Increasing intensity, building tension
        - peak: Intense, fast, dark, aggressive visuals
        - release: Calming, atmospheric, breathing room
        - feature: Unique, erratic, attention-grabbing

        Return ONLY the JSON object, no other text.
        """

    private static func buildPrompt(shaderName: String, shaderSource: String, hasScreenshot: Bool) -> String {
        let screenshotNote = hasScreenshot
            ? "I've included a screenshot of the rendered shader. Please analyze BOTH the code and the visual output."
            : ""

        return analysisPrompt
            .replacingOccurrences(of: "%SHADER_NAME%", with: shaderName)
            .replacingOccurrences(of: "%SHADER_SOURCE%", with: String(shaderSource.prefix(2000)))
            .replacingOccurrences(of: "%SCREENSHOT_NOTE%", with: screenshotNote)
    }

    private static func makeTachikomaConfiguration(from config: LLMServiceConfig) -> TachikomaConfiguration {
        let tachikomaConfig = TachikomaConfiguration(loadFromEnvironment: true)
        if let baseURL = config.baseURL?.absoluteString {
            tachikomaConfig.setBaseURL(baseURL, for: config.provider.tachikomaProvider)
        }
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            tachikomaConfig.setAPIKey(apiKey, for: config.provider.tachikomaProvider)
        }
        return tachikomaConfig
    }
}

public enum AnalyzerError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int, String)
    case parseError(String)
    case notAvailable

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid LLM provider URL"
        case .invalidResponse:
            return "Invalid response from provider"
        case .serverError(let code, let body):
            return "LLM provider error \(code): \(body.prefix(200))"
        case .parseError(let message):
            return "Parse error: \(message)"
        case .notAvailable:
            return "LLM provider is not available"
        }
    }
}

private extension LLMServiceConfig {
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
}

private extension LLMProvider {
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

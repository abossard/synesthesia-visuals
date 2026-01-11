// ShaderAnalyzer.swift - AI-powered shader analysis via LM Studio
// Pure async functions

import Foundation

// MARK: - ShaderAnalyzer

/// Analyze shaders using LM Studio local LLM
public enum ShaderAnalyzer {
    
    /// Check if LM Studio server is available
    /// - Parameter config: LM Studio configuration
    /// - Returns: True if server responds
    public static func isAvailable(config: LMStudioConfig = .localhost) async -> Bool {
        guard let url = URL(string: "\(config.baseURL.absoluteString)/v1/models") else {
            return false
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5  // Quick health check
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            return false
        }
        
        return false
    }
    
    /// Analyze a shader using LM Studio
    /// - Parameters:
    ///   - shader: The shader to analyze
    ///   - shaderSource: GLSL source code
    ///   - screenshotData: Optional PNG screenshot data
    ///   - config: LM Studio configuration
    /// - Returns: ShaderAnalysis or nil if failed
    public static func analyze(
        shader: Shader,
        shaderSource: String,
        screenshotData: Data?,
        config: LMStudioConfig = .localhost
    ) async throws -> ShaderAnalysis {
        let prompt = buildPrompt(shaderName: shader.name, shaderSource: shaderSource, hasScreenshot: screenshotData != nil)
        
        let response = try await chatCompletion(
            prompt: prompt,
            imageBase64: screenshotData?.base64EncodedString(),
            config: config
        )
        
        return try parseAnalysis(from: response, shaderName: shader.name)
    }
    
    /// Analyze shader from source file
    /// - Parameters:
    ///   - shader: The shader to analyze
    ///   - config: LM Studio configuration
    /// - Returns: ShaderAnalysis
    public static func analyze(
        shader: Shader,
        config: LMStudioConfig = .localhost
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

// MARK: - Private Implementation

extension ShaderAnalyzer {
    
    /// Make chat completion request with optional vision
    private static func chatCompletion(
        prompt: String,
        imageBase64: String?,
        config: LMStudioConfig
    ) async throws -> String {
        guard let url = URL(string: "\(config.baseURL.absoluteString)/v1/chat/completions") else {
            throw AnalyzerError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = config.timeout
        
        // Build message content
        let messageContent: Any
        if let base64 = imageBase64 {
            messageContent = [
                ["type": "text", "text": prompt],
                ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64)"]]
            ]
        } else {
            messageContent = prompt
        }
        
        let payload: [String: Any] = [
            "messages": [["role": "user", "content": messageContent]],
            "max_tokens": config.maxTokens,
            "temperature": config.temperature
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalyzerError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw AnalyzerError.serverError(httpResponse.statusCode, body)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AnalyzerError.parseError("Could not extract content from response")
        }
        
        return content
    }
    
    /// Parse analysis JSON from LLM response
    private static func parseAnalysis(from content: String, shaderName: String) throws -> ShaderAnalysis {
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
    
    /// Build the analysis prompt
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
            ? "I've included a screenshot of the rendered shader. Please analyze BOTH the code AND the visual output."
            : ""
        
        return analysisPrompt
            .replacingOccurrences(of: "%SHADER_NAME%", with: shaderName)
            .replacingOccurrences(of: "%SHADER_SOURCE%", with: String(shaderSource.prefix(2000)))
            .replacingOccurrences(of: "%SCREENSHOT_NOTE%", with: screenshotNote)
    }
}

// MARK: - AnalyzerError

/// Errors from shader analysis
public enum AnalyzerError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(Int, String)
    case parseError(String)
    case notAvailable
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid LM Studio URL"
        case .invalidResponse:
            return "Invalid response from LM Studio"
        case .serverError(let code, let body):
            return "LM Studio error \(code): \(body.prefix(200))"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .notAvailable:
            return "LM Studio is not available"
        }
    }
}

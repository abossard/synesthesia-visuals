// LMStudioClient.swift - Client for LM Studio local LLM API
// Implements OpenAI-compatible chat completions endpoint

import Foundation

import SwiftVJCore

/// Result of shader analysis from LLM
struct ShaderAnalysisResult: Codable, Equatable {
    let title: String
    let description: String
    let mood: String
    let energy: Double
    let colors: [String]
    let effects: [String]
    let geometry: [String]
    let objects: [String]
    let complexity: String
    let visualMetadata: [String: String]
    let djPhases: [String]?  // DJ set phases this shader fits

    enum CodingKeys: String, CodingKey {
        case title, description, mood, energy, colors, effects, geometry, objects, complexity
        case visualMetadata = "visual_metadata"
        case djPhases = "dj_phases"
    }

    /// Convert dj_phases strings to Phase enum set
    var phases: Set<Phase> {
        Phase.fromStrings(djPhases ?? [])
    }
}

/// Client for LM Studio local LLM server
actor LMStudioClient {
    
    private let baseURL: String
    private let timeout: TimeInterval
    private let logger: @Sendable (String, LogLevel) -> Void
    
    /// Initialize LM Studio client
    /// - Parameters:
    ///   - baseURL: Base URL of LM Studio server (default: http://localhost:1234)
    ///   - timeout: Request timeout in seconds (default: 300s for large requests)
    ///   - logger: Logging function
    init(baseURL: String = "http://localhost:1234", timeout: TimeInterval = 300, logger: @escaping @Sendable (String, LogLevel) -> Void) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.logger = logger
    }
    
    /// Check if LM Studio server is available
    /// - Returns: True if server responds to health check
    func isAvailable() async -> Bool {
        logger("🔍 Checking LM Studio availability at \(baseURL)", .debug)
        
        guard let url = URL(string: "\(baseURL)/v1/models") else {
            logger("  ✗ Invalid LM Studio URL: \(baseURL)", .error)
            return false
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 5  // Quick health check
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let available = httpResponse.statusCode == 200
                if available {
                    logger("  ✓ LM Studio is available", .info)
                } else {
                    logger("  ✗ LM Studio returned status \(httpResponse.statusCode)", .warning)
                }
                return available
            }
        } catch {
            logger("  ✗ LM Studio not available: \(error.localizedDescription)", .debug)
        }
        
        return false
    }
    
    /// Analyze shader using LLM
    /// - Parameters:
    ///   - shaderName: Name of the shader
    ///   - shaderSource: GLSL source code
    ///   - screenshotPath: Path to screenshot (for visual analysis)
    /// - Returns: Analysis result or nil if failed
    func analyzeShader(shaderName: String, shaderSource: String, screenshotPath: URL?) async -> ShaderAnalysisResult? {
        logger("🤖 Analyzing shader '\(shaderName)' with LM Studio", .info)
        
        // Build prompt text
        let promptText = buildShaderAnalysisPrompt(shaderName: shaderName, shaderSource: shaderSource, hasScreenshot: screenshotPath != nil)
        
        // Load and encode screenshot if available
        var imageBase64: String? = nil
        if let path = screenshotPath {
            imageBase64 = loadImageAsBase64(from: path)
            if imageBase64 != nil {
                logger("  🖼️ Screenshot encoded (\(imageBase64!.count / 1024) KB base64)", .debug)
            }
        }
        
        // Make request with vision support
        guard let result = await chatCompletionWithVision(prompt: promptText, imageBase64: imageBase64) else {
            logger("  ✗ LM Studio chat completion failed", .error)
            return nil
        }
        
        // Parse JSON from response
        return parseShaderAnalysis(content: result, shaderName: shaderName)
    }
    
    /// Load image from disk and encode as base64
    private func loadImageAsBase64(from path: URL) -> String? {
        guard let imageData = try? Data(contentsOf: path) else {
            logger("  ⚠️ Could not read screenshot file", .warning)
            return nil
        }
        return imageData.base64EncodedString()
    }
    
    /// Make chat completion request with vision support
    /// - Parameters:
    ///   - prompt: The text prompt
    ///   - imageBase64: Optional base64-encoded image
    /// - Returns: Response content or nil if failed
    private func chatCompletionWithVision(prompt: String, imageBase64: String?) async -> String? {
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            logger("  ✗ Invalid chat completions URL", .error)
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        
        // Build message content - either simple text or multi-part with image
        let messageContent: Any
        if let base64 = imageBase64 {
            // Vision format: array of content parts (text + image)
            messageContent = [
                [
                    "type": "text",
                    "text": prompt
                ],
                [
                    "type": "image_url",
                    "image_url": [
                        "url": "data:image/png;base64,\(base64)"
                    ]
                ]
            ]
        } else {
            // Simple text format
            messageContent = prompt
        }
        
        let payload: [String: Any] = [
            "messages": [
                ["role": "user", "content": messageContent]
            ],
            "max_tokens": 4000,  // Increased for reasoning models that need more tokens
            "temperature": 0.7
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            logger("  ✗ Failed to serialize request payload: \(error)", .error)
            return nil
        }
        
        let payloadSize = request.httpBody?.count ?? 0
        logger("  📡 Sending request to LM Studio (\(payloadSize / 1024) KB payload)", .debug)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logger("  ✗ Invalid response type", .error)
                return nil
            }
            
            logger("  📥 Received response: HTTP \(httpResponse.statusCode)", .debug)
            
            guard httpResponse.statusCode == 200 else {
                let errorBody = String(data: data, encoding: .utf8) ?? "unknown error"
                logger("  ✗ LM Studio returned status \(httpResponse.statusCode): \(errorBody.prefix(200))", .error)
                return nil
            }
            
            // Parse response - handle both regular models and reasoning models
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any] else {
                logger("  ✗ Failed to parse LM Studio response structure", .error)
                if let rawBody = String(data: data, encoding: .utf8) {
                    logger("  📄 Raw response: \(rawBody.prefix(500))", .debug)
                }
                return nil
            }
            
            // Try content first, then reasoning_content (for reasoning models like ministral)
            var content = message["content"] as? String ?? ""
            if content.isEmpty, let reasoningContent = message["reasoning_content"] as? String {
                logger("  ℹ️ Using reasoning_content (reasoning model detected)", .debug)
                content = reasoningContent
            }
            
            // Check for empty content (model may have failed silently)
            if content.isEmpty {
                logger("  ⚠️ LM Studio returned empty content - model may not be loaded or request too large", .warning)
                if let rawBody = String(data: data, encoding: .utf8) {
                    logger("  📄 Full response: \(rawBody.prefix(1000))", .debug)
                }
                return nil
            }
            
            logger("  ✓ LM Studio response received (\(content.count) chars)", .info)
            return content
            
        } catch {
            logger("  ✗ LM Studio request failed: \(error.localizedDescription)", .error)
            return nil
        }
    }
    
    /// Build shader analysis prompt
    private func buildShaderAnalysisPrompt(shaderName: String, shaderSource: String, hasScreenshot: Bool) -> String {
        var prompt = """
        Analyze this GLSL shader for VJ music visualization matching.
        
        Shader name: \(shaderName)
        
        GLSL source code (first 2000 chars):
        \(String(shaderSource.prefix(2000)))
        
        """
        
        if hasScreenshot {
            prompt += """
            
            I've included a screenshot of the rendered shader. Please analyze BOTH the code AND the visual output to provide an accurate description of colors, effects, and mood.
            
            """
        }
        
        prompt += """

        Provide a JSON analysis with:
        {
          "title": "A catchy VJ-friendly title (3-5 words)",
          "description": "Brief description of visual style (1-2 sentences)",
          "mood": "Primary mood (energetic|calm|dark|bright|psychedelic|dreamy|aggressive|peaceful|hypnotic)",
          "energy": 0.0-1.0 (calm=0, intense=1),
          "colors": ["color1", "color2", "color3"] (dominant colors from the screenshot: neon, cyan, purple, warm, cool, rainbow, etc.),
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
          "dj_phases": ["phase1", "phase2"] (which DJ set phases this shader fits - can select multiple)
        }

        DJ Phases (select 1-3 that fit best):
        - disco: Warm, inviting, flowing visuals for starter songs
        - buildup: Increasing intensity, building tension
        - peak: Intense, fast, dark, aggressive visuals
        - release: Calming, atmospheric, breathing room
        - feature: Unique, erratic, attention-grabbing

        Return ONLY the JSON object, no other text.
        """
        
        return prompt
    }
    
    /// Parse shader analysis from LLM response
    private func parseShaderAnalysis(content: String, shaderName: String) -> ShaderAnalysisResult? {
        // Find JSON object in response
        guard let jsonStart = content.firstIndex(of: "{"),
              let jsonEnd = content.lastIndex(of: "}") else {
            logger("  ✗ No JSON found in LLM response", .error)
            return nil
        }
        
        let jsonString = String(content[jsonStart...jsonEnd])
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            logger("  ✗ Failed to convert JSON string to data", .error)
            return nil
        }
        
        do {
            let result = try JSONDecoder().decode(ShaderAnalysisResult.self, from: jsonData)
            logger("  ✓ Successfully parsed shader analysis", .info)
            return result
        } catch {
            logger("  ✗ Failed to parse shader analysis JSON: \(error)", .error)
            logger("  📄 Response was: \(jsonString.prefix(500))", .debug)
            return nil
        }
    }
}

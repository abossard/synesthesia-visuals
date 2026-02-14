import Foundation
import Tachikoma

public enum LLMClientError: Error, Equatable {
    case notAvailable
    case requestFailed(String)
    case invalidResponse(String)
    case timeout
}

public enum LLMBackend: Equatable {
    case none
    case tachikoma(provider: String, model: String)
}

public struct SongAnalysis: Sendable, Equatable {
    public let keywords: [String]
    public let themes: [String]
    public let visualAdjectives: [String]
    public let refrainLines: [String]
    public let tempo: String
    public let mood: String
    public let energy: Double
    public let valence: Double
    public let categories: [String: Double]
    public let djPhase: Phase?
    public let cached: Bool

    public init(
        keywords: [String] = [],
        themes: [String] = [],
        visualAdjectives: [String] = [],
        refrainLines: [String] = [],
        tempo: String = "medium",
        mood: String = "neutral",
        energy: Double = 0.5,
        valence: Double = 0.0,
        categories: [String: Double] = [:],
        djPhase: Phase? = nil,
        cached: Bool = false
    ) {
        self.keywords = keywords
        self.themes = themes
        self.visualAdjectives = visualAdjectives
        self.refrainLines = refrainLines
        self.tempo = tempo
        self.mood = mood
        self.energy = energy
        self.valence = valence
        self.categories = categories
        self.djPhase = djPhase
        self.cached = cached
    }

    public var primaryMood: String {
        categories.max(by: { $0.value < $1.value })?.key ?? mood
    }
}

public actor LLMClient {
    public static let configPathDefaultsKey = "tachikomaConfigPath"
    private static let recheckInterval: TimeInterval = 30
    private static let requestTimeout: TimeInterval = 60

    private static let defaultCategories = [
        "dark", "happy", "sad", "energetic", "calm", "love",
        "romantic", "aggressive", "peaceful", "nostalgic", "uplifting"
    ]

    private let runtimeConfig: TachikomaLLMRuntimeConfig
    private let tachikomaConfiguration: TachikomaConfiguration

    private var backend: LLMBackend = .none
    private var lastCheck: Date = .distantPast
    private let health: ServiceHealth
    private var analysisCache: [String: SongAnalysis] = [:]
    private var categoriesCache: [String: SongCategories] = [:]

    public init(
        runtimeConfig: TachikomaLLMRuntimeConfig? = nil,
        runtimeConfigURL: URL? = nil
    ) {
        let selectedURL = runtimeConfigURL ?? Self.selectedConfigURLFromDefaults()
        let resolvedConfig = runtimeConfig ?? TachikomaLLMRuntimeConfig.load(from: selectedURL)
        self.runtimeConfig = resolvedConfig
        self.tachikomaConfiguration = resolvedConfig.makeTachikomaConfiguration()
        self.health = ServiceHealth(name: "LLM")
    }

    public var isAvailable: Bool {
        backend != .none
    }

    public var backendInfo: String {
        switch backend {
        case .none:
            return "Basic (no LLM)"
        case .tachikoma(let provider, let model):
            return "Tachikoma \(provider) (\(model))"
        }
    }

    public func start() async {
        await checkBackend(using: runtimeConfig.songAnalysis)
    }

    public func startShaderAnalysis() async {
        await checkBackend(using: runtimeConfig.shaderAnalysis)
    }

    public func analyzeSong(
        lyrics: String,
        artist: String,
        title: String,
        album: String? = nil
    ) async throws -> SongAnalysis {
        let cacheKey = makeAnalysisCacheKey(
            lyrics: lyrics,
            artist: artist,
            title: title,
            album: album
        )
        if let cached = analysisCache[cacheKey] {
            return cached.withCached(true)
        }

        await ensureBackend()
        if backend != .none {
            if let result = try? await analyzeSongWithLLM(lyrics: lyrics, artist: artist, title: title, album: album) {
                analysisCache[cacheKey] = result.withCached(false)
                return result
            }
        }

        let fallback = basicAnalysis(lyrics: lyrics, artist: artist, title: title)
        analysisCache[cacheKey] = fallback.withCached(false)
        return fallback
    }

    public func categorize(
        artist: String,
        title: String,
        lyrics: String?
    ) async -> SongCategories {
        let cacheKey = makeCategoriesCacheKey(artist: artist, title: title, lyrics: lyrics)
        if let cached = categoriesCache[cacheKey] {
            return cached
        }

        await ensureBackend()
        if backend != .none, let lyrics {
            if let result = try? await categorizeWithLLM(artist: artist, title: title, lyrics: lyrics) {
                categoriesCache[cacheKey] = result
                return result
            }
        }

        let fallback = basicCategorization(artist: artist, title: title, lyrics: lyrics)
        categoriesCache[cacheKey] = fallback
        return fallback
    }

    public struct LLMShaderAnalysis: Sendable, Equatable {
        public let shaderName: String
        public let title: String
        public let mood: String
        public let energy: Double
        public let colors: [String]
        public let effects: [String]
        public let geometry: [String]
        public let objects: [String]
        public let complexity: String
        public let description: String
        public let visualMetadata: [String: String]
        public let djPhases: [String]
        public let features: ShaderFeatureScores
        public let hasScreenshot: Bool
        public let error: String?

        public init(
            shaderName: String,
            title: String = "",
            mood: String = "unknown",
            energy: Double = 0.5,
            colors: [String] = [],
            effects: [String] = [],
            geometry: [String] = [],
            objects: [String] = [],
            complexity: String = "medium",
            description: String = "",
            visualMetadata: [String: String] = [:],
            djPhases: [String] = [],
            features: ShaderFeatureScores = ShaderFeatureScores(),
            hasScreenshot: Bool = false,
            error: String? = nil
        ) {
            self.shaderName = shaderName
            self.title = title
            self.mood = mood
            self.energy = energy
            self.colors = colors
            self.effects = effects
            self.geometry = geometry
            self.objects = objects
            self.complexity = complexity
            self.description = description
            self.visualMetadata = visualMetadata
            self.djPhases = djPhases
            self.features = features
            self.hasScreenshot = hasScreenshot
            self.error = error
        }
    }

    public struct ShaderFeatureScores: Sendable, Equatable {
        public let energyScore: Double
        public let moodValence: Double
        public let colorWarmth: Double
        public let motionSpeed: Double
        public let geometricScore: Double
        public let visualDensity: Double

        public init(
            energyScore: Double = 0.5,
            moodValence: Double = 0.0,
            colorWarmth: Double = 0.5,
            motionSpeed: Double = 0.5,
            geometricScore: Double = 0.5,
            visualDensity: Double = 0.5
        ) {
            self.energyScore = energyScore
            self.moodValence = moodValence
            self.colorWarmth = colorWarmth
            self.motionSpeed = motionSpeed
            self.geometricScore = geometricScore
            self.visualDensity = visualDensity
        }

        public func toVector() -> [Double] {
            [energyScore, moodValence, colorWarmth, motionSpeed, geometricScore, visualDensity]
        }
    }

    public func analyzeShader(
        shaderName: String,
        shaderSource: String,
        screenshotData: Data? = nil,
        timeout: TimeInterval = 120
    ) async -> LLMShaderAnalysis {
        await ensureBackend()

        guard backend != .none else {
            return LLMShaderAnalysis(shaderName: shaderName, error: "LLM not available")
        }

        let prompt = buildShaderAnalysisPrompt(
            shaderName: shaderName,
            source: shaderSource,
            hasScreenshot: screenshotData != nil
        )

        do {
            let content = try await sendShaderAnalysisRequest(
                prompt: prompt,
                screenshotData: screenshotData,
                maxTokens: 1400,
                timeout: timeout
            )
            var parsed = parseShaderAnalysisResponse(content, shaderName: shaderName)
            parsed = LLMShaderAnalysis(
                shaderName: parsed.shaderName,
                title: parsed.title.isEmpty ? shaderName : parsed.title,
                mood: parsed.mood,
                energy: parsed.energy,
                colors: parsed.colors,
                effects: parsed.effects,
                geometry: parsed.geometry,
                objects: parsed.objects,
                complexity: parsed.complexity,
                description: parsed.description,
                visualMetadata: parsed.visualMetadata,
                djPhases: parsed.djPhases,
                features: parsed.features,
                hasScreenshot: screenshotData != nil,
                error: parsed.error
            )
            return parsed
        } catch {
            return LLMShaderAnalysis(
                shaderName: shaderName,
                hasScreenshot: screenshotData != nil,
                error: error.localizedDescription
            )
        }
    }

    public func status() async -> ServiceHealthStatus {
        await health.status()
    }

    private func ensureBackend() async {
        if backend == .none && Date().timeIntervalSince(lastCheck) > Self.recheckInterval {
            await checkBackend()
        }
    }

    private func checkBackend() async {
        await checkBackend(using: runtimeConfig.songAnalysis)
    }

    private func checkBackend(using providerConfig: TachikomaProviderConfig) async {
        lastCheck = Date()

        if providerConfig.provider == .lmstudio {
            let baseURL = providerConfig.baseURL ?? "http://localhost:1234/v1"
            if let detectedModel = await probeLMStudioModel(baseURL: baseURL) {
                let model = detectedModel.isEmpty ? providerConfig.model : detectedModel
                backend = .tachikoma(provider: "LMStudio", model: model)
                await health.markAvailable(message: "Tachikoma LMStudio (\(model))")
                return
            }

            backend = .none
            await health.markUnavailable(error: "LMStudio unavailable at \(baseURL)")
            return
        }

        let provider = providerConfig.provider.tachikomaProvider
        let hasInlineKey = !(providerConfig.apiKey?.isEmpty ?? true)
        let hasCredentials = hasInlineKey || tachikomaConfiguration.hasAPIKey(for: provider)
        let isUsable = provider.requiresAPIKey ? hasCredentials : true

        if isUsable {
            backend = .tachikoma(
                provider: provider.displayName,
                model: providerConfig.model
            )
            await health.markAvailable(message: "Tachikoma \(provider.displayName) (\(providerConfig.model))")
        } else {
            backend = .none
            await health.markUnavailable(error: "Missing credentials for \(provider.displayName)")
        }
    }

    private func probeLMStudioModel(baseURL: String) async -> String? {
        guard let modelsURL = modelsEndpointURL(from: baseURL) else {
            return nil
        }

        var request = URLRequest(url: modelsURL)
        request.timeoutInterval = 3

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]],
               let firstModel = models.first?["id"] as? String {
                return firstModel
            }

            // Endpoint is healthy even if no model id was parsed.
            return "current"
        } catch {
            return nil
        }
    }

    private func modelsEndpointURL(from baseURL: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(trimmed)/models")
    }

    private func analyzeSongWithLLM(
        lyrics: String,
        artist: String,
        title: String,
        album: String?
    ) async throws -> SongAnalysis {
        let categories = Self.defaultCategories.joined(separator: ", ")
        let albumContext = album.map { " from album \"\($0)\"" } ?? ""

        let prompt = """
        Analyze the song "\(title)" by \(artist)\(albumContext).

        Lyrics:
        \(String(lyrics.prefix(2500)))

        Provide a complete analysis as JSON with:
        1. keywords: 5-10 important words from the lyrics
        2. themes: 2-4 main themes (love, loss, rebellion, etc.)
        3. visual_adjectives: 5-8 visual/aesthetic words for image search (neon, cosmic, ethereal, gritty, etc.)
        4. refrain_lines: repeated chorus/hook lines (max 3)
        5. tempo: slow/medium/fast
        6. mood: primary mood (dark/happy/sad/energetic/calm/romantic/aggressive/peaceful/dreamy/nostalgic)
        7. energy: 0.0-1.0 (calm=0, intense=1)
        8. valence: -1.0 to 1.0 (dark/negative=-1, bright/positive=+1)
        9. categories: scores 0.0-1.0 for each: \(categories)
        10. dj_phase: suggested DJ set phase (one of: disco, buildup, peak, release, feature)
            - disco: Starter songs, jungle beats, 90-125 BPM, easy listening
            - buildup: Bridge songs, 115-140 BPM, building energy
            - peak: High energy, dark, loud, 135-160 BPM
            - release: Breathing room, atmospheric, after peaks
            - feature: Special/erratic, remixes, doesn't fit elsewhere

        Return ONLY valid JSON:
        {
          "keywords": ["word1", "word2"],
          "themes": ["theme1", "theme2"],
          "visual_adjectives": ["adj1", "adj2"],
          "refrain_lines": ["line1"],
          "tempo": "medium",
          "mood": "energetic",
          "energy": 0.7,
          "valence": 0.3,
          "categories": {"dark": 0.2, "happy": 0.6},
          "dj_phase": "buildup"
        }
        """

        let content = try await sendChatRequest(prompt: prompt, maxTokens: 900)
        return try parseAnalysisResponse(content)
    }

    private func categorizeWithLLM(
        artist: String,
        title: String,
        lyrics: String
    ) async throws -> SongCategories {
        let categories = Self.defaultCategories.joined(separator: ", ")

        let prompt = """
        Rate song "\(title)" by \(artist) on these categories (0.0-1.0):
        \(categories)

        Lyrics: \(String(lyrics.prefix(1500)))

        Return JSON: {"dark": 0.8, "energetic": 0.3, ...}
        """

        let content = try await sendChatRequest(prompt: prompt, maxTokens: 320)

        if let start = content.firstIndex(of: "{"),
           let end = content.lastIndex(of: "}") {
            let jsonStr = String(content[start...end])
            if let data = jsonStr.data(using: .utf8),
               let scores = try? JSONSerialization.jsonObject(with: data) as? [String: Double] {
                return SongCategories(scores: scores)
            }
        }

        throw LLMClientError.invalidResponse("Failed to parse categories")
    }

    private func sendChatRequest(prompt: String, maxTokens: Int) async throws -> String {
        guard backend != .none else {
            throw LLMClientError.notAvailable
        }

        return try await generate(
            prompt,
            using: runtimeConfig.songAnalysis.languageModel,
            maxTokens: maxTokens,
            temperature: 0.2,
            timeout: Self.requestTimeout,
            configuration: tachikomaConfiguration
        )
    }

    private func sendShaderAnalysisRequest(
        prompt: String,
        screenshotData: Data?,
        maxTokens: Int,
        timeout: TimeInterval
    ) async throws -> String {
        guard backend != .none else {
            throw LLMClientError.notAvailable
        }

        let model = runtimeConfig.shaderAnalysis.languageModel
        let settings = GenerationSettings(maxTokens: maxTokens, temperature: 0.2)

        if let screenshotData {
            let image = ModelMessage.ContentPart.ImageContent(
                data: screenshotData.base64EncodedString(),
                mimeType: "image/png"
            )
            let messages = [ModelMessage.user(text: prompt, images: [image])]
            let result = try await generateText(
                model: model,
                messages: messages,
                settings: settings,
                timeout: timeout,
                configuration: tachikomaConfiguration
            )
            return result.text
        }

        let result = try await generateText(
            model: model,
            messages: [.user(prompt)],
            settings: settings,
            timeout: timeout,
            configuration: tachikomaConfiguration
        )
        return result.text
    }

    private func parseAnalysisResponse(_ content: String) throws -> SongAnalysis {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}") else {
            throw LLMClientError.invalidResponse("No JSON found")
        }

        let jsonStr = String(content[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMClientError.invalidResponse("Invalid JSON")
        }

        let djPhase: Phase?
        if let phaseStr = json["dj_phase"] as? String {
            djPhase = Phase.from(phaseStr)
        } else {
            djPhase = nil
        }

        return SongAnalysis(
            keywords: (json["keywords"] as? [String]) ?? [],
            themes: (json["themes"] as? [String]) ?? [],
            visualAdjectives: (json["visual_adjectives"] as? [String]) ?? [],
            refrainLines: (json["refrain_lines"] as? [String]) ?? [],
            tempo: (json["tempo"] as? String) ?? "medium",
            mood: (json["mood"] as? String) ?? "neutral",
            energy: (json["energy"] as? Double) ?? 0.5,
            valence: (json["valence"] as? Double) ?? 0.0,
            categories: (json["categories"] as? [String: Double]) ?? [:],
            djPhase: djPhase,
            cached: false
        )
    }

    private func buildShaderAnalysisPrompt(shaderName: String, source: String, hasScreenshot: Bool) -> String {
        let truncatedSource = source.count > 6000
            ? String(source.prefix(6000)) + "\n// ... (truncated)"
            : source

        var prompt = """
        Analyze this GLSL shader for VJ music visualization matching.

        Shader name: \(shaderName)

        GLSL source code:
        ```glsl
        \(truncatedSource)
        ```
        """

        if hasScreenshot {
            prompt += "\nI've included a screenshot of the rendered shader. Use BOTH code and visual output.\n"
        }

        prompt += """

        Return ONLY valid JSON:
        {
          "title": "A catchy VJ-friendly title (3-5 words)",
          "description": "Brief description of visual style (1-2 sentences)",
          "mood": "energetic|calm|dark|bright|psychedelic|dreamy|aggressive|peaceful|hypnotic",
          "energy": 0.0,
          "colors": ["color1", "color2", "color3"],
          "effects": ["effect1", "effect2"],
          "geometry": ["shape1", "shape2"],
          "objects": ["object1", "object2"],
          "complexity": "low|medium|high",
          "visual_metadata": {
            "contrast": "low|medium|high",
            "saturation": "muted|normal|vibrant",
            "motion": "static|slow|medium|fast",
            "symmetry": "none|radial|bilateral|kaleidoscopic"
          },
          "dj_phases": ["disco", "buildup"],
          "features": {
            "energy_score": 0.0,
            "mood_valence": 0.0,
            "color_warmth": 0.0,
            "motion_speed": 0.0,
            "geometric_score": 0.0,
            "visual_density": 0.0
          }
        }
        """

        return prompt
    }

    private func parseShaderAnalysisResponse(_ content: String, shaderName: String) -> LLMShaderAnalysis {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}") else {
            return LLMShaderAnalysis(shaderName: shaderName, error: "No JSON found in response")
        }

        let jsonStr = String(content[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LLMShaderAnalysis(shaderName: shaderName, error: "Invalid JSON")
        }

        let featuresDict = json["features"] as? [String: Any] ?? [:]
        let features = ShaderFeatureScores(
            energyScore: featuresDict.doubleValue(for: "energy_score", default: 0.5),
            moodValence: featuresDict.doubleValue(for: "mood_valence", default: 0.5),
            colorWarmth: featuresDict.doubleValue(for: "color_warmth", default: 0.5),
            motionSpeed: featuresDict.doubleValue(for: "motion_speed", default: 0.5),
            geometricScore: featuresDict.doubleValue(for: "geometric_score", default: 0.5),
            visualDensity: featuresDict.doubleValue(for: "visual_density", default: 0.5)
        )

        var visualMetadata: [String: String] = [:]
        if let metadata = json["visual_metadata"] as? [String: Any] {
            for (key, value) in metadata {
                visualMetadata[key] = String(describing: value)
            }
        }

        return LLMShaderAnalysis(
            shaderName: shaderName,
            title: (json["title"] as? String) ?? shaderName,
            mood: (json["mood"] as? String) ?? "unknown",
            energy: json.doubleValue(for: "energy", default: features.energyScore),
            colors: (json["colors"] as? [String]) ?? [],
            effects: (json["effects"] as? [String]) ?? [],
            geometry: (json["geometry"] as? [String]) ?? [],
            objects: (json["objects"] as? [String]) ?? [],
            complexity: (json["complexity"] as? String) ?? "medium",
            description: (json["description"] as? String) ?? "",
            visualMetadata: visualMetadata,
            djPhases: (json["dj_phases"] as? [String]) ?? [],
            features: features,
            hasScreenshot: false,
            error: nil
        )
    }

    private func basicAnalysis(lyrics: String, artist: String, title: String) -> SongAnalysis {
        let text = (title + " " + lyrics).lowercased()
        let words = text.components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }

        var wordCounts: [String: Int] = [:]
        for word in words {
            wordCounts[word, default: 0] += 1
        }
        let keywords = wordCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }

        var categories: [String: Double] = Self.defaultCategories.reduce(into: [:]) { $0[$1] = 0.1 }

        if text.contains(anyOf: ["dark", "death", "shadow", "night", "black"]) {
            categories["dark"] = 0.7
        }
        if text.contains(anyOf: ["happy", "joy", "smile", "laugh", "fun"]) {
            categories["happy"] = 0.7
        }
        if text.contains(anyOf: ["sad", "cry", "tear", "pain", "hurt"]) {
            categories["sad"] = 0.7
        }
        if text.contains(anyOf: ["love", "heart", "kiss", "baby"]) {
            categories["love"] = 0.7
        }
        if text.contains(anyOf: ["fight", "rage", "anger", "hate"]) {
            categories["aggressive"] = 0.7
        }
        if text.contains(anyOf: ["dance", "party", "move", "groove"]) {
            categories["energetic"] = 0.7
        }

        let highEnergy = ["energetic", "aggressive", "uplifting"]
        let lowEnergy = ["calm", "peaceful", "sad"]
        let positive = ["happy", "uplifting", "love", "romantic", "peaceful"]
        let negative = ["dark", "sad", "aggressive"]

        let highSum = highEnergy.compactMap { categories[$0] }.reduce(0, +)
        let lowSum = lowEnergy.compactMap { categories[$0] }.reduce(0, +)
        let energy = (highSum + lowSum) > 0 ? highSum / (highSum + lowSum + 0.001) : 0.5

        let posSum = positive.compactMap { categories[$0] }.reduce(0, +)
        let negSum = negative.compactMap { categories[$0] }.reduce(0, +)
        let valence = (posSum + negSum) > 0 ? (posSum - negSum) / (posSum + negSum + 0.001) : 0.0

        let primaryMood = categories.max { $0.value < $1.value }?.key ?? "neutral"

        return SongAnalysis(
            keywords: Array(keywords),
            themes: [],
            visualAdjectives: [],
            refrainLines: [],
            tempo: "medium",
            mood: primaryMood,
            energy: energy,
            valence: valence,
            categories: categories,
            cached: false
        )
    }

    private func basicCategorization(artist: String, title: String, lyrics: String?) -> SongCategories {
        var categories: [String: Double] = Self.defaultCategories.reduce(into: [:]) { $0[$1] = 0.1 }

        if let lyrics {
            let text = (title + " " + lyrics).lowercased()

            if text.contains(anyOf: ["dark", "death", "shadow", "night"]) {
                categories["dark"] = 0.7
            }
            if text.contains(anyOf: ["happy", "joy", "smile", "laugh"]) {
                categories["happy"] = 0.7
            }
            if text.contains(anyOf: ["sad", "cry", "tear", "pain"]) {
                categories["sad"] = 0.7
            }
            if text.contains(anyOf: ["love", "heart", "kiss"]) {
                categories["love"] = 0.7
            }
        }

        return SongCategories(scores: categories)
    }

    private let stopWords: Set<String> = [
        "the", "be", "to", "of", "and", "a", "in", "that", "have", "i",
        "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
        "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
        "or", "an", "will", "my", "one", "all", "would", "there", "their",
        "what", "so", "up", "out", "if", "about", "who", "get", "which", "go",
        "me", "when", "make", "can", "like", "time", "no", "just", "him",
        "know", "take", "people", "into", "year", "your", "good", "some",
        "could", "them", "see", "other", "than", "then", "now", "look",
        "only", "come", "its", "over", "think", "also", "back", "after",
        "use", "two", "how", "our", "work", "first", "well", "way", "even",
        "new", "want", "because", "any", "these", "give", "day", "most", "us",
        "yeah", "oh", "ooh", "ahh", "mmm", "gonna", "wanna", "gotta"
    ]

    private func makeAnalysisCacheKey(
        lyrics: String,
        artist: String,
        title: String,
        album: String?
    ) -> String {
        let fingerprint = String(lyrics.lowercased().hashValue)
        return [
            artist.lowercased(),
            title.lowercased(),
            (album ?? "").lowercased(),
            fingerprint
        ].joined(separator: "|")
    }

    private func makeCategoriesCacheKey(
        artist: String,
        title: String,
        lyrics: String?
    ) -> String {
        let fingerprint = String((lyrics ?? "").lowercased().hashValue)
        return [artist.lowercased(), title.lowercased(), fingerprint].joined(separator: "|")
    }
}

private extension LLMClient {
    static func selectedConfigURLFromDefaults() -> URL? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: configPathDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: raw)
    }
}

extension SongAnalysis {
    func withCached(_ cached: Bool) -> SongAnalysis {
        SongAnalysis(
            keywords: keywords,
            themes: themes,
            visualAdjectives: visualAdjectives,
            refrainLines: refrainLines,
            tempo: tempo,
            mood: mood,
            energy: energy,
            valence: valence,
            categories: categories,
            djPhase: djPhase,
            cached: cached
        )
    }
}

extension String {
    func contains(anyOf words: [String]) -> Bool {
        words.contains { self.contains($0) }
    }
}

private extension Dictionary where Key == String, Value == Any {
    func doubleValue(for key: String, default defaultValue: Double) -> Double {
        if let value = self[key] as? Double {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.doubleValue
        }
        return defaultValue
    }
}

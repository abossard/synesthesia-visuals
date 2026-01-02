// LLMClient - Adapter for LLM backends (LM Studio, OpenAI)
// Following Grokking Simplicity: this is an action (side effects)
// Graceful degradation: works offline with basic keyword analysis

import Foundation

/// Error types for LLM operations
public enum LLMClientError: Error, Equatable {
    case notAvailable
    case requestFailed(String)
    case invalidResponse(String)
    case timeout
}

/// LLM backend type
public enum LLMBackend: Equatable {
    case none
    case lmStudio(model: String)
    case openAI
}

/// Result of song analysis
public struct SongAnalysis: Sendable, Equatable {
    public let keywords: [String]
    public let themes: [String]
    public let visualAdjectives: [String]
    public let refrainLines: [String]
    public let tempo: String
    public let mood: String
    public let energy: Double  // 0.0-1.0
    public let valence: Double  // -1.0 to 1.0
    public let categories: [String: Double]
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
        self.cached = cached
    }
    
    /// Primary mood from highest category score
    public var primaryMood: String {
        categories.max(by: { $0.value < $1.value })?.key ?? mood
    }
}

/// LLM client for song analysis with fallback
///
/// Architecture:
/// - Tries LM Studio first (local, fast, private)
/// - Falls back to OpenAI if available
/// - Falls back to basic keyword analysis if no LLM
///
/// Deep module: Simple interface, hides backend complexity
public actor LLMClient {
    
    // MARK: - Configuration
    
    public static let lmStudioURL = "http://localhost:1234"
    private static let lmStudioTimeout: TimeInterval = 60
    private static let recheckInterval: TimeInterval = 30
    
    // Default categories for song categorization
    private static let defaultCategories = [
        "dark", "happy", "sad", "energetic", "calm", "love",
        "romantic", "aggressive", "peaceful", "nostalgic", "uplifting"
    ]
    
    // MARK: - State
    
    private var backend: LLMBackend = .none
    private var lastCheck: Date = .distantPast
    private let health: ServiceHealth
    
    // Cache directory
    private let cacheDir: URL
    
    public init(cacheDir: URL? = nil) {
        self.cacheDir = cacheDir ?? Config.cacheDirectory.appendingPathComponent("llm_cache")
        self.health = ServiceHealth(name: "LLM")
        
        // Create cache directory
        try? FileManager.default.createDirectory(at: self.cacheDir, withIntermediateDirectories: true)
    }
    
    // MARK: - Public API
    
    /// Check if LLM is available
    public var isAvailable: Bool {
        backend != .none
    }
    
    /// Get backend info string
    public var backendInfo: String {
        switch backend {
        case .none:
            return "Basic (no LLM)"
        case .lmStudio(let model):
            return "LM Studio (\(model))"
        case .openAI:
            return "OpenAI"
        }
    }
    
    /// Initialize/check LLM backend
    public func start() async {
        await checkBackend()
    }
    
    /// Complete song analysis (combines metadata + categorization)
    public func analyzeSong(
        lyrics: String,
        artist: String,
        title: String,
        album: String? = nil
    ) async throws -> SongAnalysis {
        // Check cache first
        let cacheKey = sanitizeCacheFilename(artist: artist, title: title) + "_complete"
        let cacheFile = cacheDir.appendingPathComponent("\(cacheKey).json")
        
        if let cached = loadCache(from: cacheFile) {
            return cached.withCached(true)
        }
        
        // Try LLM
        await ensureBackend()
        
        if backend != .none {
            if let result = try? await analyzeSongWithLLM(lyrics: lyrics, artist: artist, title: title, album: album) {
                saveCache(result, to: cacheFile)
                return result
            }
        }
        
        // Fallback to basic analysis
        let result = basicAnalysis(lyrics: lyrics, artist: artist, title: title)
        saveCache(result, to: cacheFile)
        return result
    }
    
    /// Categorize song by mood/theme
    public func categorize(
        artist: String,
        title: String,
        lyrics: String?
    ) async -> SongCategories {
        // Check cache
        let cacheKey = sanitizeCacheFilename(artist: artist, title: title) + "_cat"
        let cacheFile = cacheDir.appendingPathComponent("\(cacheKey).json")
        
        if let data = try? Data(contentsOf: cacheFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scores = json["categories"] as? [String: Double] {
            return SongCategories(
                scores: scores,
                primaryMood: json["primary_mood"] as? String ?? ""
            )
        }
        
        // Try LLM
        await ensureBackend()
        
        if backend != .none, let lyrics = lyrics {
            if let result = try? await categorizeWithLLM(artist: artist, title: title, lyrics: lyrics) {
                // Cache result
                let json: [String: Any] = ["categories": result.scores, "primary_mood": result.primaryMood]
                if let data = try? JSONSerialization.data(withJSONObject: json) {
                    try? data.write(to: cacheFile)
                }
                return result
            }
        }
        
        // Fallback
        return basicCategorization(artist: artist, title: title, lyrics: lyrics)
    }
    
    /// Get service status
    public func status() async -> [String: Any] {
        await health.status()
    }
    
    // MARK: - Backend Management
    
    private func ensureBackend() async {
        if backend == .none && Date().timeIntervalSince(lastCheck) > Self.recheckInterval {
            await checkBackend()
        }
    }
    
    private func checkBackend() async {
        lastCheck = Date()
        
        // Try LM Studio first
        if let model = await checkLMStudio() {
            backend = .lmStudio(model: model)
            await health.markAvailable(message: "LM Studio (\(model))")
            print("[LLM] ✓ LM Studio (\(model))")
            return
        }
        
        // Try OpenAI
        if checkOpenAI() {
            backend = .openAI
            await health.markAvailable(message: "OpenAI")
            print("[LLM] ✓ OpenAI")
            return
        }
        
        backend = .none
        print("[LLM] Using basic analysis (no AI)")
    }
    
    private func checkLMStudio() async -> String? {
        guard let url = URL(string: "\(Self.lmStudioURL)/v1/models") else { return nil }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]],
               let firstModel = models.first,
               let modelId = firstModel["id"] as? String {
                return modelId
            }
        } catch {
            // LM Studio not running
        }
        
        return nil
    }
    
    private func checkOpenAI() -> Bool {
        // Check for OpenAI API key in environment
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty {
            return true
        }
        return false
    }
    
    // MARK: - LLM Calls
    
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
          "categories": {"dark": 0.2, "happy": 0.6}
        }
        """
        
        let content = try await sendChatRequest(prompt: prompt, maxTokens: 800)
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
        
        let content = try await sendChatRequest(prompt: prompt, maxTokens: 300)
        
        // Parse JSON
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
        switch backend {
        case .none:
            throw LLMClientError.notAvailable
            
        case .lmStudio(let model):
            return try await sendLMStudioRequest(prompt: prompt, model: model, maxTokens: maxTokens)
            
        case .openAI:
            return try await sendOpenAIRequest(prompt: prompt, maxTokens: maxTokens)
        }
    }
    
    private func sendLMStudioRequest(prompt: String, model: String, maxTokens: Int) async throws -> String {
        guard let url = URL(string: "\(Self.lmStudioURL)/v1/chat/completions") else {
            throw LLMClientError.requestFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = Self.lmStudioTimeout
        
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMClientError.requestFailed("LM Studio returned error")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        
        throw LLMClientError.invalidResponse("Invalid LM Studio response")
    }
    
    private func sendOpenAIRequest(prompt: String, maxTokens: Int) async throws -> String {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            throw LLMClientError.notAvailable
        }
        
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw LLMClientError.requestFailed("Invalid URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        
        let body: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [["role": "user", "content": prompt]],
            "max_tokens": maxTokens
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMClientError.requestFailed("OpenAI returned error")
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        
        throw LLMClientError.invalidResponse("Invalid OpenAI response")
    }
    
    // MARK: - Response Parsing
    
    private func parseAnalysisResponse(_ content: String) throws -> SongAnalysis {
        // Find JSON in response
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}") else {
            throw LLMClientError.invalidResponse("No JSON found")
        }
        
        let jsonStr = String(content[start...end])
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMClientError.invalidResponse("Invalid JSON")
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
            cached: false
        )
    }
    
    // MARK: - Basic Fallback Analysis
    
    private func basicAnalysis(lyrics: String, artist: String, title: String) -> SongAnalysis {
        let text = (title + " " + lyrics).lowercased()
        
        // Extract keywords (basic word frequency)
        let words = text.components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }
        
        var wordCounts: [String: Int] = [:]
        for word in words {
            wordCounts[word, default: 0] += 1
        }
        let keywords = wordCounts.sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }
        
        // Basic category detection
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
        
        // Calculate energy/valence from categories
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
        
        if let lyrics = lyrics {
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
    
    // MARK: - Cache
    
    private func loadCache(from file: URL) -> SongAnalysis? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        return SongAnalysis(
            keywords: json["keywords"] as? [String] ?? [],
            themes: json["themes"] as? [String] ?? [],
            visualAdjectives: json["visual_adjectives"] as? [String] ?? [],
            refrainLines: json["refrain_lines"] as? [String] ?? [],
            tempo: json["tempo"] as? String ?? "medium",
            mood: json["mood"] as? String ?? "neutral",
            energy: json["energy"] as? Double ?? 0.5,
            valence: json["valence"] as? Double ?? 0.0,
            categories: json["categories"] as? [String: Double] ?? [:],
            cached: true
        )
    }
    
    private func saveCache(_ result: SongAnalysis, to file: URL) {
        let json: [String: Any] = [
            "keywords": result.keywords,
            "themes": result.themes,
            "visual_adjectives": result.visualAdjectives,
            "refrain_lines": result.refrainLines,
            "tempo": result.tempo,
            "mood": result.mood,
            "energy": result.energy,
            "valence": result.valence,
            "categories": result.categories
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: file)
        }
    }
    
    // MARK: - Helpers
    
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
}

// MARK: - Extensions

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
            cached: cached
        )
    }
}

extension String {
    func contains(anyOf words: [String]) -> Bool {
        words.contains { self.contains($0) }
    }
}

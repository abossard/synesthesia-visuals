// AIModule - Song categorization with energy/valence scoring
// Following A Philosophy of Software Design: deep module hiding complexity

import Foundation

/// AI module - analyzes songs for mood, energy, themes
///
/// Deep module interface:
/// - `start()` / `stop()` - lifecycle (checks LLM availability)
/// - `analyze(track:lyrics:)` - full song analysis
/// - `categorize(track:lyrics:)` - just categories
///
/// Hides: LLM backend selection, fallback logic, caching, prompt engineering
public actor AIModule: Module {
    
    // MARK: - State
    
    public private(set) var isStarted: Bool = false
    private var lastAnalysis: SongAnalysis?
    private var lastCategories: SongCategories?
    
    // Adapters
    private let llmClient: LLMClient
    
    // MARK: - Init
    
    public init(llmClient: LLMClient? = nil) {
        self.llmClient = llmClient ?? LLMClient()
    }
    
    // MARK: - Module Protocol
    
    public func start() async throws {
        guard !isStarted else { throw ModuleError.alreadyStarted }
        
        // Check LLM availability
        await llmClient.start()
        
        isStarted = true
    }
    
    public func stop() async {
        isStarted = false
        lastAnalysis = nil
        lastCategories = nil
    }
    
    public func getStatus() -> ModuleStatus {
        var status = ModuleStatus([
            "started": .bool(isStarted),
            "backend": .string("llm")
        ])

        if let analysis = lastAnalysis {
            status["last_mood"] = .string(analysis.mood)
            status["last_energy"] = .double(analysis.energy)
            status["last_valence"] = .double(analysis.valence)
            status["keywords_count"] = .int(analysis.keywords.count)
        }

        return status
    }
    
    // MARK: - Public API
    
    /// Check if LLM is available
    public var isLLMAvailable: Bool {
        get async { await llmClient.isAvailable }
    }
    
    /// Get backend info string
    public var backendInfo: String {
        get async { await llmClient.backendInfo }
    }
    
    /// Full song analysis (keywords, themes, energy, valence, categories)
    public func analyze(track: Track, lyrics: String) async -> SongAnalysis {
        do {
            let analysis = try await llmClient.analyzeSong(
                lyrics: lyrics,
                artist: track.artist,
                title: track.title,
                album: track.album
            )
            
            lastAnalysis = analysis
            return analysis
            
        } catch {
            // Return basic analysis
            let basic = SongAnalysis(mood: "unknown", energy: 0.5, valence: 0.0)
            lastAnalysis = basic
            return basic
        }
    }
    
    /// Just categorize (lighter weight than full analysis)
    /// Also sets a basic analysis with energy/valence estimates
    public func categorize(track: Track, lyrics: String?) async -> SongCategories {
        let categories = await llmClient.categorize(
            artist: track.artist,
            title: track.title,
            lyrics: lyrics
        )
        
        lastCategories = categories
        
        // Create basic analysis from categories
        // This ensures we always have SOME analysis for shader/image matching
        let mood = categories.primaryMood.isEmpty ? "unknown" : categories.primaryMood
        let energy = categories.estimatedEnergy
        let valence = categories.estimatedValence
        
        lastAnalysis = SongAnalysis(
            mood: mood,
            energy: energy,
            valence: valence,
            categories: categories.scores
        )
        print("[AI] Categorized: \(track.title) → mood=\(mood), energy=\(String(format: "%.2f", energy)), valence=\(String(format: "%.2f", valence))")
        
        return categories
    }
    
    /// Get last analysis result
    public var currentAnalysis: SongAnalysis? {
        lastAnalysis
    }
    
    /// Get last categories result
    public var currentCategories: SongCategories? {
        lastCategories
    }
}

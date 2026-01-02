// ShadersModule - Module wrapper for shader matching
// Following A Philosophy of Software Design: deep module hiding complexity

import Foundation

/// Shaders module - provides shader matching and selection
///
/// Deep module interface:
/// - `start()` / `stop()` - lifecycle
/// - `match(energy:valence:)` - feature-based matching
/// - `matchByMood(_:energy:)` - mood keyword matching
/// - `search(query:)` - text search
/// - `selectForSong(categories:energy:valence:)` - select with usage tracking
///
/// Hides: Shader loading, indexing, scoring, usage tracking
public actor ShadersModule: Module {
    
    // MARK: - State
    
    public private(set) var isStarted: Bool = false
    
    private let matcher: ShaderMatcher
    private var shadersDir: URL?
    
    // Usage tracking for variety
    private var usageCounts: [String: Int] = [:]
    private var lastSelected: String?
    private let usagePenalty: Double = 0.15
    
    // MARK: - Init
    
    public init(matcher: ShaderMatcher = ShaderMatcher()) {
        self.matcher = matcher
    }
    
    // MARK: - Module Protocol
    
    public func start() async throws {
        guard !isStarted else { throw ModuleError.alreadyStarted }
        isStarted = true
        print("[Shaders] Started")
    }
    
    public func stop() async {
        isStarted = false
        print("[Shaders] Stopped")
    }
    
    public func getStatus() -> [String: Any] {
        [
            "started": isStarted,
            "usage_count": usageCounts.values.reduce(0, +),
            "unique_used": usageCounts.count,
            "last_selected": lastSelected ?? "none"
        ]
    }
    
    // MARK: - Public API
    
    /// Load shaders from directory
    ///
    /// - Parameter directory: Path to shaders directory (containing isf/ and glsl/ subdirs)
    /// - Returns: Number of shaders loaded
    @discardableResult
    public func loadShaders(from directory: URL) async -> Int {
        shadersDir = directory
        return await matcher.loadShaders(from: directory)
    }
    
    /// Match shaders to energy and valence values
    ///
    /// - Parameters:
    ///   - energy: Energy level 0.0-1.0
    ///   - valence: Mood valence -1.0 to 1.0
    ///   - topK: Number of matches to return
    /// - Returns: Array of ShaderMatchResult sorted by score
    public func match(energy: Double, valence: Double, topK: Int = 5) async -> [ShaderMatchResult] {
        await matcher.match(energy: energy, valence: valence, topK: topK)
    }
    
    /// Match shaders by mood keyword
    ///
    /// - Parameters:
    ///   - mood: Mood keyword (energetic, calm, dark, bright, etc.)
    ///   - energy: Energy level 0.0-1.0
    ///   - topK: Number of matches to return
    /// - Returns: Array of ShaderMatchResult sorted by score
    public func matchByMood(_ mood: String, energy: Double = 0.5, topK: Int = 5) async -> [ShaderMatchResult] {
        await matcher.matchByMood(mood, energy: energy, topK: topK)
    }
    
    /// Text search across shaders
    ///
    /// - Parameters:
    ///   - query: Search query
    ///   - topK: Number of results to return
    /// - Returns: Array of ShaderMatchResult sorted by relevance
    public func search(query: String, topK: Int = 10) async -> [ShaderMatchResult] {
        await matcher.search(query: query, topK: topK)
    }
    
    /// Select best shader for a song with usage tracking
    ///
    /// Applies usage penalty for variety and tracks selection.
    ///
    /// - Parameters:
    ///   - categories: Song categories with scores
    ///   - energy: Energy level 0.0-1.0
    ///   - valence: Mood valence -1.0 to 1.0
    ///   - excludeLast: Whether to exclude last selected shader
    /// - Returns: Best matching shader or nil
    public func selectForSong(
        categories: SongCategories? = nil,
        energy: Double = 0.5,
        valence: Double = 0.0,
        excludeLast: Bool = true
    ) async -> ShaderMatchResult? {
        // Get candidates
        let candidates = await matcher.match(energy: energy, valence: valence, topK: 10)
        
        guard !candidates.isEmpty else { return nil }
        
        // Score with usage penalty
        var scored: [(ShaderMatchResult, Double)] = []
        
        for candidate in candidates {
            // Skip last selected if requested
            if excludeLast && candidate.name == lastSelected {
                continue
            }
            
            // Apply usage penalty
            let usage = usageCounts[candidate.name] ?? 0
            let penalty = Double(usage) * usagePenalty
            let adjustedScore = candidate.score + penalty
            
            scored.append((candidate, adjustedScore))
        }
        
        // Fallback if all excluded
        if scored.isEmpty, let first = candidates.first {
            scored.append((first, first.score))
        }
        
        // Sort and select best
        scored.sort { $0.1 < $1.1 }
        
        guard let best = scored.first else { return nil }
        
        // Record usage
        usageCounts[best.0.name, default: 0] += 1
        lastSelected = best.0.name
        
        print("[Shaders] Selected: \(best.0.name) (score=\(String(format: "%.2f", best.1)))")
        
        return best.0
    }
    
    /// Get random shader
    public func randomShader() async -> ShaderInfo? {
        let shader = await matcher.randomShader()
        if let shader = shader {
            usageCounts[shader.name, default: 0] += 1
            lastSelected = shader.name
        }
        return shader
    }
    
    /// Reset usage tracking (call at session start)
    public func resetUsage() {
        usageCounts.removeAll()
        lastSelected = nil
        print("[Shaders] Usage counts reset")
    }
    
    /// Get all loaded shaders
    public var allShaders: [ShaderInfo] {
        get async { await matcher.allShaders }
    }
    
    /// Get shader count
    public var shaderCount: Int {
        get async { await matcher.count }
    }
    
    /// Get usage statistics
    public var usageStats: [String: Any] {
        [
            "total_selections": usageCounts.values.reduce(0, +),
            "unique_used": usageCounts.count,
            "last_selected": lastSelected ?? "none",
            "top_used": Array(usageCounts.sorted { $0.value > $1.value }.prefix(5))
        ]
    }
}

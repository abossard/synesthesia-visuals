// ShaderMatcher - Load, index, and match shaders
// Following A Philosophy of Software Design: deep module hiding complexity

import Foundation

// MARK: - Shader Analysis Data

/// Shader analysis result from JSON file
public struct ShaderAnalysis: Sendable, Codable {
    public let shaderName: String
    public let shaderType: String
    public let features: ShaderFeatures
    public let mood: String
    public let colors: [String]
    public let effects: [String]
    public let description: String
    
    public struct ShaderFeatures: Sendable, Codable {
        public let energyScore: Double
        public let moodValence: Double
        public let colorWarmth: Double
        public let motionSpeed: Double
        public let geometricScore: Double
        public let visualDensity: Double
        
        private enum CodingKeys: String, CodingKey {
            case energyScore = "energy_score"
            case moodValence = "mood_valence"
            case colorWarmth = "color_warmth"
            case motionSpeed = "motion_speed"
            case geometricScore = "geometric_score"
            case visualDensity = "visual_density"
        }
        
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
        
        /// Convert to feature vector for distance calculations
        public func toVector() -> [Double] {
            [energyScore, moodValence, colorWarmth, motionSpeed, geometricScore, visualDensity]
        }
    }
    
    public init(
        shaderName: String,
        shaderType: String = "isf",
        features: ShaderFeatures = ShaderFeatures(),
        mood: String = "unknown",
        colors: [String] = [],
        effects: [String] = [],
        description: String = ""
    ) {
        self.shaderName = shaderName
        self.shaderType = shaderType
        self.features = features
        self.mood = mood
        self.colors = colors
        self.effects = effects
        self.description = description
    }
}

// MARK: - ShaderMatcher

/// Deep module for loading, indexing, and matching shaders
///
/// Simple interface:
/// - `loadShaders(from:)` - Load all analyzed shaders from directory
/// - `match(energy:valence:)` - Find best matching shader
/// - `matchByMood(_:energy:)` - Find shaders by mood keyword
/// - `search(query:)` - Text search across shaders
///
/// Hides: Directory scanning, JSON parsing, feature extraction, scoring
public actor ShaderMatcher {
    
    // MARK: - State
    
    private var shaders: [String: ShaderInfo] = [:]
    private var analyses: [String: ShaderAnalysis] = [:]
    private var shadersDir: URL?
    
    // Feature weights for matching
    private let featureWeights: [Double] = [
        1.5,  // energy_score (most important)
        1.3,  // mood_valence
        0.8,  // color_warmth
        1.0,  // motion_speed
        0.6,  // geometric_score
        0.8   // visual_density
    ]
    
    // Mood to feature mapping
    private let moodMap: [String: [Double]] = [
        "energetic": [0.9, 0.5, 0.6, 0.8, 0.5, 0.7],
        "calm": [0.2, 0.3, 0.4, 0.2, 0.4, 0.3],
        "dark": [0.6, -0.6, 0.3, 0.5, 0.4, 0.6],
        "bright": [0.6, 0.7, 0.7, 0.5, 0.5, 0.5],
        "psychedelic": [0.7, 0.2, 0.5, 0.7, 0.3, 0.8],
        "melancholic": [0.3, -0.5, 0.3, 0.3, 0.4, 0.4],
        "aggressive": [0.95, -0.3, 0.4, 0.9, 0.6, 0.8],
        "dreamy": [0.3, 0.4, 0.5, 0.4, 0.3, 0.5],
        "mysterious": [0.5, -0.2, 0.4, 0.4, 0.5, 0.5],
        "happy": [0.7, 0.8, 0.7, 0.6, 0.4, 0.5],
        "sad": [0.3, -0.7, 0.3, 0.2, 0.4, 0.4]
    ]
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - Public API
    
    /// Get all unique folder names from loaded shaders
    public var availableFolders: [String] {
        Array(Set(shaders.values.map { $0.folder })).sorted()
    }
    
    /// Load all analyzed shaders from a directory
    ///
    /// Scans for .analysis.json files and loads shader metadata.
    /// Supports both ISF (.fs) and GLSL (.txt) shaders.
    ///
    /// - Parameter directory: Path to shaders directory (containing isf/ and glsl/ subdirs)
    /// - Returns: Number of shaders loaded
    @discardableResult
    public func loadShaders(from directory: URL) async -> Int {
        shadersDir = directory
        shaders.removeAll()
        analyses.removeAll()
        
        let fileManager = FileManager.default
        
        // Scan both isf/ and glsl/ subdirectories
        let subDirs = ["isf", "glsl"]
        
        for subDir in subDirs {
            let subDirURL = directory.appendingPathComponent(subDir)
            guard fileManager.fileExists(atPath: subDirURL.path) else { continue }
            
            let analysisFiles = analysisFiles(in: subDirURL)

            for fileURL in analysisFiles {
                guard fileURL.pathExtension == "json",
                      fileURL.lastPathComponent.hasSuffix(".analysis.json") else {
                    continue
                }
                
                do {
                    let data = try Data(contentsOf: fileURL)
                    let analysis = try JSONDecoder().decode(ShaderAnalysis.self, from: data)
                    
                    // Use bare shader name (matches metallib function names)
                    let shaderName = fileURL.lastPathComponent
                        .replacingOccurrences(of: ".analysis.json", with: "")
                    
                    // Determine shader file path
                    let ext = subDir == "isf" ? "fs" : "txt"
                    let shaderPath = fileURL.deletingLastPathComponent()
                        .appendingPathComponent("\(shaderName).\(ext)")
                    
                    // Create ShaderInfo with bare name
                    let info = ShaderInfo(
                        name: shaderName,  // Bare name: matches metallib function names
                        path: shaderPath.path,
                        folder: subDir,  // Folder for filtering: "isf", "glsl", etc.
                        energyScore: analysis.features.energyScore,
                        moodValence: analysis.features.moodValence,
                        colorWarmth: analysis.features.colorWarmth,
                        motionSpeed: analysis.features.motionSpeed,
                        mood: analysis.mood,
                        colors: analysis.colors,
                        effects: analysis.effects,
                        rating: .normal
                    )
                    
                    shaders[shaderName] = info
                    analyses[shaderName] = analysis
                    
                } catch {
                    // Skip invalid files
                    continue
                }
            }
        }
        
        print("[ShaderMatcher] Loaded \(shaders.count) shaders with analysis")
        return shaders.count
    }

    /// Collect analysis files synchronously to avoid async iteration over DirectoryEnumerator
    private func analysisFiles(in directory: URL) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            files.append(fileURL)
        }
        return files
    }
    
    /// Load all shader files from directory (analysis.json optional)
    ///
    /// Dynamically scans all subdirectories for .txt shader files.
    /// Loads shaders with or without analysis.json.
    ///
    /// - Parameter directory: Path to shaders directory (containing subdirs like glsl/, masks/)
    /// - Returns: Number of shaders loaded
    @discardableResult
    public func loadAllShaderFiles(from directory: URL) async -> Int {
        shadersDir = directory
        shaders.removeAll()
        analyses.removeAll()
        
        let fileManager = FileManager.default
        
        // Dynamically discover all subdirectories
        guard let subDirs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("[ShaderMatcher] Could not list directory: \(directory.path)")
            return 0
        }
        
        for subDirURL in subDirs {
            // Check if it's a directory
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: subDirURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            
            let folderName = subDirURL.lastPathComponent
            
            // Find all .txt shader files in this folder
            guard let contents = try? fileManager.contentsOfDirectory(
                at: subDirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for fileURL in contents {
                guard fileURL.pathExtension == "txt" else { continue }
                
                // Use bare shader name (matches metallib function names)
                let shaderName = fileURL.deletingPathExtension().lastPathComponent
                
                // Try to load analysis if it exists (optional)
                let analysisURL = fileURL.deletingPathExtension().appendingPathExtension("analysis.json")
                var loadedAnalysis: ShaderAnalysis? = nil
                var energyScore = 0.5
                var moodValence = 0.0
                var colorWarmth = 0.5
                var motionSpeed = 0.5
                var mood = "unknown"
                var colors: [String] = []
                var effects: [String] = []
                
                if fileManager.fileExists(atPath: analysisURL.path),
                   let data = try? Data(contentsOf: analysisURL),
                   let analysis = try? JSONDecoder().decode(ShaderAnalysis.self, from: data) {
                    loadedAnalysis = analysis
                    energyScore = analysis.features.energyScore
                    moodValence = analysis.features.moodValence
                    colorWarmth = analysis.features.colorWarmth
                    motionSpeed = analysis.features.motionSpeed
                    mood = analysis.mood
                    colors = analysis.colors
                    effects = analysis.effects
                }
                
                // Create ShaderInfo with bare name (matches metallib) and folder for filtering
                let info = ShaderInfo(
                    name: shaderName,  // Bare name: "Electriclava" (matches fragment_Electriclava in metallib)
                    path: fileURL.path,
                    folder: folderName,  // Folder for filtering: "glsl" or "masks"
                    energyScore: energyScore,
                    moodValence: moodValence,
                    colorWarmth: colorWarmth,
                    motionSpeed: motionSpeed,
                    mood: mood,
                    colors: colors,
                    effects: effects,
                    rating: .normal  // Rating no longer used for filtering
                )
                
                // Use bare name as key (avoids duplicates across folders with same name)
                // If same shader name exists in multiple folders, last one wins
                shaders[shaderName] = info
                if let analysis = loadedAnalysis {
                    analyses[shaderName] = analysis
                }
            }
        }
        
        print("[ShaderMatcher] Loaded \(shaders.count) shaders from \(subDirs.count) folders")
        return shaders.count
    }
    
    /// Match shaders to energy and valence values
    ///
    /// - Parameters:
    ///   - energy: Energy level 0.0-1.0
    ///   - valence: Mood valence -1.0 to 1.0
    ///   - topK: Number of matches to return
    /// - Returns: Array of ShaderMatchResult sorted by score (lower is better)
    public func match(energy: Double, valence: Double, topK: Int = 5) -> [ShaderMatchResult] {
        let target = buildShaderTargetVector(energy: energy, valence: valence)
        return matchToVector(target, topK: topK)
    }
    
    /// Match shaders by mood keyword
    ///
    /// - Parameters:
    ///   - mood: Mood keyword (energetic, calm, dark, bright, etc.)
    ///   - energy: Energy level 0.0-1.0
    ///   - topK: Number of matches to return
    /// - Returns: Array of ShaderMatchResult sorted by score
    public func matchByMood(_ mood: String, energy: Double = 0.5, topK: Int = 5) -> [ShaderMatchResult] {
        var target = moodMap[mood.lowercased()] ?? [0.5, 0.0, 0.5, 0.5, 0.5, 0.5]
        
        // Adjust for energy
        target[0] = energy
        target[3] = target[3] * 0.5 + energy * 0.5  // Motion follows energy
        
        return matchToVector(target, topK: topK)
    }
    
    /// Text search across shader names, moods, colors, effects
    ///
    /// - Parameters:
    ///   - query: Search query
    ///   - topK: Number of results to return
    /// - Returns: Array of ShaderMatchResult sorted by relevance
    public func search(query: String, topK: Int = 10) -> [ShaderMatchResult] {
        let queryLower = query.lowercased()
        let queryWords = queryLower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        var scored: [(ShaderInfo, Double)] = []
        
        for (name, info) in shaders {
            var score = 0.0
            let analysis = analyses[name]
            
            // Build searchable text
            var searchableText = name.lowercased() + " " + info.mood.lowercased()
            searchableText += " " + info.colors.joined(separator: " ").lowercased()
            searchableText += " " + info.effects.joined(separator: " ").lowercased()
            if let desc = analysis?.description {
                searchableText += " " + desc.lowercased()
            }
            
            for word in queryWords {
                if searchableText.contains(word) {
                    score += 1.0
                    
                    // Bonus for name match
                    if name.lowercased().contains(word) {
                        score += 3.0
                    }
                    
                    // Bonus for mood match
                    if info.mood.lowercased() == word {
                        score += 2.0
                    }
                }
            }
            
            if score > 0 {
                // Convert to distance (lower is better)
                scored.append((info, 1.0 / (1.0 + score)))
            }
        }
        
        scored.sort { $0.1 < $1.1 }
        
        return scored.prefix(topK).map { info, score in
            ShaderMatchResult(
                name: info.name,
                path: info.path,
                score: score,
                energyScore: info.energyScore,
                moodValence: info.moodValence,
                mood: info.mood
            )
        }
    }
    
    /// Get all loaded shaders
    public var allShaders: [ShaderInfo] {
        Array(shaders.values)
    }
    
    /// Get shader by name
    public func getShader(name: String) -> ShaderInfo? {
        shaders[name]
    }
    
    /// Get shader count
    public var count: Int {
        shaders.count
    }
    
    /// Get random shader
    public func randomShader() -> ShaderInfo? {
        shaders.values.randomElement()
    }

    // MARK: - Phase-Based Matching

    /// Match shaders with phase as a soft factor
    ///
    /// Phase matching adds a bonus to shaders that match the target phase,
    /// but does not filter out non-matching shaders. This allows for variety
    /// while still preferring phase-appropriate visuals.
    ///
    /// - Parameters:
    ///   - energy: Energy level 0.0-1.0
    ///   - valence: Mood valence -1.0 to 1.0
    ///   - phase: Optional DJ set phase for soft bonus
    ///   - phaseWeight: How much to weight phase match (default 0.2)
    ///   - topK: Number of matches to return
    /// - Returns: Array of ShaderMatchResult sorted by score (lower is better)
    public func matchWithPhase(
        energy: Double,
        valence: Double,
        phase: Phase?,
        phaseWeight: Double = 0.2,
        topK: Int = 5
    ) -> [ShaderMatchResult] {
        guard !shaders.isEmpty else { return [] }

        let target = buildShaderTargetVector(energy: energy, valence: valence)

        var scored: [(ShaderInfo, Double)] = []

        for info in shaders.values {
            let vector = [
                info.energyScore,
                info.moodValence,
                info.colorWarmth,
                info.motionSpeed,
                0.5,  // geometric (not stored in ShaderInfo)
                0.5   // density (not stored in ShaderInfo)
            ]

            var distance = weightedDistance(target, vector)

            // Apply phase bonus (reduce distance for matching phases)
            if let targetPhase = phase,
               let shaderPhases = info.phases,
               shaderPhases.contains(targetPhase) {
                distance *= (1.0 - phaseWeight)  // e.g., 0.8 multiplier for 0.2 weight
            }

            scored.append((info, distance))
        }

        scored.sort { $0.1 < $1.1 }

        return scored.prefix(topK).map { info, score in
            ShaderMatchResult(
                name: info.name,
                path: info.path,
                score: score,
                energyScore: info.energyScore,
                moodValence: info.moodValence,
                mood: info.mood
            )
        }
    }

    /// Strict phase matching: only return shaders tagged with the target phase.
    public func matchForPhase(
        energy: Double,
        valence: Double,
        phase: Phase,
        topK: Int = 5
    ) -> [ShaderMatchResult] {
        let filtered = shaders.values.filter { $0.phases?.contains(phase) ?? false }
        guard !filtered.isEmpty else { return [] }

        let target = buildShaderTargetVector(energy: energy, valence: valence)
        var scored: [(ShaderInfo, Double)] = []

        for info in filtered {
            let vector = [
                info.energyScore,
                info.moodValence,
                info.colorWarmth,
                info.motionSpeed,
                0.5,
                0.5
            ]
            let distance = weightedDistance(target, vector)
            scored.append((info, distance))
        }

        scored.sort { $0.1 < $1.1 }

        return scored.prefix(topK).map { info, score in
            ShaderMatchResult(
                name: info.name,
                path: info.path,
                score: score,
                energyScore: info.energyScore,
                moodValence: info.moodValence,
                mood: info.mood
            )
        }
    }

    /// Get all shaders that match a specific phase
    ///
    /// - Parameter phase: The phase to filter by
    /// - Returns: Array of ShaderInfo for shaders in the given phase
    public func shadersForPhase(_ phase: Phase) -> [ShaderInfo] {
        shaders.values.filter { shader in
            shader.phases?.contains(phase) ?? false
        }
    }

    // MARK: - Private
    
    private func matchToVector(_ target: [Double], topK: Int) -> [ShaderMatchResult] {
        guard !shaders.isEmpty else { return [] }
        
        var scored: [(ShaderInfo, Double)] = []
        
        for info in shaders.values {
            let vector = [
                info.energyScore,
                info.moodValence,
                info.colorWarmth,
                info.motionSpeed,
                0.5,  // geometric (not stored in ShaderInfo)
                0.5   // density (not stored in ShaderInfo)
            ]
            
            let distance = weightedDistance(target, vector)
            scored.append((info, distance))
        }
        
        scored.sort { $0.1 < $1.1 }
        
        return scored.prefix(topK).map { info, score in
            ShaderMatchResult(
                name: info.name,
                path: info.path,
                score: score,
                energyScore: info.energyScore,
                moodValence: info.moodValence,
                mood: info.mood
            )
        }
    }
    
    private func weightedDistance(_ v1: [Double], _ v2: [Double]) -> Double {
        var total = 0.0
        for i in 0..<min(v1.count, v2.count, featureWeights.count) {
            let diff = v1[i] - v2[i]
            total += featureWeights[i] * (diff * diff)
        }
        return sqrt(total)
    }
    
    // MARK: - Vector Similarity Search
    
    /// Match shaders using cosine similarity (vector search)
    ///
    /// Unlike weighted Euclidean distance, cosine similarity measures
    /// angle between vectors, making it robust to magnitude differences.
    /// Returns results with similarity score 0.0-1.0 (higher is better match).
    ///
    /// - Parameters:
    ///   - query: Query feature vector [energy, valence, warmth, motion, geometric, density]
    ///   - topK: Number of results to return
    /// - Returns: Array of ShaderMatchResult sorted by similarity (descending)
    public func matchBySimilarity(query: [Double], topK: Int = 5) -> [ShaderMatchResult] {
        guard !shaders.isEmpty, query.count >= 4 else { return [] }
        
        // Normalize query vector
        let queryNorm = normalize(query)
        
        var scored: [(ShaderInfo, Double)] = []
        
        for info in shaders.values {
            let vector = [
                info.energyScore,
                info.moodValence,
                info.colorWarmth,
                info.motionSpeed,
                0.5,  // geometric
                0.5   // density
            ]
            
            let vectorNorm = normalize(vector)
            let similarity = cosineSimilarity(queryNorm, vectorNorm)
            scored.append((info, similarity))
        }
        
        // Sort by similarity descending (higher is better)
        scored.sort { $0.1 > $1.1 }
        
        return scored.prefix(topK).map { info, similarity in
            ShaderMatchResult(
                name: info.name,
                path: info.path,
                score: 1.0 - similarity,  // Convert to distance for consistency
                energyScore: info.energyScore,
                moodValence: info.moodValence,
                mood: info.mood
            )
        }
    }
    
    /// Find similar shaders to a given shader by name
    ///
    /// Uses the shader's feature vector to find other shaders with similar characteristics.
    ///
    /// - Parameters:
    ///   - shaderName: Name of the reference shader
    ///   - topK: Number of similar shaders to return
    /// - Returns: Array of similar shaders (excluding the reference)
    public func findSimilar(to shaderName: String, topK: Int = 5) -> [ShaderMatchResult] {
        guard let reference = shaders[shaderName] else { return [] }
        
        let query = [
            reference.energyScore,
            reference.moodValence,
            reference.colorWarmth,
            reference.motionSpeed,
            0.5,
            0.5
        ]
        
        // Get topK+1 to exclude self
        var results = matchBySimilarity(query: query, topK: topK + 1)
        results.removeAll { $0.name == shaderName }
        return Array(results.prefix(topK))
    }
    
    /// Build embedding text for a shader (for future semantic search)
    ///
    /// Creates a text representation suitable for embedding models.
    public func buildEmbeddingText(for shaderName: String) -> String? {
        guard let info = shaders[shaderName],
              let analysis = analyses[shaderName] else { return nil }
        
        var parts: [String] = []
        parts.append("shader: \(info.name)")
        parts.append("mood: \(info.mood)")
        parts.append("colors: \(info.colors.joined(separator: ", "))")
        parts.append("effects: \(info.effects.joined(separator: ", "))")
        if !analysis.description.isEmpty {
            parts.append("description: \(analysis.description)")
        }
        
        return parts.joined(separator: " | ")
    }
    
    // MARK: - Vector Math Helpers
    
    /// Normalize a vector to unit length
    private func normalize(_ v: [Double]) -> [Double] {
        let magnitude = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard magnitude > 0 else { return v }
        return v.map { $0 / magnitude }
    }
    
    /// Compute cosine similarity between two normalized vectors
    private func cosineSimilarity(_ v1: [Double], _ v2: [Double]) -> Double {
        guard v1.count == v2.count else { return 0 }
        var dotProduct = 0.0
        for i in 0..<v1.count {
            dotProduct += v1[i] * v2[i]
        }
        // Clamp to [-1, 1] to handle floating point errors
        return max(-1.0, min(1.0, dotProduct))
    }
}

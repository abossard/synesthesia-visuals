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
            
            // Find all .analysis.json files
            guard let enumerator = fileManager.enumerator(
                at: subDirURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "json",
                      fileURL.lastPathComponent.hasSuffix(".analysis.json") else {
                    continue
                }
                
                do {
                    let data = try Data(contentsOf: fileURL)
                    let analysis = try JSONDecoder().decode(ShaderAnalysis.self, from: data)
                    
                    // Build prefixed name: "isf/shadername" or "glsl/shadername"
                    let relativePath = fileURL.deletingLastPathComponent()
                        .path
                        .replacingOccurrences(of: subDirURL.path, with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    
                    let shaderName = fileURL.lastPathComponent
                        .replacingOccurrences(of: ".analysis.json", with: "")
                    
                    let prefixedName: String
                    if relativePath.isEmpty {
                        prefixedName = "\(subDir)/\(shaderName)"
                    } else {
                        prefixedName = "\(subDir)/\(relativePath)/\(shaderName)"
                    }
                    
                    // Determine shader file path
                    let ext = subDir == "isf" ? "fs" : "txt"
                    let shaderPath = fileURL.deletingLastPathComponent()
                        .appendingPathComponent("\(shaderName).\(ext)")
                    
                    // Create ShaderInfo
                    let info = ShaderInfo(
                        name: prefixedName,
                        path: shaderPath.path,
                        energyScore: analysis.features.energyScore,
                        moodValence: analysis.features.moodValence,
                        colorWarmth: analysis.features.colorWarmth,
                        motionSpeed: analysis.features.motionSpeed,
                        mood: analysis.mood,
                        colors: analysis.colors,
                        effects: analysis.effects,
                        rating: .normal
                    )
                    
                    shaders[prefixedName] = info
                    analyses[prefixedName] = analysis
                    
                } catch {
                    // Skip invalid files
                    continue
                }
            }
        }
        
        print("[ShaderMatcher] Loaded \(shaders.count) shaders")
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
}

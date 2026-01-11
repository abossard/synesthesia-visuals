// ShaderRepository.swift - Pure functions for shader loading, saving, search, and matching
// Single source of truth for shader management

import Foundation

// MARK: - Shaders

/// Pure functions for shader management
/// All functions are stateless - caller manages caching
/// Usage: `Shaders.loadAll(...)`, `Shaders.search(...)`, `Shaders.match(...)`
public enum Shaders {
    
    // MARK: - Loading
    
    /// Load all shaders from a directory and metallib
    /// - Parameters:
    ///   - shadersDir: Directory containing shader folders (glsl/, masks/)
    ///   - metallibURL: URL to compiled metallib (optional, enriches with Metal function names)
    /// - Returns: Array of Shader entities
    public static func loadAll(shadersDir: URL, metallibURL: URL? = nil) throws -> [Shader] {
        let fileManager = FileManager.default
        
        // Parse metallib for renderable shader names
        var metallibNames: Set<String> = []
        if let url = metallibURL {
            let names = try? MetallibParser.parseMetallib(at: url)
            metallibNames = Set(names ?? [])
        }
        
        var shaders: [Shader] = []
        
        // Scan subdirectories
        guard let subDirs = try? fileManager.contentsOfDirectory(
            at: shadersDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for subDirURL in subDirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: subDirURL.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            
            let folderName = subDirURL.lastPathComponent
            
            // Skip non-shader directories
            guard folderName == "glsl" || folderName == "masks" else { continue }
            
            // Find all .txt shader files
            guard let contents = try? fileManager.contentsOfDirectory(
                at: subDirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for fileURL in contents where fileURL.pathExtension == "txt" {
                let name = fileURL.deletingPathExtension().lastPathComponent
                
                // Load analysis if exists
                let analysisURL = fileURL.deletingPathExtension().appendingPathExtension("analysis.json")
                let analysis = loadAnalysis(from: analysisURL)
                
                // Determine Metal function name
                let metalFunctionName = metallibNames.contains(name) ? "fragment_\(name)" : nil
                
                // Determine rating (masks folder = mask rating)
                let rating: ShaderRating = folderName == "masks" ? .mask : .normal
                
                let shader = Shader(
                    name: name,
                    sourceURL: fileURL,
                    folder: folderName,
                    analysis: analysis,
                    metalFunctionName: metalFunctionName,
                    rating: rating
                )
                
                shaders.append(shader)
            }
        }
        
        return shaders.sorted { $0.name < $1.name }
    }
    
    /// Load a single shader by name
    /// - Parameters:
    ///   - name: Shader name (without extension)
    ///   - shadersDir: Directory containing shader folders
    ///   - metallibURL: URL to compiled metallib (optional)
    /// - Returns: Shader if found
    public static func load(name: String, shadersDir: URL, metallibURL: URL? = nil) throws -> Shader? {
        let shaders = try loadAll(shadersDir: shadersDir, metallibURL: metallibURL)
        return shaders.first { $0.name == name }
    }
    
    // MARK: - Saving
    
    /// Save shader analysis to JSON file
    /// - Parameters:
    ///   - analysis: Analysis to save
    ///   - shader: Target shader
    public static func save(analysis: ShaderAnalysis, for shader: Shader) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(analysis)
        try data.write(to: shader.analysisURL)
    }
    
    /// Save screenshot data for a shader
    /// - Parameters:
    ///   - data: PNG image data
    ///   - shader: Target shader
    public static func saveScreenshot(data: Data, for shader: Shader) throws {
        let screenshotURL = shader.sourceURL.deletingPathExtension().appendingPathExtension("png")
        try data.write(to: screenshotURL)
    }
    
    // MARK: - Reading
    
    /// Read shader GLSL source code
    /// - Parameter shader: The shader to read
    /// - Returns: GLSL source string
    public static func readSource(for shader: Shader) throws -> String {
        try String(contentsOf: shader.sourceURL, encoding: .utf8)
    }
    
    /// Read screenshot data
    /// - Parameter shader: The shader
    /// - Returns: PNG data if screenshot exists
    public static func readScreenshot(for shader: Shader) -> Data? {
        guard let url = shader.screenshotURL else { return nil }
        return try? Data(contentsOf: url)
    }
    
    // MARK: - Search
    
    /// Text search across shader names, moods, colors, effects
    /// - Parameters:
    ///   - query: Search query
    ///   - shaders: Array of shaders to search
    /// - Returns: Matching shaders sorted by relevance
    public static func search(query: String, in shaders: [Shader]) -> [Shader] {
        let queryLower = query.lowercased()
        let queryWords = queryLower.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        guard !queryWords.isEmpty else { return shaders }
        
        var scored: [(Shader, Double)] = []
        
        for shader in shaders {
            var score = 0.0
            
            // Build searchable text
            var searchableText = shader.name.lowercased()
            searchableText += " " + shader.mood.lowercased()
            searchableText += " " + shader.colors.joined(separator: " ").lowercased()
            searchableText += " " + shader.effects.joined(separator: " ").lowercased()
            if let desc = shader.analysis?.description {
                searchableText += " " + desc.lowercased()
            }
            
            for word in queryWords {
                if searchableText.contains(word) {
                    score += 1.0
                    
                    // Bonus for name match
                    if shader.name.lowercased().contains(word) {
                        score += 3.0
                    }
                    
                    // Bonus for mood match
                    if shader.mood.lowercased() == word {
                        score += 2.0
                    }
                }
            }
            
            if score > 0 {
                scored.append((shader, score))
            }
        }
        
        // Sort by score descending
        scored.sort { $0.1 > $1.1 }
        return scored.map { $0.0 }
    }
    
    // MARK: - Matching
    
    /// Match shaders to energy and valence values
    /// - Parameters:
    ///   - energy: Energy level 0.0-1.0
    ///   - valence: Mood valence -1.0 to 1.0
    ///   - shaders: Array of shaders to match
    ///   - topK: Number of results
    /// - Returns: Array of ShaderMatchResult sorted by score (lower is better)
    public static func match(
        energy: Double,
        valence: Double,
        in shaders: [Shader],
        topK: Int = 5
    ) -> [ShaderMatchResult] {
        let target = [energy, valence, 0.5, 0.5]  // [energy, valence, warmth, motion]
        return matchToVector(target, in: shaders, topK: topK)
    }
    
    /// Match shaders by mood keyword
    /// - Parameters:
    ///   - mood: Mood keyword
    ///   - energy: Energy level
    ///   - shaders: Array of shaders
    ///   - topK: Number of results
    /// - Returns: Matching shaders
    public static func matchByMood(
        _ mood: String,
        energy: Double = 0.5,
        in shaders: [Shader],
        topK: Int = 5
    ) -> [ShaderMatchResult] {
        let moodMap: [String: [Double]] = [
            "energetic": [0.9, 0.5, 0.6, 0.8],
            "calm": [0.2, 0.3, 0.4, 0.2],
            "dark": [0.6, -0.6, 0.3, 0.5],
            "bright": [0.6, 0.7, 0.7, 0.5],
            "psychedelic": [0.7, 0.2, 0.5, 0.7],
            "aggressive": [0.95, -0.3, 0.4, 0.9],
            "dreamy": [0.3, 0.4, 0.5, 0.4],
            "hypnotic": [0.5, 0.0, 0.5, 0.6]
        ]
        
        var target = moodMap[mood.lowercased()] ?? [0.5, 0.0, 0.5, 0.5]
        target[0] = energy  // Override with provided energy
        
        return matchToVector(target, in: shaders, topK: topK)
    }
    
    /// Match with phase as a soft bonus
    /// - Parameters:
    ///   - energy: Energy level
    ///   - valence: Mood valence
    ///   - phase: Optional DJ phase
    ///   - phaseWeight: Weight for phase matching (0.0-1.0)
    ///   - shaders: Array of shaders
    ///   - topK: Number of results
    /// - Returns: Matching shaders
    public static func matchWithPhase(
        energy: Double,
        valence: Double,
        phase: Phase?,
        phaseWeight: Double = 0.2,
        in shaders: [Shader],
        topK: Int = 5
    ) -> [ShaderMatchResult] {
        let target = [energy, valence, 0.5, 0.5]
        
        var scored: [(Shader, Double)] = []
        
        for shader in shaders {
            let vector = shader.analysis?.featureVector ?? [0.5, 0.0, 0.5, 0.5]
            var distance = weightedDistance(target, vector)
            
            // Apply phase bonus
            if let targetPhase = phase, shader.phases.contains(targetPhase) {
                distance *= (1.0 - phaseWeight)
            }
            
            scored.append((shader, distance))
        }
        
        scored.sort { $0.1 < $1.1 }
        
        return scored.prefix(topK).map { ShaderMatchResult(shader: $0.0, score: $0.1) }
    }
    
    /// Find shaders similar to a given shader
    /// - Parameters:
    ///   - shader: Reference shader
    ///   - shaders: Array to search
    ///   - topK: Number of results
    /// - Returns: Similar shaders (excluding reference)
    public static func findSimilar(
        to shader: Shader,
        in shaders: [Shader],
        topK: Int = 5
    ) -> [ShaderMatchResult] {
        let query = shader.analysis?.featureVector ?? [0.5, 0.0, 0.5, 0.5]
        
        let filtered = shaders.filter { $0.id != shader.id }
        return matchToVector(query, in: filtered, topK: topK)
    }
    
    // MARK: - Filtering
    
    /// Filter shaders by folder
    public static func filter(byFolder folder: String, in shaders: [Shader]) -> [Shader] {
        shaders.filter { $0.folder == folder }
    }
    
    /// Filter shaders by phase
    public static func filter(byPhase phase: Phase, in shaders: [Shader]) -> [Shader] {
        shaders.filter { $0.phases.contains(phase) }
    }
    
    /// Filter shaders by rating
    public static func filter(byRating rating: ShaderRating, in shaders: [Shader]) -> [Shader] {
        shaders.filter { $0.rating == rating }
    }
    
    /// Filter out black/broken shaders
    public static func filterOutBlack(in shaders: [Shader]) -> [Shader] {
        shaders.filter { !$0.isBlack }
    }
    
    /// Filter to only renderable shaders (have Metal function)
    public static func filterRenderable(in shaders: [Shader]) -> [Shader] {
        shaders.filter { $0.isRenderable }
    }
    
    // MARK: - Statistics
    
    /// Get unique folders in shader list
    public static func folders(in shaders: [Shader]) -> [String] {
        Array(Set(shaders.map { $0.folder })).sorted()
    }
    
    /// Get unique moods in shader list
    public static func moods(in shaders: [Shader]) -> [String] {
        Array(Set(shaders.map { $0.mood }.filter { !$0.isEmpty })).sorted()
    }
    
    /// Count shaders by folder
    public static func countByFolder(in shaders: [Shader]) -> [String: Int] {
        Dictionary(grouping: shaders, by: { $0.folder }).mapValues { $0.count }
    }
}

// MARK: - Private Helpers

extension Shaders {
    
    private static func loadAnalysis(from url: URL) -> ShaderAnalysis? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ShaderAnalysis.self, from: data)
    }
    
    private static func matchToVector(_ target: [Double], in shaders: [Shader], topK: Int) -> [ShaderMatchResult] {
        var scored: [(Shader, Double)] = []
        
        for shader in shaders {
            let vector = shader.analysis?.featureVector ?? [0.5, 0.0, 0.5, 0.5]
            let distance = weightedDistance(target, vector)
            scored.append((shader, distance))
        }
        
        scored.sort { $0.1 < $1.1 }
        
        return scored.prefix(topK).map { ShaderMatchResult(shader: $0.0, score: $0.1) }
    }
    
    private static let featureWeights: [Double] = [1.5, 1.3, 0.8, 1.0]  // energy, valence, warmth, motion
    
    private static func weightedDistance(_ v1: [Double], _ v2: [Double]) -> Double {
        var total = 0.0
        for i in 0..<min(v1.count, v2.count, featureWeights.count) {
            let diff = v1[i] - v2[i]
            total += featureWeights[i] * (diff * diff)
        }
        return sqrt(total)
    }
}

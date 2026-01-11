// ShaderStore - Actor wrapper for shader list state
// Uses ShaderRepository module for types and file operations
// Following A Philosophy of Software Design: deep module with simple interface

import Foundation
import ShaderRepository

// MARK: - Shader Store

/// Actor that holds shader state and provides async-safe access.
/// Uses `Shaders` namespace from ShaderRepository module for loading/matching.
/// Combines two sources:
/// - **Metallib**: Authoritative list of renderable shaders (fragment_* functions)
/// - **File System**: Metadata from .analysis.json files, folder info
///
/// Design: The metallib is the source of truth for what can render.
/// File metadata enriches shaders but doesn't add new ones.
public actor ShaderStore {
    
    // MARK: - State
    
    private var shaders: [String: Shader] = [:]
    private var metallibShaderNames: Set<String> = []
    private var shadersDirectory: URL?
    private var metallibURL: URL?
    
    // MARK: - Configuration
    
    /// Paths to search for metallib
    public static let metallibSearchPaths: [String] = [
        Bundle.main.bundleURL.appendingPathComponent("Shaders.metallib").path,
        Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Shaders.metallib").path,
        Bundle.main.path(forResource: "Shaders", ofType: "metallib") ?? "",
        // Dev paths - adjust as needed
        "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJApp/Resources/Shaders.metallib",
        "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Build/Shaders.metallib"
    ].filter { !$0.isEmpty }
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - Public API
    
    /// Load shaders from metallib and enrich with file metadata.
    ///
    /// - Parameters:
    ///   - metallibPath: Optional explicit path to metallib. If nil, searches standard paths.
    ///   - shadersDirectory: Directory containing shader folders (glsl/, masks/) with .txt and .analysis.json files
    /// - Returns: Number of shaders loaded
    @discardableResult
    public func load(metallibPath: String? = nil, shadersDirectory: URL? = nil) -> Int {
        self.shadersDirectory = shadersDirectory
        shaders.removeAll()
        metallibShaderNames.removeAll()
        
        // Find metallib
        let searchPaths: [String]
        if let explicit = metallibPath {
            searchPaths = [explicit]
        } else {
            searchPaths = Self.metallibSearchPaths
        }
        
        for path in searchPaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            metallibURL = URL(fileURLWithPath: path)
            break
        }
        
        // Extract shader names from metallib
        if let url = metallibURL {
            if let names = try? MetallibParser.parseMetallib(at: url) {
                metallibShaderNames = Set(names)
                print("[ShaderStore] Found \(names.count) shaders in metallib")
            }
        } else {
            print("[ShaderStore] No metallib found in search paths")
        }
        
        // Load from directory using ShaderRepository module
        if let dir = shadersDirectory {
            do {
                let loadedShaders = try Shaders.loadAll(shadersDir: dir, metallibURL: metallibURL)
                for shader in loadedShaders {
                    shaders[shader.name] = shader
                }
                print("[ShaderStore] Loaded \(loadedShaders.count) shaders from directory")
            } catch {
                print("[ShaderStore] Failed to load shaders: \(error)")
            }
        } else {
            // Create basic shader entries from metallib names
            for name in metallibShaderNames {
                let shader = Shader(
                    name: name,
                    sourceURL: URL(fileURLWithPath: "/metallib/\(name).txt"),
                    folder: "glsl",
                    metalFunctionName: "fragment_\(name)"
                )
                shaders[name] = shader
            }
        }
        
        print("[ShaderStore] Loaded \(shaders.count) shaders total")
        return shaders.count
    }
    
    /// Reload shaders (call when files change)
    @discardableResult
    public func reload() -> Int {
        load(metallibPath: metallibURL?.path, shadersDirectory: shadersDirectory)
    }
    
    /// Get all shaders (sorted by name)
    public var allShaders: [Shader] {
        shaders.values.sorted { $0.name < $1.name }
    }
    
    /// Get all shaders as ShaderInfo (for UI compatibility)
    public var allShaderInfos: [ShaderInfo] {
        allShaders.map { ShaderInfo(from: $0) }
    }
    
    /// Get shaders in a specific folder
    public func shaders(inFolder folder: String) -> [Shader] {
        shaders.values.filter { $0.folder == folder }.sorted { $0.name < $1.name }
    }
    
    /// Get all unique folder names
    public var availableFolders: [String] {
        Shaders.folders(in: Array(shaders.values))
    }
    
    /// Get shader by name
    public func shader(named name: String) -> Shader? {
        // Try exact match first
        if let shader = shaders[name] {
            return shader
        }
        // Try without folder prefix
        let baseName = name.components(separatedBy: "/").last ?? name
        return shaders.values.first { $0.name == baseName || $0.name.hasSuffix("/\(baseName)") }
    }
    
    /// Get shader info by name (for UI compatibility)
    public func shaderInfo(named name: String) -> ShaderInfo? {
        guard let shader = shader(named: name) else { return nil }
        return ShaderInfo(from: shader)
    }
    
    /// Check if shader is renderable (in metallib)
    public func isRenderable(_ name: String) -> Bool {
        let baseName = name.components(separatedBy: "/").last ?? name
        return metallibShaderNames.contains(baseName)
    }
    
    /// Total shader count
    public var count: Int { shaders.count }
    
    // MARK: - Matching (delegates to Shaders namespace, converts results)
    
    /// Match shaders to energy and valence
    public func match(energy: Double, valence: Double, topK: Int = 5) -> [ShaderMatchResult] {
        Shaders.match(energy: energy, valence: valence, in: Array(shaders.values), topK: topK)
            .map { ShaderMatchResult(from: $0) }
    }
    
    /// Match shaders by mood
    public func matchByMood(_ mood: String, energy: Double = 0.5, topK: Int = 5) -> [ShaderMatchResult] {
        Shaders.matchByMood(mood, energy: energy, in: Array(shaders.values), topK: topK)
            .map { ShaderMatchResult(from: $0) }
    }
    
    /// Match with phase consideration
    public func matchWithPhase(
        energy: Double,
        valence: Double,
        phase: Phase?,
        phaseWeight: Double = 0.2,
        topK: Int = 5
    ) -> [ShaderMatchResult] {
        Shaders.matchWithPhase(
            energy: energy,
            valence: valence,
            phase: phase,
            phaseWeight: phaseWeight,
            in: Array(shaders.values),
            topK: topK
        ).map { ShaderMatchResult(from: $0) }
    }
    
    /// Search shaders by text
    public func search(query: String) -> [Shader] {
        Shaders.search(query: query, in: Array(shaders.values))
    }
    
    /// Find similar shaders
    public func findSimilar(to shader: Shader, topK: Int = 5) -> [ShaderMatchResult] {
        Shaders.findSimilar(to: shader, in: Array(shaders.values), topK: topK)
            .map { ShaderMatchResult(from: $0) }
    }
    
    /// Get random shader
    public func randomShader() -> Shader? {
        shaders.values.randomElement()
    }
    
    /// Filter by phase
    public func shaders(forPhase phase: Phase) -> [Shader] {
        Shaders.filter(byPhase: phase, in: Array(shaders.values))
    }
    
    /// Filter renderable only
    public func renderableShaders() -> [Shader] {
        Shaders.filterRenderable(in: Array(shaders.values))
    }
}

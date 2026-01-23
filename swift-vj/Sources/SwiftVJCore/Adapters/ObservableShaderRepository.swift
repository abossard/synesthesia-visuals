// ObservableShaderRepository.swift - Observable single source of truth for shader data
// Wraps the ShaderRepository pure functions with @Published state for SwiftUI

import Foundation
import Combine
import ShaderRepository

// MARK: - Observable Shader Repository

/// Observable single source of truth for all shader data.
/// - Uses ShaderRepository.Shaders for pure loading/matching functions
/// - Provides @Published state for SwiftUI reactivity
/// - Thread-safe via @MainActor
/// - All mutations go through repository methods (unidirectional flow)
@MainActor
public final class ObservableShaderRepository: ObservableObject {
    
    // MARK: - Published State
    
    /// All loaded shaders (both regular and masks)
    @Published public private(set) var allShaders: [ShaderInfo] = []
    
    /// Last reload timestamp
    @Published public private(set) var lastReloadTime: Date?
    
    /// Loading state
    @Published public private(set) var isLoading: Bool = false
    
    /// Error message from last operation
    @Published public private(set) var lastError: String?
    
    // MARK: - Configuration
    
    private var metallibURL: URL?
    private var shadersDirectory: URL?
    
    /// Internal shader storage (ShaderRepository.Shader)
    private var shaders: [Shader] = []
    
    /// Metallib shader names (for renderable check)
    private var metallibNames: Set<String> = []
    
    // MARK: - Computed Filters (no storage, derived from allShaders)
    
    /// All available folder names
    public var folders: [String] {
        Array(Set(allShaders.map { $0.folder })).sorted()
    }
    
    /// Shaders that are renderable (have Metal function)
    public var renderableShaders: [ShaderInfo] {
        allShaders.filter { $0.metalFunctionName != nil }
    }
    
    /// Mask shaders (folder == "masks")
    public var masks: [ShaderInfo] {
        allShaders.filter { $0.isMask }
    }
    
    /// Regular shaders (not masks)
    public var regularShaders: [ShaderInfo] {
        allShaders.filter { !$0.isMask }
    }
    
    /// Shader names (for quick lookup)
    public var shaderNames: [String] {
        allShaders.map { $0.name }
    }
    
    /// Mask names
    public var maskNames: [String] {
        masks.map { $0.name }
    }
    
    /// Regular shader names
    public var regularShaderNames: [String] {
        regularShaders.map { $0.name }
    }
    
    /// Filter by folder
    public func byFolder(_ folder: String) -> [ShaderInfo] {
        allShaders.filter { $0.folder == folder }
    }
    
    /// Filter by rating
    public func byRating(_ rating: ShaderRating) -> [ShaderInfo] {
        allShaders.filter { $0.rating == rating }
    }
    
    /// Filter by phase
    public func byPhase(_ phase: Phase) -> [ShaderInfo] {
        allShaders.filter { $0.phases?.contains(phase) == true }
    }
    
    /// Check if shader exists
    public func contains(_ name: String) -> Bool {
        allShaders.contains { $0.name == name }
    }
    
    /// Get shader by name
    public func shader(named name: String) -> ShaderInfo? {
        allShaders.first { $0.name == name }
    }
    
    /// Check if shader is renderable
    public func isRenderable(_ name: String) -> Bool {
        metallibNames.contains(name)
    }
    
    /// Check if shader is a mask
    public func isMask(_ name: String) -> Bool {
        shader(named: name)?.isMask ?? false
    }
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - Configuration
    
    /// Configure repository with metallib and shaders directory
    public func configure(metallibURL: URL?, shadersDirectory: URL?) {
        self.metallibURL = metallibURL
        self.shadersDirectory = shadersDirectory
    }
    
    // MARK: - Loading
    
    /// Reload all shaders from metallib and file system
    @discardableResult
    public func reload() async -> Int {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        
        // Parse metallib for renderable shader names
        metallibNames.removeAll()
        if let url = metallibURL {
            if let names = try? MetallibParser.parseMetallib(at: url) {
                metallibNames = Set(names)
                print("[ShaderRepository] Found \(names.count) shaders in metallib")
            }
        } else {
            // Try to find metallib in standard paths
            let searchPaths = [
                Bundle.main.bundleURL.appendingPathComponent("Shaders.metallib").path,
                Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Shaders.metallib").path,
                Bundle.main.path(forResource: "Shaders", ofType: "metallib") ?? "",
                "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJApp/Resources/Shaders.metallib",
                "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Build/Shaders.metallib"
            ].filter { !$0.isEmpty }
            
            for path in searchPaths {
                if FileManager.default.fileExists(atPath: path) {
                    metallibURL = URL(fileURLWithPath: path)
                    if let names = try? MetallibParser.parseMetallib(at: URL(fileURLWithPath: path)) {
                        metallibNames = Set(names)
                        print("[ShaderRepository] Found \(names.count) shaders in metallib: \(path)")
                    }
                    break
                }
            }
        }
        
        // Load shaders from directory
        if let dir = shadersDirectory {
            do {
                shaders = try ShaderRepository.Shaders.loadAll(shadersDir: dir, metallibURL: metallibURL)
                print("[ShaderRepository] Loaded \(shaders.count) shaders from directory")
            } catch {
                lastError = "Failed to load shaders: \(error.localizedDescription)"
                print("[ShaderRepository] \(lastError!)")
                shaders = []
            }
        } else {
            // Create basic shader entries from metallib names only
            shaders = metallibNames.sorted().map {
                Shader(
                    name: $0,
                    sourceURL: URL(fileURLWithPath: "/metallib/\($0).txt"),
                    folder: "glsl",
                    metalFunctionName: "fragment_\($0)"
                )
            }
        }
        
        // Convert to ShaderInfo for UI
        allShaders = shaders.map { ShaderInfo(from: $0) }
        lastReloadTime = Date()
        
        print("[ShaderRepository] Total: \(allShaders.count) shaders (\(regularShaders.count) regular, \(masks.count) masks)")
        return allShaders.count
    }
    
    /// Set shaders directory and reload
    public func setShadersDirectory(_ url: URL) async {
        shadersDirectory = url
        await reload()
    }
    
    // MARK: - Mutations
    
    /// Move shader to different folder
    /// - Updates internal state and moves files on disk
    public func moveToFolder(shaderName: String, folder: String) throws {
        guard let shadersDir = shadersDirectory else {
            throw RepositoryError.noShadersDirectory
        }
        
        guard let shaderInfo = shader(named: shaderName) else {
            throw RepositoryError.shaderNotFound(shaderName)
        }
        
        // Source and destination
        let sourceFile = URL(fileURLWithPath: shaderInfo.path)
        let sourceDir = sourceFile.deletingLastPathComponent()
        let destDir = shadersDir.appendingPathComponent(folder)
        
        // Create destination folder if needed
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Move all related files (.txt, .png, .analysis.json)
        let extensions = ["txt", "png", "analysis.json"]
        let baseName = sourceFile.deletingPathExtension().lastPathComponent
        
        for ext in extensions {
            let sourceRelated = sourceDir.appendingPathComponent("\(baseName).\(ext)")
            let destRelated = destDir.appendingPathComponent("\(baseName).\(ext)")
            
            if FileManager.default.fileExists(atPath: sourceRelated.path) {
                try FileManager.default.moveItem(at: sourceRelated, to: destRelated)
            }
        }
        
        // Update internal state
        if let index = allShaders.firstIndex(where: { $0.name == shaderName }) {
            let old = allShaders[index]
            let newPath = destDir.appendingPathComponent("\(baseName).txt").path
            allShaders[index] = ShaderInfo(
                name: old.name,
                path: newPath,
                folder: folder,
                energyScore: old.energyScore,
                moodValence: old.moodValence,
                colorWarmth: old.colorWarmth,
                motionSpeed: old.motionSpeed,
                mood: old.mood,
                colors: old.colors,
                effects: old.effects,
                rating: folder == "masks" ? .mask : old.rating,
                phases: old.phases,
                metalFunctionName: old.metalFunctionName
            )
        }
        
        print("[ShaderRepository] Moved \(shaderName) to \(folder)")
    }
    
    /// Delete shader and all related files
    public func delete(shaderName: String) throws {
        guard let shaderInfo = shader(named: shaderName) else {
            throw RepositoryError.shaderNotFound(shaderName)
        }
        
        let sourceFile = URL(fileURLWithPath: shaderInfo.path)
        let sourceDir = sourceFile.deletingLastPathComponent()
        let baseName = sourceFile.deletingPathExtension().lastPathComponent
        
        // Delete all related files
        let extensions = ["txt", "png", "analysis.json"]
        for ext in extensions {
            let file = sourceDir.appendingPathComponent("\(baseName).\(ext)")
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
        }
        
        // Update internal state
        allShaders.removeAll { $0.name == shaderName }
        shaders.removeAll { $0.name == shaderName }
        
        print("[ShaderRepository] Deleted \(shaderName)")
    }
    
    /// Update shader analysis
    public func updateAnalysis(shaderName: String, analysis: ShaderRepository.ShaderAnalysis) throws {
        guard shader(named: shaderName) != nil else {
            throw RepositoryError.shaderNotFound(shaderName)
        }
        
        // Find the underlying Shader
        guard let shader = shaders.first(where: { $0.name == shaderName }) else {
            throw RepositoryError.shaderNotFound(shaderName)
        }
        
        // Save analysis using ShaderRepository functions
        try ShaderRepository.Shaders.save(analysis: analysis, for: shader)
        
        // Update internal state
        if let index = allShaders.firstIndex(where: { $0.name == shaderName }) {
            let old = allShaders[index]
            let featureVector = analysis.featureVector
            allShaders[index] = ShaderInfo(
                name: old.name,
                path: old.path,
                folder: old.folder,
                energyScore: analysis.energy,
                moodValence: featureVector.count > 1 ? featureVector[1] : 0.0,
                colorWarmth: featureVector.count > 2 ? featureVector[2] : 0.5,
                motionSpeed: featureVector.count > 3 ? featureVector[3] : 0.5,
                mood: analysis.mood,
                colors: analysis.colors,
                effects: analysis.effects,
                rating: old.rating,
                phases: analysis.phases,
                metalFunctionName: old.metalFunctionName
            )
        }
        
        print("[ShaderRepository] Updated analysis for \(shaderName)")
    }
    
    // MARK: - Matching (delegates to Shaders)
    
    /// Match shaders to energy and valence
    public func match(energy: Double, valence: Double, topK: Int = 5) -> [ShaderMatchResult] {
        ShaderRepository.Shaders.match(energy: energy, valence: valence, in: shaders, topK: topK)
            .map { SwiftVJCore.ShaderMatchResult(from: $0) }
    }
    
    /// Match shaders by mood
    public func matchByMood(_ mood: String, energy: Double = 0.5, topK: Int = 5) -> [ShaderMatchResult] {
        ShaderRepository.Shaders.matchByMood(mood, energy: energy, in: shaders, topK: topK)
            .map { SwiftVJCore.ShaderMatchResult(from: $0) }
    }
    
    /// Search shaders by text
    public func search(query: String) -> [ShaderInfo] {
        let results = ShaderRepository.Shaders.search(query: query, in: shaders)
        return results.map { ShaderInfo(from: $0) }
    }
    
    /// Get random shader
    public func randomShader() -> ShaderInfo? {
        shaders.randomElement().map { ShaderInfo(from: $0) }
    }
}

// MARK: - Errors

public enum RepositoryError: LocalizedError {
    case noShadersDirectory
    case shaderNotFound(String)
    case fileOperationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noShadersDirectory:
            return "Shaders directory not configured"
        case .shaderNotFound(let name):
            return "Shader '\(name)' not found"
        case .fileOperationFailed(let message):
            return "File operation failed: \(message)"
        }
    }
}

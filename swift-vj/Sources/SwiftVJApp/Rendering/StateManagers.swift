// StateManagers.swift - Observable state managers for VJ rendering
// Minimal managers for shader, mask, and image state

import Foundation
import SwiftUI
import Metal
import SwiftVJCore

// MARK: - Shader State Manager

/// Manages shader and mask selection and state
/// Uses metallib as source of truth for renderable shaders
/// Provides unified access to all shaders with isMask filtering
@MainActor
final class ShaderStateManager: ObservableObject {
    @Published var state: ShaderDisplayState = .empty
    @Published var maskState: ShaderDisplayState = .empty
    @Published private(set) var allShaders: [ShaderInfo] = []  // All shaders (both regular and masks)
    @Published private(set) var shadersDirectory: URL?

    private(set) var currentIndex: Int = 0
    private(set) var currentMaskIndex: Int = 0
    private var metallibPath: String?
    
    /// All shaders from metallib (before folder filtering)
    private var allMetallibShaders: Set<String> = []
    
    /// Shader name -> folder mapping from file system
    private var shaderFolders: [String: String] = [:]

    /// Logger callback for UI integration
    var logger: ((String, LogLevel) -> Void)?

    init() {
        loadMetallibShaders()
    }
    
    // MARK: - Computed Filters
    
    /// Regular shaders (non-masks, from "glsl" folder or unknown)
    var availableShaders: [ShaderInfo] {
        allShaders.filter { !$0.isMask }
    }
    
    /// Mask shaders (from "masks" folder)
    var availableMasks: [ShaderInfo] {
        allShaders.filter { $0.isMask }
    }
    
    /// Get shader names (for UI integration)
    var shaderNames: [String] {
        availableShaders.map { $0.name }
    }
    
    /// Get mask names (for UI integration)
    var maskNames: [String] {
        availableMasks.map { $0.name }
    }
    
    // MARK: - Lifecycle
    
    /// Reload shaders from metallib and file system
    /// Call this from UI when shaders may have changed
    func reload() {
        loadMetallibShaders()
        // Re-enrich with file metadata if directory is set
        if let dir = shadersDirectory {
            enrichFromFileSystem(directory: dir)
        }
        print("[ShaderStateManager] Reloaded: \(availableShaders.count) shaders, \(availableMasks.count) masks")
    }
    
    /// Set the shaders directory for file-based metadata enrichment
    func setShadersDirectory(_ url: URL) {
        shadersDirectory = url
        enrichFromFileSystem(directory: url)
    }
    
    private func loadMetallibShaders() {
        // Dynamically scan metallib for fragment_* functions
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[ShaderStateManager] No Metal device")
            return
        }
        
        // Find metallib
        let searchPaths = [
            Bundle.main.bundleURL.appendingPathComponent("Shaders.metallib").path,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Shaders.metallib").path,
            Bundle.main.path(forResource: "Shaders", ofType: "metallib") ?? "",
            "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Sources/SwiftVJApp/Resources/Shaders.metallib",
            "/Users/abossard/Desktop/projects/synesthesia-visuals/swift-vj/Build/Shaders.metallib"
        ].filter { !$0.isEmpty }
        
        var library: MTLLibrary?
        for path in searchPaths {
            if FileManager.default.fileExists(atPath: path) {
                library = try? device.makeLibrary(URL: URL(fileURLWithPath: path))
                if library != nil {
                    metallibPath = path
                    print("[ShaderStateManager] Loaded metallib: \(path)")
                    break
                }
            }
        }
        
        guard let lib = library else {
            print("[ShaderStateManager] No metallib found")
            return
        }
        
        // Extract shader names from fragment_* functions
        let shaderNames = lib.functionNames
            .filter { $0.hasPrefix("fragment_") && $0 != "fragment_main" }
            .map { String($0.dropFirst("fragment_".count)) }
        
        allMetallibShaders = Set(shaderNames)
        
        // Initially populate allShaders with all metallib shaders (folder = "glsl" default)
        // These will be updated with correct folders once enrichFromFileSystem is called
        allShaders = shaderNames.sorted().map {
            ShaderInfo(name: $0, path: "/metallib/\($0)", folder: "glsl", metalFunctionName: "fragment_\($0)")
        }
        
        print("[ShaderStateManager] Found \(allMetallibShaders.count) shaders in metallib")
    }
    
    /// Enrich shaders with metadata from file system (.analysis.json, folder info)
    private func enrichFromFileSystem(directory: URL) {
        let fileManager = FileManager.default
        shaderFolders.removeAll()
        
        // Scan subdirectories (glsl/, masks/, etc.)
        guard let subDirs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for subDirURL in subDirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: subDirURL.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            
            let folderName = subDirURL.lastPathComponent
            
            // Find all .txt shader files
            guard let contents = try? fileManager.contentsOfDirectory(
                at: subDirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for fileURL in contents where fileURL.pathExtension == "txt" {
                let shaderName = fileURL.deletingPathExtension().lastPathComponent
                shaderFolders[shaderName] = folderName
            }
        }
        
        // Build unified shader list with correct folder assignments
        var enrichedShaders: [ShaderInfo] = []
        
        for shaderName in allMetallibShaders.sorted() {
            let folder = shaderFolders[shaderName] ?? "glsl"  // Default to glsl if unknown
            let path: String
            if shaderFolders[shaderName] != nil {
                path = directory.appendingPathComponent(folder).appendingPathComponent("\(shaderName).txt").path
            } else {
                path = "/metallib/\(shaderName)"
            }
            
            enrichedShaders.append(ShaderInfo(
                name: shaderName,
                path: path,
                folder: folder,
                metalFunctionName: "fragment_\(shaderName)"
            ))
        }
        
        allShaders = enrichedShaders
        
        print("[ShaderStateManager] Enriched: \(availableShaders.count) shaders, \(availableMasks.count) masks")
    }
    
    // MARK: - Shader Selection
    
    /// Select a shader for the MAIN output (any shader, regardless of isMask)
    func selectShader(name: String) {
        guard let shader = allShaders.first(where: { $0.name == name }) else {
            let errorMsg = "[Shader] ❌ '\(name)' not found (\(allShaders.count) available)"
            logger?(errorMsg, .error)
            print(errorMsg)
            suggestSimilar(name)
            return
        }
        
        if let index = allShaders.firstIndex(where: { $0.name == name }) {
            currentIndex = index
        }
        state = ShaderDisplayState(current: shader, isLoaded: true, error: nil, audioTime: state.audioTime, syntheticMouse: state.syntheticMouse)
        logger?("[Shader] ✓ Selected: \(name)\(shader.isMask ? " (mask)" : "")", .debug)
    }
    
    /// Select a shader for the MASK output (any shader, regardless of isMask)
    func selectMask(name: String) {
        guard let shader = allShaders.first(where: { $0.name == name }) else {
            let errorMsg = "[Mask] ❌ '\(name)' not found (\(allShaders.count) available)"
            logger?(errorMsg, .error)
            print(errorMsg)
            suggestSimilar(name)
            return
        }
        
        if let index = allShaders.firstIndex(where: { $0.name == name }) {
            currentMaskIndex = index
        }
        maskState = ShaderDisplayState(current: shader, isLoaded: true, error: nil, audioTime: 0, syntheticMouse: SIMD2(0.5, 0.5))
        logger?("[Mask] ✓ Selected: \(name)\(shader.isMask ? " (mask)" : "")", .debug)
    }
    
    /// Suggest similar shader names when not found
    private func suggestSimilar(_ name: String) {
        if !allShaders.isEmpty {
            let similar = allShaders.filter {
                $0.name.lowercased().contains(name.lowercased()) ||
                name.lowercased().contains($0.name.lowercased())
            }
            if !similar.isEmpty {
                let hint = "Similar: \(similar.prefix(5).map { $0.name }.joined(separator: ", "))"
                logger?(hint, .warning)
                print(hint)
            }
        }
    }
    
    func nextShader() {
        guard !availableShaders.isEmpty else { return }
        currentIndex = (currentIndex + 1) % availableShaders.count
        let shader = availableShaders[currentIndex]
        state = ShaderDisplayState(current: shader, isLoaded: true, error: nil, audioTime: state.audioTime, syntheticMouse: state.syntheticMouse)
    }
    
    func prevShader() {
        guard !availableShaders.isEmpty else { return }
        currentIndex = (currentIndex - 1 + availableShaders.count) % availableShaders.count
        let shader = availableShaders[currentIndex]
        state = ShaderDisplayState(current: shader, isLoaded: true, error: nil, audioTime: state.audioTime, syntheticMouse: state.syntheticMouse)
    }
    
    func nextMask() {
        guard !availableMasks.isEmpty else { return }
        currentMaskIndex = (currentMaskIndex + 1) % availableMasks.count
        let mask = availableMasks[currentMaskIndex]
        maskState = ShaderDisplayState(current: mask, isLoaded: true, error: nil, audioTime: 0, syntheticMouse: SIMD2(0.5, 0.5))
    }
    
    func prevMask() {
        guard !availableMasks.isEmpty else { return }
        currentMaskIndex = (currentMaskIndex - 1 + availableMasks.count) % availableMasks.count
        let mask = availableMasks[currentMaskIndex]
        maskState = ShaderDisplayState(current: mask, isLoaded: true, error: nil, audioTime: 0, syntheticMouse: SIMD2(0.5, 0.5))
    }
    
    /// Check if a shader name exists in metallib (any folder)
    func isRenderable(_ name: String) -> Bool {
        allShaders.contains { $0.name == name }
    }
    
    /// Check if a shader is a mask by name
    func isMask(_ name: String) -> Bool {
        allShaders.first { $0.name == name }?.isMask ?? false
    }
}

// MARK: - Mask State Manager (Backwards Compatibility)

/// Backwards compatibility typealias - masks are now managed by ShaderStateManager
typealias MaskStateManager = ShaderStateManager

// MARK: - Image State Manager

/// Manages image display state
@MainActor
final class ImageStateManager: ObservableObject {
    @Published var state: ImageDisplayState = .empty
}

// StateManagers.swift - Observable state managers for VJ rendering
// Minimal managers for text, shader, mask, and image state

import Foundation
import SwiftUI
import Metal
import SwiftVJCore

// MARK: - Text State Manager

/// Manages text display states (lyrics, refrain, song info)
@MainActor
final class TextStateManager: ObservableObject {
    @Published var lyricsState: LyricsDisplayState = .empty
    @Published var refrainState: RefrainDisplayState = .empty
    @Published var songInfoState: SongInfoDisplayState = .empty
    
    func start() {
        // No-op for now, could start animation timers
    }
    
    func stop() {
        // Reset states
        lyricsState = .empty
        refrainState = .empty
        songInfoState = .empty
    }
    
    func setLyrics(_ lines: [DisplayLyricLine]) {
        lyricsState = LyricsDisplayState(
            lines: lines,
            activeIndex: 0,
            textOpacity: 255,
            fadeDelayMs: 5000,
            fadeDurationMs: 1000,
            lastChangeTime: Date()
        )
    }
    
    func setActiveLine(_ index: Int) {
        lyricsState = LyricsDisplayState(
            lines: lyricsState.lines,
            activeIndex: index,
            textOpacity: 255,
            fadeDelayMs: lyricsState.fadeDelayMs,
            fadeDurationMs: lyricsState.fadeDurationMs,
            lastChangeTime: Date()
        )
    }
    
    func setRefrain(_ text: String) {
        refrainState = RefrainDisplayState(
            text: text,
            opacity: 255,
            active: !text.isEmpty,
            lastChangeTime: Date()
        )
    }
    
    func setSongInfo(artist: String, title: String, album: String) {
        songInfoState = SongInfoDisplayState(
            artist: artist,
            title: title,
            album: album,
            opacity: 255,
            displayTime: 0,
            active: true,
            lastChangeTime: Date()
        )
    }
}

// MARK: - Shader State Manager

/// Manages shader selection and state
/// Uses metallib as source of truth for renderable shaders
/// Filters to only show shaders from "glsl" folder (excludes masks)
@MainActor
final class ShaderStateManager: ObservableObject {
    @Published var state: ShaderDisplayState = .empty
    @Published private(set) var availableShaders: [ShaderInfo] = []
    @Published private(set) var shadersDirectory: URL?

    private(set) var currentIndex: Int = 0
    private var metallibPath: String?
    
    /// All shaders from metallib (before folder filtering)
    private var allMetallibShaders: Set<String> = []
    
    /// Shader name -> folder mapping from file system
    private var shaderFolders: [String: String] = [:]
    
    /// Folder to filter by (default: "glsl" for non-mask shaders)
    let targetFolder: String = "glsl"

    /// Logger callback for UI integration
    var logger: ((String, LogLevel) -> Void)?

    init() {
        loadMetallibShaders()
    }
    
    /// Reload shaders from metallib and file system
    /// Call this from UI when shaders may have changed
    func reload() {
        loadMetallibShaders()
        // Re-enrich with file metadata if directory is set
        if let dir = shadersDirectory {
            enrichFromFileSystem(directory: dir)
        }
        print("[ShaderStateManager] Reloaded: \(availableShaders.count) shaders (glsl only)")
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
        
        // Initially populate availableShaders with all metallib shaders
        // These will be filtered once enrichFromFileSystem is called
        availableShaders = shaderNames.sorted().map {
            ShaderInfo(name: $0, path: "/metallib/\($0)", metalFunctionName: "fragment_\($0)")
        }
        
        print("[ShaderStateManager] Found \(allMetallibShaders.count) shaders in metallib")
    }
    
    /// Enrich shaders with metadata from file system (.analysis.json, folder info)
    /// Filters to only include shaders from targetFolder (glsl)
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
        
        // Build filtered shader list: only shaders in targetFolder (glsl)
        var filteredShaders: [ShaderInfo] = []
        
        for shaderName in allMetallibShaders.sorted() {
            let folder = shaderFolders[shaderName]
            
            // Only include if in target folder, or if no folder info (unknown)
            // This ensures masks are excluded
            if folder == targetFolder || folder == nil {
                let path: String
                if let folder = folder {
                    path = directory.appendingPathComponent(folder).appendingPathComponent("\(shaderName).txt").path
                } else {
                    path = "/metallib/\(shaderName)"
                }
                
                filteredShaders.append(ShaderInfo(
                    name: shaderName,
                    path: path,
                    metalFunctionName: "fragment_\(shaderName)"
                ))
            }
        }
        
        availableShaders = filteredShaders
        
        let masksCount = shaderFolders.values.filter { $0 == "masks" }.count
        print("[ShaderStateManager] Filtered to \(availableShaders.count) shaders in '\(targetFolder)' (excluded \(masksCount) masks)")
    }
    
    func selectShader(name: String) {
        if let index = availableShaders.firstIndex(where: { $0.name == name }) {
            currentIndex = index
            state = ShaderDisplayState(current: availableShaders[index], isLoaded: true, error: nil, audioTime: state.audioTime, syntheticMouse: state.syntheticMouse)
            logger?("[Shader] ✓ Selected: \(name)", .debug)
        } else {
            // Check if it's a mask shader (wrong manager)
            if shaderFolders[name] == "masks" {
                let errorMsg = "[Shader] ❌ '\(name)' is a mask shader - use maskManager instead"
                logger?(errorMsg, .warning)
                print(errorMsg)
                return
            }
            
            // Log error to UI and console
            let errorMsg = "[Shader] ❌ '\(name)' not found in metallib (\(availableShaders.count) available)"
            logger?(errorMsg, .error)
            print(errorMsg)

            // Suggest similar shaders if any
            if !availableShaders.isEmpty {
                let similar = availableShaders.filter {
                    $0.name.lowercased().contains(name.lowercased()) ||
                    name.lowercased().contains($0.name.lowercased())
                }
                if !similar.isEmpty {
                    let hint = "[Shader] Similar: \(similar.prefix(5).map { $0.name }.joined(separator: ", "))"
                    logger?(hint, .warning)
                    print(hint)
                }
            }
        }
    }
    
    func nextShader() {
        guard !availableShaders.isEmpty else { return }
        currentIndex = (currentIndex + 1) % availableShaders.count
        state = ShaderDisplayState(current: availableShaders[currentIndex], isLoaded: true, error: nil, audioTime: state.audioTime, syntheticMouse: state.syntheticMouse)
    }
    
    func prevShader() {
        guard !availableShaders.isEmpty else { return }
        currentIndex = (currentIndex - 1 + availableShaders.count) % availableShaders.count
        state = ShaderDisplayState(current: availableShaders[currentIndex], isLoaded: true, error: nil, audioTime: state.audioTime, syntheticMouse: state.syntheticMouse)
    }
    
    /// Get shader names (for UI integration)
    var shaderNames: [String] {
        availableShaders.map { $0.name }
    }
    
    /// Check if a shader name exists in metallib and is in the target folder
    func isRenderable(_ name: String) -> Bool {
        availableShaders.contains { $0.name == name }
    }
}

// MARK: - Mask State Manager

/// Manages mask shader selection and state
/// Filters to only show shaders from "masks" folder
@MainActor
final class MaskStateManager: ObservableObject {
    @Published var state: ShaderDisplayState = .empty
    @Published private(set) var availableMasks: [ShaderInfo] = []
    @Published private(set) var shadersDirectory: URL?
    
    private(set) var currentIndex: Int = 0
    
    /// All shaders from metallib (before folder filtering)
    private var allMetallibShaders: Set<String> = []
    
    /// Shader name -> folder mapping from file system
    private var shaderFolders: [String: String] = [:]
    
    /// Folder to filter by (masks only)
    let targetFolder: String = "masks"
    
    /// Logger callback for UI integration
    var logger: ((String, LogLevel) -> Void)?
    
    init() {
        loadMetallibShaders()
    }
    
    /// Reload masks from metallib and file system
    func reload() {
        loadMetallibShaders()
        if let dir = shadersDirectory {
            enrichFromFileSystem(directory: dir)
        }
        print("[MaskStateManager] Reloaded: \(availableMasks.count) masks")
    }
    
    /// Set the shaders directory for file-based metadata enrichment
    func setShadersDirectory(_ url: URL) {
        shadersDirectory = url
        enrichFromFileSystem(directory: url)
    }
    
    private func loadMetallibShaders() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[MaskStateManager] No Metal device")
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
                if library != nil { break }
            }
        }
        
        guard let lib = library else {
            print("[MaskStateManager] No metallib found")
            return
        }
        
        // Extract shader names from fragment_* functions
        let shaderNames = lib.functionNames
            .filter { $0.hasPrefix("fragment_") && $0 != "fragment_main" }
            .map { String($0.dropFirst("fragment_".count)) }
        
        allMetallibShaders = Set(shaderNames)
        print("[MaskStateManager] Found \(allMetallibShaders.count) shaders in metallib")
    }
    
    /// Enrich shaders with metadata from file system
    /// Filters to only include shaders from "masks" folder
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
        
        // Build filtered shader list: only shaders in "masks" folder
        var filteredMasks: [ShaderInfo] = []
        
        for shaderName in allMetallibShaders.sorted() {
            let folder = shaderFolders[shaderName]
            
            // Only include if in masks folder
            if folder == targetFolder {
                let path = directory.appendingPathComponent(targetFolder).appendingPathComponent("\(shaderName).txt").path
                
                filteredMasks.append(ShaderInfo(
                    name: shaderName,
                    path: path,
                    metalFunctionName: "fragment_\(shaderName)"
                ))
            }
        }
        
        availableMasks = filteredMasks
        print("[MaskStateManager] Filtered to \(availableMasks.count) mask shaders")
    }
    
    func selectMask(name: String) {
        if let index = availableMasks.firstIndex(where: { $0.name == name }) {
            currentIndex = index
            state = ShaderDisplayState(current: availableMasks[index], isLoaded: true, error: nil, audioTime: 0, syntheticMouse: SIMD2(0.5, 0.5))
            logger?("[Mask] ✓ Selected: \(name)", .debug)
        } else {
            // Check if it's a regular shader (wrong manager)
            if shaderFolders[name] == "glsl" {
                let errorMsg = "[Mask] ❌ '\(name)' is a regular shader - use shaderManager instead"
                logger?(errorMsg, .warning)
                print(errorMsg)
                return
            }
            
            // Check if shader exists in metallib but not in masks folder
            if allMetallibShaders.contains(name) {
                let folder = shaderFolders[name] ?? "unknown"
                let errorMsg = "[Mask] ❌ '\(name)' is in '\(folder)' folder, not masks"
                logger?(errorMsg, .warning)
                print(errorMsg)
                return
            }
            
            // Shader not found at all
            let errorMsg = "[Mask] ❌ '\(name)' not found (\(availableMasks.count) masks available)"
            logger?(errorMsg, .error)
            print(errorMsg)
        }
    }
    
    func nextMask() {
        guard !availableMasks.isEmpty else { return }
        currentIndex = (currentIndex + 1) % availableMasks.count
        state = ShaderDisplayState(current: availableMasks[currentIndex], isLoaded: true, error: nil, audioTime: 0, syntheticMouse: SIMD2(0.5, 0.5))
    }
    
    func prevMask() {
        guard !availableMasks.isEmpty else { return }
        currentIndex = (currentIndex - 1 + availableMasks.count) % availableMasks.count
        state = ShaderDisplayState(current: availableMasks[currentIndex], isLoaded: true, error: nil, audioTime: 0, syntheticMouse: SIMD2(0.5, 0.5))
    }
    
    /// Get mask names (for UI integration)
    var maskNames: [String] {
        availableMasks.map { $0.name }
    }
    
    /// Check if a mask name exists and is in masks folder
    func isRenderable(_ name: String) -> Bool {
        availableMasks.contains { $0.name == name }
    }
}

// MARK: - Image State Manager

/// Manages image display state
@MainActor
final class ImageStateManager: ObservableObject {
    @Published var state: ImageDisplayState = .empty
}

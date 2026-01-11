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
@MainActor
final class ShaderStateManager: ObservableObject {
    @Published var state: ShaderDisplayState = .empty
    @Published private(set) var availableShaders: [ShaderInfo] = []
    @Published private(set) var shadersDirectory: URL?

    private(set) var currentIndex: Int = 0
    private var metallibPath: String?

    /// Logger callback for UI integration
    var logger: ((String, LogLevel) -> Void)?

    init() {
        loadAvailableShaders()
    }
    
    /// Reload shaders from metallib and file system
    /// Call this from UI when shaders may have changed
    func reload() {
        loadAvailableShaders()
        // Re-enrich with file metadata if directory is set
        if let dir = shadersDirectory {
            enrichFromFileSystem(directory: dir)
        }
        print("[ShaderStateManager] Reloaded: \(availableShaders.count) shaders")
    }
    
    /// Set the shaders directory for file-based metadata enrichment
    func setShadersDirectory(_ url: URL) {
        shadersDirectory = url
        enrichFromFileSystem(directory: url)
    }
    
    private func loadAvailableShaders() {
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
            .sorted()
        
        availableShaders = shaderNames.map {
            ShaderInfo(name: $0, path: "/metallib/\($0)", metalFunctionName: "fragment_\($0)")
        }
        
        print("[ShaderStateManager] Found \(availableShaders.count) shaders in metallib")
    }
    
    /// Enrich shaders with metadata from file system (.analysis.json, folder info)
    private func enrichFromFileSystem(directory: URL) {
        let fileManager = FileManager.default
        var enrichedShaders: [ShaderInfo] = []
        
        // Build lookup of shader name -> file info
        var fileInfo: [String: (path: URL, folder: String)] = [:]
        
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
                fileInfo[shaderName] = (path: fileURL, folder: folderName)
            }
        }
        
        // Enrich each metallib shader with file info
        for shader in availableShaders {
            if let info = fileInfo[shader.name] {
                // Found matching file - keep shader with updated path
                let updatedShader = ShaderInfo(
                    name: shader.name,
                    path: info.path.path,  // URL to String
                    rating: shader.rating,
                    metalFunctionName: "fragment_\(shader.name)"
                )
                // Store folder as part of path for now (could add folder property to ShaderInfo)
                enrichedShaders.append(updatedShader)
            } else {
                // No file found - keep metallib-only shader
                enrichedShaders.append(shader)
            }
        }
        
        availableShaders = enrichedShaders
        print("[ShaderStateManager] Enriched \(enrichedShaders.count) shaders with file info")
    }
    
    func selectShader(name: String) {
        if let index = availableShaders.firstIndex(where: { $0.name == name }) {
            currentIndex = index
            state = ShaderDisplayState(current: availableShaders[index], isLoaded: true, error: nil, audioTime: state.audioTime, syntheticMouse: state.syntheticMouse)
            logger?("[Shader] ✓ Selected: \(name)", .debug)
        } else {
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
    
    /// Check if a shader name exists in metallib
    func isRenderable(_ name: String) -> Bool {
        availableShaders.contains { $0.name == name }
    }
}

// MARK: - Mask State Manager

/// Manages mask shader selection and state
@MainActor
final class MaskStateManager: ObservableObject {
    @Published var state: ShaderDisplayState = .empty
    
    func selectMask(name: String) {
        let info = ShaderInfo(name: name, path: "/shaders/\(name).metal")
        state = ShaderDisplayState(current: info, isLoaded: true, error: nil, audioTime: 0, syntheticMouse: SIMD2(0.5, 0.5))
    }
}

// MARK: - Image State Manager

/// Manages image display state
@MainActor
final class ImageStateManager: ObservableObject {
    @Published var state: ImageDisplayState = .empty
}

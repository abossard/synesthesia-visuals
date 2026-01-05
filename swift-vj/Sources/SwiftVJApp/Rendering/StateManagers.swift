// StateManagers.swift - Observable state managers for VJ rendering
// Minimal managers for text, shader, mask, and image state

import Foundation
import SwiftUI
import Metal

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
    
    func setLyrics(_ lines: [LyricLine]) {
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
@MainActor
final class ShaderStateManager: ObservableObject {
    @Published var state: ShaderDisplayState = .empty
    @Published private(set) var availableShaders: [ShaderInfo] = []
    
    private(set) var currentIndex: Int = 0
    
    init() {
        loadAvailableShaders()
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
            ShaderInfo(name: $0, path: URL(fileURLWithPath: "/metallib/\($0)"))
        }
        
        print("[ShaderStateManager] Found \(availableShaders.count) shaders")
    }
    
    func selectShader(name: String) {
        if let index = availableShaders.firstIndex(where: { $0.name == name }) {
            currentIndex = index
            state = ShaderDisplayState(current: availableShaders[index], isLoaded: true, error: nil, audioTime: state.audioTime, syntheticMouse: state.syntheticMouse)
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
    
    func loadShaderDirectory(_ url: URL) {
        // Load shader files from directory
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return
        }
        
        let shaderFiles = contents.filter { $0.pathExtension == "metal" || $0.pathExtension == "glsl" }
        availableShaders = shaderFiles.map { 
            ShaderInfo(name: $0.deletingPathExtension().lastPathComponent, path: $0)
        }
        
        if !availableShaders.isEmpty {
            currentIndex = 0
            state = ShaderDisplayState(current: availableShaders[0], isLoaded: true, error: nil, audioTime: 0, syntheticMouse: SIMD2(0.5, 0.5))
        }
    }
}

// MARK: - Mask State Manager

/// Manages mask shader selection and state
@MainActor
final class MaskStateManager: ObservableObject {
    @Published var state: ShaderDisplayState = .empty
    
    func selectMask(name: String) {
        let info = ShaderInfo(name: name, path: URL(fileURLWithPath: "/shaders/\(name).metal"))
        state = ShaderDisplayState(current: info, isLoaded: true, error: nil, audioTime: 0, syntheticMouse: SIMD2(0.5, 0.5))
    }
}

// MARK: - Image State Manager

/// Manages image display state
@MainActor
final class ImageStateManager: ObservableObject {
    @Published var state: ImageDisplayState = .empty
}

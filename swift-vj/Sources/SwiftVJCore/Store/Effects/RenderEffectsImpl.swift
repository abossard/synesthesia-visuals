// RenderEffectsImpl.swift - Rendering effects
// Effects for shader and image management

import Foundation

/// Effects for rendering operations
public enum RenderEffectsImpl {

    /// Load shader via OSC and update render engine
    public static func loadShader(
        _ name: String,
        oscHub: OSCHub?,
        energy: Float = 0.5,
        valence: Float = 0.0
    ) -> Effect<AppAction> {
        .run { send in
            // Send shader load command via OSC
            if let hub = oscHub {
                do {
                    try hub.sendToMagic("/shader/load", values: [name, Float32(energy), Float32(valence)])
                } catch {
                    await send(.ui(.log("Failed to send shader: \(error)", .error)))
                }
            }

            await send(.render(.shaderSelected(name)))
            await send(.ui(.log("Selected shader: \(name)", .info)))
        }
    }

    /// Load images from folder path
    public static func loadImagesFromFolder(
        _ folderPath: String,
        imageManager: ImageStateManagerProtocol?
    ) -> Effect<AppAction> {
        .run { send in
            guard let manager = imageManager else {
                await send(.ui(.log("[Images] ImageManager not available", .error)))
                return
            }

            let url = URL(fileURLWithPath: folderPath)

            guard let files = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            ) else {
                await send(.ui(.log("[Images] Failed to read directory: \(folderPath)", .error)))
                return
            }

            let imageExtensions = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "webp"]
            let imageFiles = files.filter { file in
                imageExtensions.contains(file.pathExtension.lowercased())
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !imageFiles.isEmpty else {
                await send(.ui(.log("[Images] No images found in folder", .warning)))
                return
            }

            // Update image manager state
            await MainActor.run {
                manager.loadImages(imageFiles)
            }

            await send(.ui(.log("[Images] Loaded \(imageFiles.count) images", .info)))
            await send(.render(.imagesLoaded(count: imageFiles.count, folderPath: folderPath)))
        }
    }

    /// Navigate to specific image index
    public static func setImageIndex(
        _ index: Int,
        imageManager: ImageStateManagerProtocol?
    ) -> Effect<AppAction> {
        .fireAndForget {
            await MainActor.run {
                imageManager?.setIndex(index)
            }
        }
    }

    /// Navigate to next image
    public static func nextImage(
        imageManager: ImageStateManagerProtocol?
    ) -> Effect<AppAction> {
        .fireAndForget {
            await MainActor.run {
                imageManager?.nextImage()
            }
        }
    }

    /// Navigate to previous image
    public static func prevImage(
        imageManager: ImageStateManagerProtocol?
    ) -> Effect<AppAction> {
        .fireAndForget {
            await MainActor.run {
                imageManager?.prevImage()
            }
        }
    }

    /// Set image fit mode
    public static func setImageFitMode(
        _ coverMode: Bool,
        imageManager: ImageStateManagerProtocol?
    ) -> Effect<AppAction> {
        .fireAndForget {
            await MainActor.run {
                imageManager?.setCoverMode(coverMode)
            }
        }
    }

    /// Start render engine
    public static func startEngine(
        renderEngine: RenderEngineProtocol?
    ) -> Effect<AppAction> {
        .run { send in
            guard let engine = renderEngine else {
                await send(.ui(.log("[RenderEngine] Not available", .error)))
                return
            }

            do {
                try await engine.start()
                await send(.ui(.log("[RenderEngine] Started", .info)))
            } catch {
                await send(.ui(.log("[RenderEngine] Failed to start: \(error)", .error)))
            }
        }
    }

    /// Stop render engine
    public static func stopEngine(
        renderEngine: RenderEngineProtocol?
    ) -> Effect<AppAction> {
        .fireAndForget {
            await renderEngine?.stop()
        }
    }

    /// Update shader count from shader manager
    public static func updateShaderCount(
        shaderManager: ShaderStateManagerProtocol?
    ) -> Effect<AppAction> {
        .run { send in
            let count = await MainActor.run {
                shaderManager?.availableShaders.count ?? 0
            }
            await send(.render(.shaderCountUpdated(count)))
        }
    }
}

// MARK: - Protocol Abstractions

/// Protocol for ImageStateManager to allow mocking
@MainActor
public protocol ImageStateManagerProtocol: AnyObject, Sendable {
    func loadImages(_ urls: [URL])
    func setIndex(_ index: Int)
    func nextImage()
    func prevImage()
    func setCoverMode(_ cover: Bool)
}

/// Protocol for ShaderStateManager to allow mocking
@MainActor
public protocol ShaderStateManagerProtocol: AnyObject, Sendable {
    var availableShaders: [ShaderInfo] { get }
    func selectShader(name: String)
}

/// Protocol for RenderEngine to allow mocking
public protocol RenderEngineProtocol: AnyObject, Sendable {
    func start() async throws
    func stop() async
}

// ImageTile.swift - Image display tile with crossfade and beat-sync cycling
// Port of ImageTile.pde to Swift

import Foundation
import Metal
import AppKit
import CoreGraphics

/// Image display tile with crossfade transitions
/// Port of ImageTile.pde
final class ImageTile: BaseTile {
    // MARK: - State

    private var state: ImageDisplayState = .empty

    // Image textures
    private var currentTexture: MTLTexture?
    private var nextTexture: MTLTexture?

    // Crossfade animation
    private var crossfadeProgress: Float = 1.0
    private var fadeStartTime: Date?
    private var fadeDurationSec: Float = 0.5
    private var isFading: Bool = false

    // Beat cycling
    private var lastBeat4: Int = 0

    // Loading state
    private var isLoading: Bool = false
    private var loadingTask: Task<Void, Never>?

    // Render pipeline
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var vertexBuffer: MTLBuffer?

    // MARK: - Init

    init(device: MTLDevice) {
        super.init(device: device, config: .image)
        setupPipeline()
    }

    private func setupPipeline() {
        // Create sampler
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = commandQueue.device.makeSamplerState(descriptor: samplerDescriptor)

        // Create fullscreen quad vertices
        let vertices: [Float] = [
            -1, -1, 0, 1,  // bottom-left, uv
            1, -1, 1, 1,   // bottom-right
            -1, 1, 0, 0,   // top-left
            1, 1, 1, 0     // top-right
        ]
        vertexBuffer = commandQueue.device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - State Updates

    func updateState(_ newState: ImageDisplayState) {
        let oldState = state
        state = newState

        // Check if we need to load a new image
        if newState.currentImageURL != oldState.currentImageURL,
           let url = newState.currentImageURL {
            loadImage(url: url)
        }
    }

    // MARK: - Image Loading

    func loadImage(url: URL) {
        loadingTask?.cancel()
        isLoading = true

        loadingTask = Task { [weak self] in
            guard let self = self else { return }

            do {
                let data = try Data(contentsOf: url)
                guard let nsImage = NSImage(data: data),
                      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    await MainActor.run { self.isLoading = false }
                    return
                }

                let texture = try await self.createTexture(from: cgImage)

                await MainActor.run {
                    self.startCrossfade(to: texture)
                    self.isLoading = false
                }
            } catch {
                await MainActor.run { self.isLoading = false }
                print("[ImageTile] Failed to load: \(url.lastPathComponent) - \(error)")
            }
        }
    }

    func loadFolder(url: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return }

        let images = contents
            .filter { isImageFile($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !images.isEmpty else { return }

        state = ImageDisplayState(
            currentImageURL: images.first,
            nextImageURL: nil,
            crossfadeProgress: 1.0,
            isFading: false,
            coverMode: state.coverMode,
            folderImages: images,
            folderIndex: 0,
            beatsPerChange: state.beatsPerChange
        )

        if let first = images.first {
            loadImage(url: first)
        }
    }

    private func isImageFile(_ filename: String) -> Bool {
        let extensions = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp"]
        let ext = filename.lowercased().components(separatedBy: ".").last ?? ""
        return extensions.contains(ext)
    }

    private func createTexture(from cgImage: CGImage) async throws -> MTLTexture {
        let width = cgImage.width
        let height = cgImage.height

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed

        guard let texture = commandQueue.device.makeTexture(descriptor: descriptor) else {
            throw NSError(domain: "ImageTile", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create texture"])
        }

        // Create bitmap context and draw image
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw NSError(domain: "ImageTile", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create context"])
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else {
            throw NSError(domain: "ImageTile", code: 3, userInfo: [NSLocalizedDescriptionKey: "No context data"])
        }

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        texture.replace(region: region, mipmapLevel: 0, withBytes: data, bytesPerRow: width * 4)

        return texture
    }

    // MARK: - Crossfade

    private func startCrossfade(to newTexture: MTLTexture) {
        currentTexture = nextTexture
        nextTexture = newTexture
        crossfadeProgress = 0.0
        fadeStartTime = Date()
        isFading = true
    }

    private func updateCrossfade(deltaTime: Float) {
        guard isFading, let startTime = fadeStartTime else { return }

        let elapsed = Float(Date().timeIntervalSince(startTime))
        crossfadeProgress = min(max(elapsed / fadeDurationSec, 0), 1)
        crossfadeProgress = easeInOutQuad(crossfadeProgress)

        if elapsed >= fadeDurationSec {
            isFading = false
            crossfadeProgress = 1.0
            currentTexture = nextTexture
            nextTexture = nil
        }
    }

    // MARK: - Beat Cycling

    private func updateBeatCycling(audioState: AudioState) {
        guard !state.folderImages.isEmpty,
              state.beatsPerChange > 0,
              state.folderImages.count > 1 else { return }

        if audioState.beat4 != lastBeat4 {
            lastBeat4 = audioState.beat4

            if audioState.beat4 % state.beatsPerChange == 0 {
                nextFolderImage()
            }
        }
    }

    func nextFolderImage() {
        guard !state.folderImages.isEmpty else { return }
        let newIndex = (state.folderIndex + 1) % state.folderImages.count
        state = ImageDisplayState(
            currentImageURL: state.folderImages[newIndex],
            nextImageURL: nil,
            crossfadeProgress: state.crossfadeProgress,
            isFading: state.isFading,
            coverMode: state.coverMode,
            folderImages: state.folderImages,
            folderIndex: newIndex,
            beatsPerChange: state.beatsPerChange
        )
        loadImage(url: state.folderImages[newIndex])
    }

    func prevFolderImage() {
        guard !state.folderImages.isEmpty else { return }
        let newIndex = (state.folderIndex - 1 + state.folderImages.count) % state.folderImages.count
        state = ImageDisplayState(
            currentImageURL: state.folderImages[newIndex],
            nextImageURL: nil,
            crossfadeProgress: state.crossfadeProgress,
            isFading: state.isFading,
            coverMode: state.coverMode,
            folderImages: state.folderImages,
            folderIndex: newIndex,
            beatsPerChange: state.beatsPerChange
        )
        loadImage(url: state.folderImages[newIndex])
    }

    // MARK: - Tile Protocol

    override func update(audioState: AudioState, deltaTime: Float) {
        updateCrossfade(deltaTime: deltaTime)
        updateBeatCycling(audioState: audioState)
    }

    override func render(commandBuffer: MTLCommandBuffer) {
        guard let renderPassDesc = renderPassDescriptor else { return }

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }

        // Draw current image (fading out during crossfade)
        if isFading, let current = currentTexture, let next = nextTexture {
            drawImage(current, alpha: 1.0 - crossfadeProgress, encoder: encoder)
            drawImage(next, alpha: crossfadeProgress, encoder: encoder)
        } else if let current = currentTexture ?? nextTexture {
            drawImage(current, alpha: 1.0, encoder: encoder)
        }

        encoder.endEncoding()
    }

    private func drawImage(_ texture: MTLTexture, alpha: Float, encoder: MTLRenderCommandEncoder) {
        // Simple texture draw with aspect ratio
        // For full implementation, we'd need a proper shader pipeline
        // This is a placeholder that would be replaced with actual Metal shader code

        encoder.setFragmentTexture(texture, index: 0)
        if let sampler = samplerState {
            encoder.setFragmentSamplerState(sampler, index: 0)
        }

        // Note: Full implementation would include:
        // 1. A shader that handles aspect ratio calculation
        // 2. Alpha blending for crossfade
        // 3. Proper vertex transformation
    }

    override var statusString: String {
        if isLoading { return "Loading..." }

        if !state.folderImages.isEmpty {
            let indexInfo = "\(state.folderIndex + 1)/\(state.folderImages.count)"
            let beatInfo = state.beatsPerChange == 0 ? "manual" : "beat:\(state.beatsPerChange)"
            return "Folder \(indexInfo) (\(beatInfo))"
        }

        if let url = state.currentImageURL {
            return url.lastPathComponent
        }

        return "Empty"
    }
}

// MARK: - Image State Manager

/// Manages ImageTile state
@MainActor
final class ImageStateManager: ObservableObject {
    @Published private(set) var state: ImageDisplayState = .empty

    func loadImage(url: URL) {
        state = ImageDisplayState(
            currentImageURL: url,
            nextImageURL: nil,
            crossfadeProgress: 0,
            isFading: true,
            coverMode: state.coverMode,
            folderImages: [],
            folderIndex: 0,
            beatsPerChange: 0
        )
    }

    func loadFolder(url: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return }

        let images = contents
            .filter { isImageFile($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !images.isEmpty else { return }

        state = ImageDisplayState(
            currentImageURL: images.first,
            nextImageURL: nil,
            crossfadeProgress: 0,
            isFading: true,
            coverMode: state.coverMode,
            folderImages: images,
            folderIndex: 0,
            beatsPerChange: state.beatsPerChange
        )
    }

    func setBeatsPerChange(_ beats: Int) {
        state = ImageDisplayState(
            currentImageURL: state.currentImageURL,
            nextImageURL: state.nextImageURL,
            crossfadeProgress: state.crossfadeProgress,
            isFading: state.isFading,
            coverMode: state.coverMode,
            folderImages: state.folderImages,
            folderIndex: state.folderIndex,
            beatsPerChange: max(0, beats)
        )
    }

    func setCoverMode(_ cover: Bool) {
        state = ImageDisplayState(
            currentImageURL: state.currentImageURL,
            nextImageURL: state.nextImageURL,
            crossfadeProgress: state.crossfadeProgress,
            isFading: state.isFading,
            coverMode: cover,
            folderImages: state.folderImages,
            folderIndex: state.folderIndex,
            beatsPerChange: state.beatsPerChange
        )
    }

    func clear() {
        state = .empty
    }

    private func isImageFile(_ filename: String) -> Bool {
        let extensions = ["jpg", "jpeg", "png", "gif", "tif", "tiff", "bmp"]
        let ext = filename.lowercased().components(separatedBy: ".").last ?? ""
        return extensions.contains(ext)
    }
}

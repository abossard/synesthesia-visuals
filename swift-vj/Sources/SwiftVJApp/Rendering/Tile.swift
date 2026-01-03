// Tile.swift - Base tile protocol and implementations for VJ rendering
// Port of Tile.pde to Swift/Metal

import Foundation
import Metal
import MetalKit
import CoreGraphics
import AppKit

// MARK: - Tile Protocol

/// Base protocol for all VJ tiles
/// Each tile renders to its own texture for Syphon output
protocol Tile: AnyObject {
    /// Tile configuration
    var config: TileConfig { get }

    /// Current render texture (may be nil if not initialized)
    var texture: MTLTexture? { get }

    /// Update tile state (called every frame before render)
    func update(audioState: AudioState, deltaTime: Float)

    /// Render to internal texture
    func render(commandBuffer: MTLCommandBuffer)

    /// Status string for display
    var statusString: String { get }
}

// MARK: - Base Tile Implementation

/// Base class providing common tile functionality
class BaseTile: Tile {
    let config: TileConfig
    private(set) var texture: MTLTexture?

    private let device: MTLDevice
    let commandQueue: MTLCommandQueue

    // Render pass descriptor for clearing/drawing
    var renderPassDescriptor: MTLRenderPassDescriptor?

    init(device: MTLDevice, config: TileConfig) {
        self.device = device
        self.config = config
        self.commandQueue = device.makeCommandQueue()!

        setupTexture()
    }

    private func setupTexture() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: config.width,
            height: config.height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        texture = device.makeTexture(descriptor: descriptor)

        // Setup render pass descriptor
        renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor?.colorAttachments[0].texture = texture
        renderPassDescriptor?.colorAttachments[0].loadAction = .clear
        renderPassDescriptor?.colorAttachments[0].storeAction = .store
        renderPassDescriptor?.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    }

    func update(audioState: AudioState, deltaTime: Float) {
        // Override in subclasses
    }

    func render(commandBuffer: MTLCommandBuffer) {
        // Override in subclasses
    }

    var statusString: String {
        config.name
    }
}

// MARK: - Text Tile Base

/// Base class for text-rendering tiles
class TextTile: BaseTile {
    // Text rendering is done via Core Graphics
    private var cgContext: CGContext?
    private var cgTexture: MTLTexture?

    override init(device: MTLDevice, config: TileConfig) {
        super.init(device: device, config: config)
        setupCGContext()
    }

    private func setupCGContext() {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        cgContext = CGContext(
            data: nil,
            width: config.width,
            height: config.height,
            bitsPerComponent: 8,
            bytesPerRow: config.width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )

        // Create texture for CPU->GPU transfer
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: config.width,
            height: config.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .managed

        cgTexture = device.makeTexture(descriptor: descriptor)
    }

    /// Draw text centered at normalized Y position
    func drawText(
        _ text: String,
        fontSize: CGFloat,
        opacity: CGFloat,
        yPosition: CGFloat,
        context: CGContext
    ) {
        guard !text.isEmpty, opacity > 0.01 else { return }

        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(opacity / 255.0)
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        let x = (CGFloat(config.width) - bounds.width) / 2
        let y = CGFloat(config.height) * (1 - yPosition) - bounds.height / 2

        context.saveGState()
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Auto-size font to fit text within max width
    func calcAutoFitFontSize(for text: String, maxWidth: CGFloat, minSize: CGFloat = 24, maxSize: CGFloat = 96) -> CGFloat {
        var size = maxSize

        while size > minSize {
            let font = NSFont.systemFont(ofSize: size, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [.font: font]
            let textSize = (text as NSString).size(withAttributes: attributes)

            if textSize.width <= maxWidth {
                return size
            }
            size -= 2
        }

        return minSize
    }

    /// Upload CG context to texture
    func uploadToTexture(commandBuffer: MTLCommandBuffer) {
        guard let context = cgContext,
              let cgTexture = cgTexture,
              let data = context.data else { return }

        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: config.width, height: config.height, depth: 1)
        )

        cgTexture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: config.width * 4
        )

        // Blit to render texture
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder(),
           let renderTexture = texture {
            blitEncoder.copy(
                from: cgTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: config.width, height: config.height, depth: 1),
                to: renderTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
        }
    }

    /// Clear context
    func clearContext() {
        cgContext?.clear(CGRect(x: 0, y: 0, width: config.width, height: config.height))
    }

    /// Get CGContext for drawing
    var context: CGContext? { cgContext }

    // Make device accessible to subclasses
    var device: MTLDevice {
        // Access via commandQueue which holds a reference
        commandQueue.device
    }
}

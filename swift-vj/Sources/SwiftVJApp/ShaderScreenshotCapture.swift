// ShaderScreenshotCapture.swift - Utility for capturing shader screenshots from Metal textures
// Converts MTLTexture to CGImage/NSImage and saves to disk

import Foundation
import Metal
import AppKit
import CoreGraphics

/// Utility for capturing screenshots of rendered shaders
actor ShaderScreenshotCapture {
    
    private let logger: (String, LogLevel) -> Void
    
    init(logger: @escaping (String, LogLevel) -> Void) {
        self.logger = logger
    }
    
    /// Capture screenshot from Metal texture
    /// - Parameters:
    ///   - texture: The MTLTexture to capture
    ///   - outputPath: Path where to save the PNG file
    ///   - shaderName: Name of shader for logging
    /// - Returns: True if screenshot was captured successfully
    func captureTexture(_ texture: MTLTexture, outputPath: URL, shaderName: String) async -> Bool {
        logger("  📸 Capturing texture: \(texture.width)x\(texture.height) for \(shaderName)", .debug)
        
        // Convert texture to CGImage
        guard let cgImage = textureToCGImage(texture) else {
            logger("  ✗ Failed to convert texture to CGImage for \(shaderName)", .error)
            return false
        }
        
        // Check if image is completely black
        if isImageBlack(cgImage) {
            logger("  ⚠️ BLACK SCREENSHOT detected for \(shaderName)", .warning)
        }
        
        // Convert to NSImage
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: texture.width, height: texture.height))
        
        // Save as PNG
        return await savePNG(image: nsImage, to: outputPath, shaderName: shaderName)
    }
    
    /// Convert MTLTexture to CGImage
    /// - Parameter texture: The Metal texture to convert
    /// - Returns: CGImage or nil if conversion failed
    private func textureToCGImage(_ texture: MTLTexture) -> CGImage? {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4 // BGRA8Unorm format
        
        // Allocate buffer for pixel data
        guard let data = malloc(rowBytes * height) else {
            logger("  ✗ Failed to allocate memory for texture data", .error)
            return nil
        }
        
        // Copy texture data to CPU memory
        texture.getBytes(
            data,
            bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        
        // Create data provider that owns the buffer
        guard let provider = CGDataProvider(
            dataInfo: nil,
            data: data,
            size: rowBytes * height,
            releaseData: { _, data, _ in
                free(data)
            }
        ) else {
            free(data)
            logger("  ✗ Failed to create CGDataProvider", .error)
            return nil
        }
        
        // Create color space
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // BGRA8Unorm format: byte order is little endian, alpha first
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue |
            CGBitmapInfo.byteOrder32Little.rawValue
        )
        
        // Create CGImage
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: rowBytes,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        
        return cgImage
    }
    
    /// Check if image is completely black or nearly black
    /// - Parameter image: The CGImage to check
    /// - Returns: True if image is black
    private func isImageBlack(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        
        // Sample a grid of pixels across the image
        let sampleSize = 10 // 10x10 grid
        let stepX = max(1, width / sampleSize)
        let stepY = max(1, height / sampleSize)
        
        var totalBrightness: CGFloat = 0
        var sampleCount = 0
        
        // Create bitmap context for pixel sampling
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            logger("  ⚠️ Could not create context for black detection", .warning)
            return false
        }
        
        // Draw image to context
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return false }
        let pixelBuffer = data.assumingMemoryBound(to: UInt8.self)
        
        // Sample pixels across the image
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = (y * width + x) * 4
                let b = CGFloat(pixelBuffer[offset]) / 255.0     // Blue (BGRA)
                let g = CGFloat(pixelBuffer[offset + 1]) / 255.0 // Green
                let r = CGFloat(pixelBuffer[offset + 2]) / 255.0 // Red
                // Alpha is at offset + 3
                
                // Calculate brightness (perceived luminance)
                let brightness = 0.299 * r + 0.587 * g + 0.114 * b
                totalBrightness += brightness
                sampleCount += 1
            }
        }
        
        let averageBrightness = totalBrightness / CGFloat(sampleCount)
        
        // Consider black if average brightness is very low (< 5%)
        let isBlack = averageBrightness < 0.05
        
        logger("  🔍 Average brightness: \(String(format: "%.2f%%", averageBrightness * 100)) (threshold: 5%)", .debug)
        
        return isBlack
    }
    
    /// Save NSImage as PNG
    /// - Parameters:
    ///   - image: The image to save
    ///   - url: Output file path
    ///   - shaderName: Shader name for logging
    /// - Returns: True if saved successfully
    private func savePNG(image: NSImage, to url: URL, shaderName: String) async -> Bool {
        // Convert NSImage to PNG data
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
            logger("  ✗ Failed to convert image to PNG data for \(shaderName)", .error)
            return false
        }
        
        do {
            // Ensure parent directory exists
            let parentDir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parentDir.path) {
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                logger("  📁 Created directory: \(parentDir.lastPathComponent)", .debug)
            }
            
            // Write PNG data to file
            try pngData.write(to: url)
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let fileSizeKB = Double(fileSize) / 1024.0
            
            logger("  ✓ Screenshot saved: \(url.lastPathComponent) (\(String(format: "%.1f", fileSizeKB)) KB)", .info)
            return true
        } catch {
            logger("  ✗ Failed to save PNG for \(shaderName): \(error.localizedDescription)", .error)
            return false
        }
    }
}

// MARK: - LogLevel enum (if not already defined)

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

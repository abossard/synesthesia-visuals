import Foundation
import Metal
import CoreText
import CoreGraphics

/// Handles text rendering using Core Text and Metal textures
class TextRenderer {
    private let device: MTLDevice
    private var textTexture: MTLTexture?
    private let textureDescriptor: MTLTextureDescriptor
    
    init(device: MTLDevice) {
        self.device = device
        
        // Create texture descriptor for text rendering (1920x1080)
        textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1920,
            height: 1080,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .renderTarget]
    }
    
    /// Render text to a Metal texture
    /// - Parameters:
    ///   - text: Text to render
    ///   - font: Font name (e.g., "Helvetica")
    ///   - fontSize: Font size in points
    ///   - color: Text color (RGBA)
    ///   - alignment: Text alignment (.center, .left, .right)
    ///   - rect: Frame to render text in
    /// - Returns: Metal texture with rendered text, or nil on failure
    func renderText(
        text: String,
        font: String = "Helvetica",
        fontSize: CGFloat = 48,
        color: (r: Float, g: Float, b: Float, a: Float) = (1, 1, 1, 1),
        alignment: NSTextAlignment = .center,
        rect: CGRect
    ) -> MTLTexture? {
        // Create bitmap context
        let width = Int(textureDescriptor.width)
        let height = Int(textureDescriptor.height)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            NSLog("ERROR: Failed to create bitmap context")
            return nil
        }
        
        // Clear to transparent black
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        
        // Setup text attributes
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = alignment
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: font, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor(
                red: CGFloat(color.r),
                green: CGFloat(color.g),
                blue: CGFloat(color.b),
                alpha: CGFloat(color.a)
            ),
            .paragraphStyle: paragraphStyle
        ]
        
        // Draw text
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        
        // Flip coordinate system (Core Text uses bottom-left origin)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedString.length), path, nil)
        CTFrameDraw(frame, context)
        
        // Create Metal texture from bitmap
        guard let data = context.data else {
            NSLog("ERROR: Failed to get bitmap data")
            return nil
        }
        
        let texture = device.makeTexture(descriptor: textureDescriptor)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture?.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: bytesPerRow
        )
        
        return texture
    }
    
    /// Render multi-line text with word wrapping
    func renderWrappedText(
        text: String,
        font: String = "Helvetica",
        fontSize: CGFloat = 48,
        color: (r: Float, g: Float, b: Float, a: Float) = (1, 1, 1, 1),
        alignment: NSTextAlignment = .center,
        maxWidth: CGFloat = 1600,
        position: (x: CGFloat, y: CGFloat) = (160, 100)
    ) -> MTLTexture? {
        let rect = CGRect(
            x: position.x,
            y: position.y,
            width: maxWidth,
            height: CGFloat(textureDescriptor.height) - position.y - 100
        )
        
        return renderText(
            text: text,
            font: font,
            fontSize: fontSize,
            color: color,
            alignment: alignment,
            rect: rect
        )
    }
}

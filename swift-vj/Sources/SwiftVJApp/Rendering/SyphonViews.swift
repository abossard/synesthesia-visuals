// SyphonViews.swift - SwiftUI views for displaying Syphon server output
// UI preview components that consume headless rendering via Syphon clients

import SwiftUI
import Metal
import MetalKit
import SyphonKit

// MARK: - Syphon Thumbnail View

/// SwiftUI view that displays a Syphon server's output
/// This is the ONLY way UI should display rendered tiles - via Syphon client
struct SyphonThumbnailView: View {
    let serverName: String
    
    @State private var previewImage: NSImage?
    @State private var isConnected: Bool = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                if let image = previewImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "video.slash")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text(serverName)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .onAppear {
            startReceiving()
        }
        .onReceive(Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()) { _ in
            updatePreview()
        }
    }
    
    private func startReceiving() {
        updatePreview()
    }
    
    private func updatePreview() {
        Task { @MainActor in
            guard let texture = getSyphonTexture() else {
                isConnected = false
                return
            }
            
            isConnected = true
            if let image = textureToNSImage(texture) {
                previewImage = image
            }
        }
    }
    
    private func getSyphonTexture() -> MTLTexture? {
        // Find and connect to the server
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        
        let receiver = SyphonReceiver(device: device)
        
        // Try to connect to the server by name
        // Server name format: "SwiftVJ/Shader" -> app="SwiftVJ", server="Shader"
        let parts = serverName.split(separator: "/")
        let appName = parts.first.map(String.init) ?? "SwiftVJ"
        let name = parts.count > 1 ? String(parts[1]) : nil
        
        if receiver.connect(appName: appName, serverName: name) {
            return receiver.currentFrame()
        }
        
        return nil
    }
    
    private func textureToNSImage(_ texture: MTLTexture) -> NSImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        
        // For private storage textures, we need to copy to a readable texture first
        var readableTexture: MTLTexture = texture
        
        if texture.storageMode == .private {
            // Create a managed texture to copy into
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: texture.pixelFormat,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.storageMode = .managed
            descriptor.usage = .shaderRead
            
            let device = texture.device
            guard let managedTexture = device.makeTexture(descriptor: descriptor),
                  let commandQueue = device.makeCommandQueue(),
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
                return nil
            }
            
            // Copy from private to managed texture
            blitEncoder.copy(
                from: texture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: managedTexture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.synchronize(resource: managedTexture)
            blitEncoder.endEncoding()
            
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            
            readableTexture = managedTexture
        }
        
        // Read texture data from the readable texture
        var imageBytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        readableTexture.getBytes(
            &imageBytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )
        
        // Create CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: &imageBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        
        guard let cgImage = context.makeImage() else { return nil }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        SyphonThumbnailView(serverName: "SwiftVJ/Shader")
            .aspectRatio(16/9, contentMode: .fit)
            .frame(height: 200)
        
        SyphonThumbnailView(serverName: "SwiftVJ/Lyrics")
            .aspectRatio(16/9, contentMode: .fit)
            .frame(height: 200)
    }
    .padding()
}

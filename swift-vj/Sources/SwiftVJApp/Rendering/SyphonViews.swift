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
    
    @StateObject private var receiver = SyphonReceiverHolder()
    @State private var previewImage: NSImage?
    
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
                        Image(systemName: receiver.isConnected ? "antenna.radiowaves.left.and.right" : "video.slash")
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
            receiver.connect(serverName: serverName)
        }
        .onDisappear {
            receiver.disconnect()
        }
        .onReceive(Timer.publish(every: 1.0/30.0, on: .main, in: .common).autoconnect()) { _ in
            updatePreview()
        }
    }
    
    private func updatePreview() {
        guard let texture = receiver.currentFrame() else { return }
        
        if let image = textureToNSImage(texture) {
            previewImage = image
        }
    }
    
    private func textureToNSImage(_ texture: MTLTexture) -> NSImage? {
        let width = texture.width
        let height = texture.height
        let bytesPerRow = width * 4
        
        // For private storage textures, we need to copy to a readable texture first
        var readableTexture: MTLTexture = texture
        
        if texture.storageMode == .private {
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
        
        var imageBytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        readableTexture.getBytes(
            &imageBytes,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                           size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0
        )
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        // BGRA texture format: use 32Little byte order + premultipliedFirst alpha
        // This matches Metal's .bgra8Unorm format
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        
        guard let context = CGContext(
            data: &imageBytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        guard let cgImage = context.makeImage() else { return nil }
        
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }
}

// MARK: - Syphon Receiver Holder

/// Observable holder for SyphonReceiver to persist across view updates
final class SyphonReceiverHolder: ObservableObject {
    private var receiver: SyphonReceiver?
    private let device: MTLDevice?
    private var targetServerName: String = ""
    private var retryCount = 0
    private let maxRetries = 10
    
    @Published var isConnected: Bool = false
    
    init() {
        self.device = MTLCreateSystemDefaultDevice()
    }
    
    func connect(serverName: String) {
        guard let device = device else { return }
        
        targetServerName = serverName
        receiver = SyphonReceiver(device: device)
        
        // Simple server name lookup (e.g., "Shader") - app name is auto-detected
        if receiver?.connect(appName: nil, serverName: serverName) == true {
            isConnected = true
            retryCount = 0
            print("[SyphonThumbnail] Connected to \(serverName)")
        } else {
            isConnected = false
            // Retry after a delay (server might not be ready yet)
            if retryCount < maxRetries {
                retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.connect(serverName: serverName)
                }
            }
        }
    }
    
    func disconnect() {
        receiver?.disconnect()
        receiver = nil
        isConnected = false
    }
    
    func currentFrame() -> MTLTexture? {
        // Try to reconnect if not connected
        if !isConnected && retryCount < maxRetries {
            connect(serverName: targetServerName)
        }
        return receiver?.currentFrame()
    }
}

// MARK: - Preview

#Preview {
    VStack {
        SyphonThumbnailView(serverName: "Shader")
            .aspectRatio(16/9, contentMode: .fit)
            .frame(height: 200)
        
        SyphonThumbnailView(serverName: "Lyrics")
            .aspectRatio(16/9, contentMode: .fit)
            .frame(height: 200)
    }
    .padding()
}

// ShadertoyBindings.swift - Metal argument buffer bindings for stable ABI
// Reference: https://developer.apple.com/documentation/metal/improving-cpu-performance-by-using-argument-buffers

import Foundation
import Metal
import simd

// MARK: - Binding Constants

/// Fixed binding indices for stable ABI across all shaders
public enum ShadertoyBindingIndex {
    /// Uniform buffer binding index
    public static let uniforms: Int = 0

    /// Texture binding indices (iChannel0-3)
    public static let texture0: Int = 1
    public static let texture1: Int = 2
    public static let texture2: Int = 3
    public static let texture3: Int = 4

    /// Sampler binding indices
    public static let sampler0: Int = 0
    public static let sampler1: Int = 1
    public static let sampler2: Int = 2
    public static let sampler3: Int = 3

    /// Argument buffer binding index (when using argument buffers)
    public static let argumentBuffer: Int = 0
}

// MARK: - Sampler Cache

/// Cache for Metal samplers with various configurations
public final class SamplerCache: @unchecked Sendable {
    private let device: MTLDevice
    private var cache: [SamplerKey: MTLSamplerState] = [:]
    private let lock = NSLock()

    /// Key for sampler lookup
    private struct SamplerKey: Hashable {
        let filter: FilterMode
        let wrap: WrapMode
        let mipmap: Bool
    }

    public init(device: MTLDevice) {
        self.device = device
    }

    /// Get or create a sampler with the specified configuration
    public func sampler(filter: FilterMode, wrap: WrapMode) -> MTLSamplerState? {
        let key = SamplerKey(filter: filter, wrap: wrap, mipmap: filter == .mipmap)

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[key] {
            return cached
        }

        let descriptor = MTLSamplerDescriptor()

        // Min/Mag filter
        switch filter {
        case .nearest:
            descriptor.minFilter = .nearest
            descriptor.magFilter = .nearest
            descriptor.mipFilter = .notMipmapped
        case .linear:
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .notMipmapped
        case .mipmap:
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
        }

        // Wrap mode
        let mtlWrap: MTLSamplerAddressMode
        switch wrap {
        case .clamp:
            mtlWrap = .clampToEdge
        case .repeat:
            mtlWrap = .repeat
        case .mirror:
            mtlWrap = .mirrorRepeat
        }
        descriptor.sAddressMode = mtlWrap
        descriptor.tAddressMode = mtlWrap
        descriptor.rAddressMode = mtlWrap

        // Create sampler
        let sampler = device.makeSamplerState(descriptor: descriptor)
        cache[key] = sampler
        return sampler
    }

    /// Default linear/repeat sampler
    public var defaultSampler: MTLSamplerState? {
        sampler(filter: .linear, wrap: .repeat)
    }
}

// MARK: - Dummy Resources

/// Provides default 1x1 black textures for unbound channels
public final class DummyResources: @unchecked Sendable {
    private let device: MTLDevice

    /// 1x1 black 2D texture
    public let blackTexture2D: MTLTexture?

    /// 1x1 black cube texture
    public let blackTextureCube: MTLTexture?

    /// Default sampler (linear, repeat)
    public let defaultSampler: MTLSamplerState?

    public init(device: MTLDevice) {
        self.device = device

        // Create 1x1 black 2D texture
        let desc2D = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        desc2D.usage = [.shaderRead]
        desc2D.storageMode = .shared

        if let texture = device.makeTexture(descriptor: desc2D) {
            let black: [UInt8] = [0, 0, 0, 255]
            texture.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1)),
                mipmapLevel: 0,
                withBytes: black,
                bytesPerRow: 4
            )
            self.blackTexture2D = texture
        } else {
            self.blackTexture2D = nil
        }

        // Create 1x1 black cube texture
        let descCube = MTLTextureDescriptor.textureCubeDescriptor(
            pixelFormat: .rgba8Unorm,
            size: 1,
            mipmapped: false
        )
        descCube.usage = [.shaderRead]
        descCube.storageMode = .shared

        if let texture = device.makeTexture(descriptor: descCube) {
            let black: [UInt8] = [0, 0, 0, 255]
            for face in 0..<6 {
                texture.replace(
                    region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: 1, height: 1, depth: 1)),
                    mipmapLevel: 0,
                    slice: face,
                    withBytes: black,
                    bytesPerRow: 4,
                    bytesPerImage: 4
                )
            }
            self.blackTextureCube = texture
        } else {
            self.blackTextureCube = nil
        }

        // Create default sampler
        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .repeat
        samplerDesc.tAddressMode = .repeat
        self.defaultSampler = device.makeSamplerState(descriptor: samplerDesc)
    }
}

// MARK: - Pass Resource Set

/// Complete resource set for a single render pass
public struct PassResourceSet {
    /// Uniform buffer
    public let uniformBuffer: MTLBuffer

    /// Textures for channels 0-3
    public var textures: [MTLTexture?]

    /// Samplers for channels 0-3
    public var samplers: [MTLSamplerState?]

    /// Argument buffer (optional, for argument buffer path)
    public var argumentBuffer: MTLBuffer?

    public init(uniformBuffer: MTLBuffer) {
        self.uniformBuffer = uniformBuffer
        self.textures = [nil, nil, nil, nil]
        self.samplers = [nil, nil, nil, nil]
        self.argumentBuffer = nil
    }

    /// Bind resources to a render encoder (traditional path)
    public func bind(to encoder: MTLRenderCommandEncoder, dummy: DummyResources) {
        // Bind uniform buffer
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: ShadertoyBindingIndex.uniforms)

        // Bind textures (use dummy if nil)
        for i in 0..<4 {
            let texture = textures[i] ?? dummy.blackTexture2D
            encoder.setFragmentTexture(texture, index: i + 1)
        }

        // Bind samplers (use default if nil)
        for i in 0..<4 {
            let sampler = samplers[i] ?? dummy.defaultSampler
            encoder.setFragmentSamplerState(sampler, index: i)
        }
    }
}

// MARK: - Argument Buffer Encoder

/// Encodes resources into Metal argument buffers for reduced CPU overhead
/// Reference: https://developer.apple.com/documentation/metal/managing-groups-of-resources-with-argument-buffers
public final class ArgumentBufferEncoder: @unchecked Sendable {
    private let device: MTLDevice
    private let argumentEncoder: MTLArgumentEncoder?
    private let encodedLength: Int

    public init(device: MTLDevice, function: MTLFunction, bufferIndex: Int = 0) {
        self.device = device

        // Create argument encoder from function reflection
        if let encoder = function.makeArgumentEncoder(bufferIndex: bufferIndex) {
            self.argumentEncoder = encoder
            self.encodedLength = encoder.encodedLength
        } else {
            self.argumentEncoder = nil
            self.encodedLength = 0
        }
    }

    /// Create an argument buffer
    public func createArgumentBuffer() -> MTLBuffer? {
        guard encodedLength > 0 else { return nil }
        return device.makeBuffer(length: encodedLength, options: .storageModeShared)
    }

    /// Encode resources into an argument buffer
    public func encode(
        into buffer: MTLBuffer,
        uniformBuffer: MTLBuffer,
        textures: [MTLTexture?],
        samplers: [MTLSamplerState?],
        dummy: DummyResources
    ) {
        guard let encoder = argumentEncoder else { return }

        encoder.setArgumentBuffer(buffer, offset: 0)

        // Encode uniform buffer at index 0
        encoder.setBuffer(uniformBuffer, offset: 0, index: 0)

        // Encode textures at indices 1-4
        for i in 0..<4 {
            let texture = textures[i] ?? dummy.blackTexture2D
            encoder.setTexture(texture, index: i + 1)
        }

        // Encode samplers at indices 5-8
        for i in 0..<4 {
            let sampler = samplers[i] ?? dummy.defaultSampler
            encoder.setSamplerState(sampler, index: i + 5)
        }
    }
}

// MARK: - Resource Manager

/// Manages all GPU resources for shader rendering
public actor ResourceManager {
    private let device: MTLDevice
    private let dummyResources: DummyResources
    private let samplerCache: SamplerCache

    /// Uniform buffer pool for reuse
    private var uniformBufferPool: [MTLBuffer] = []
    private let uniformBufferSize = MemoryLayout<ShadertoyUniformBuffer>.stride

    /// Loaded texture cache
    private var textureCache: [URL: MTLTexture] = [:]

    public init(device: MTLDevice) {
        self.device = device
        self.dummyResources = DummyResources(device: device)
        self.samplerCache = SamplerCache(device: device)
    }

    /// Get dummy resources
    public var dummy: DummyResources { dummyResources }

    /// Get or create a uniform buffer
    public func acquireUniformBuffer() -> MTLBuffer? {
        if let buffer = uniformBufferPool.popLast() {
            return buffer
        }
        return device.makeBuffer(length: uniformBufferSize, options: .storageModeShared)
    }

    /// Return a uniform buffer to the pool
    public func releaseUniformBuffer(_ buffer: MTLBuffer) {
        uniformBufferPool.append(buffer)
    }

    /// Get a sampler for the specified configuration
    public func sampler(filter: FilterMode, wrap: WrapMode) -> MTLSamplerState? {
        samplerCache.sampler(filter: filter, wrap: wrap)
    }

    /// Load a texture from file
    public func loadTexture(from url: URL) async throws -> MTLTexture? {
        if let cached = textureCache[url] {
            return cached
        }

        // Load using MTKTextureLoader
        let loader = MTKTextureLoaderWrapper(device: device)
        let texture = try await loader.loadTexture(from: url)

        if let texture = texture {
            textureCache[url] = texture
        }

        return texture
    }

    /// Create a render target texture
    public func createRenderTarget(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private

        return device.makeTexture(descriptor: descriptor)
    }

    /// Create a pair of textures for ping-pong rendering
    public func createPingPongPair(width: Int, height: Int, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> (MTLTexture?, MTLTexture?) {
        let a = createRenderTarget(width: width, height: height, pixelFormat: pixelFormat)
        let b = createRenderTarget(width: width, height: height, pixelFormat: pixelFormat)
        return (a, b)
    }
}

// MARK: - Texture Loader Wrapper

/// Wrapper for MTKTextureLoader (requires MetalKit)
private final class MTKTextureLoaderWrapper {
    private let device: MTLDevice

    init(device: MTLDevice) {
        self.device = device
    }

    func loadTexture(from url: URL) async throws -> MTLTexture? {
        // Simple texture loading using Core Graphics
        guard let dataProvider = CGDataProvider(url: url as CFURL),
              let cgImage = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) ?? CGImage(
                jpegDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        // Create bitmap context and draw
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var imageData = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &imageData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        texture.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0), size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0,
            withBytes: imageData,
            bytesPerRow: bytesPerRow
        )

        return texture
    }
}

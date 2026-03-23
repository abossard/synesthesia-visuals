import AppKit
import Metal
import MetalKit
import os.lock

/// Thread-safe async texture cache for Metal image rendering.
///
/// Provides non-blocking texture reads for the render thread while loading
/// images on a background queue. Uses LRU eviction to bound memory.
///
/// Two-method public API:
/// - `texture(for:)` — instant non-blocking read (call from render thread)
/// - `requestLoad(urls:)` — triggers background loading for uncached URLs
final class TextureCache: @unchecked Sendable {

    private struct CacheEntry: @unchecked Sendable {
        let texture: MTLTexture
        var lastAccess: UInt64
    }

    private let device: MTLDevice
    private let textureLoader: MTKTextureLoader
    private let loadQueue = DispatchQueue(label: "TextureCache.load", qos: .userInitiated)

    private let cache: OSAllocatedUnfairLock<[URL: CacheEntry]>
    private let pending: OSAllocatedUnfairLock<Set<URL>>
    private var accessCounter: UInt64 = 0
    private let maxEntries: Int

    var logger: ((String) -> Void)?

    init(device: MTLDevice, maxEntries: Int = 20) {
        self.device = device
        self.textureLoader = MTKTextureLoader(device: device)
        self.maxEntries = maxEntries
        self.cache = OSAllocatedUnfairLock(initialState: [:])
        self.pending = OSAllocatedUnfairLock(initialState: [])
    }

    /// Non-blocking texture read. Returns cached texture or nil if not yet loaded.
    func texture(for url: URL) -> MTLTexture? {
        let result: CacheEntry? = cache.withLock { entries in
            guard var entry = entries[url] else { return nil }
            entry.lastAccess = accessCounter
            accessCounter += 1
            entries[url] = entry
            return entry
        }
        return result?.texture
    }

    /// Request background loading for URLs not already cached or in-flight.
    func requestLoad(urls: [URL]) {
        let urlsToLoad = pending.withLock { pendingSet in
            urls.filter { url in
                let isCached = cache.withLock { $0[url] != nil }
                let isPending = pendingSet.contains(url)
                if !isCached && !isPending {
                    pendingSet.insert(url)
                    return true
                }
                return false
            }
        }

        for url in urlsToLoad {
            loadQueue.async { [weak self] in
                self?.loadTexture(from: url)
            }
        }
    }

    /// Evict all cached textures.
    func clear() {
        cache.withLock { $0.removeAll() }
        pending.withLock { $0.removeAll() }
    }

    // MARK: - Private

    private func loadTexture(from url: URL) {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            logger?("[TextureCache] ❌ Failed to load image: \(url.lastPathComponent)")
            pending.withLock { $0.remove(url) }
            return
        }

        do {
            let texture = try textureLoader.newTexture(cgImage: cgImage, options: [
                .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
                .SRGB: false,
                .origin: MTKTextureLoader.Origin.bottomLeft
            ])

            let entry = CacheEntry(texture: texture, lastAccess: 0)
            cache.withLock { entries in
                entries[url] = CacheEntry(texture: entry.texture, lastAccess: accessCounter)
                accessCounter += 1
                evictIfNeeded(&entries)
            }
            pending.withLock { $0.remove(url) }
            logger?("[TextureCache] ✓ Loaded: \(url.lastPathComponent)")
        } catch {
            logger?("[TextureCache] ❌ Texture error: \(error.localizedDescription)")
            pending.withLock { $0.remove(url) }
        }
    }

    private func evictIfNeeded(_ entries: inout [URL: CacheEntry]) {
        while entries.count > maxEntries {
            if let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) {
                entries.removeValue(forKey: oldest.key)
                logger?("[TextureCache] Evicted: \(oldest.key.lastPathComponent)")
            } else {
                break
            }
        }
    }
}

# Syphon Integration Guide

## Overview
Syphon is a macOS framework for sharing frames between applications in real-time. SwiftVJ uses Syphon to output multiple channels (shader, lyrics, refrain, song info) that can be consumed by VJ software like Magic Music Visuals or VDMX.

## Integration Steps

### 1. Add Syphon Framework

#### Option A: Git Submodule (Recommended)
```bash
cd swift-vj
git submodule add https://github.com/Syphon/Syphon-Framework.git Frameworks/Syphon
```

#### Option B: Pre-built Binary
Download the latest Syphon.framework from the [releases page](https://github.com/Syphon/Syphon-Framework/releases) and place in `swift-vj/Frameworks/`.

### 2. Update Package.swift

Add framework search path:
```swift
.executableTarget(
    name: "SwiftVJ",
    dependencies: [
        .product(name: "SwiftOSC", package: "SwiftOSC")
    ],
    path: "Sources/SwiftVJ",
    linkerSettings: [
        .unsafeFlags([
            "-F", "Frameworks",
            "-framework", "Syphon"
        ])
    ]
)
```

### 3. Configure Bridging Header

Uncomment the import in `SwiftVJ-Bridging-Header.h`:
```objc
#import <Syphon/Syphon.h>
```

### 4. Implement Syphon Servers in MetalRenderEngine

Add to `MetalRenderEngine.swift`:

```swift
// At top of file, after imports
typealias SyphonMetalServer = AnyObject  // Will be replaced with actual type

class MetalRenderEngine: NSObject, MTKViewDelegate {
    // ... existing code ...
    
    // Replace placeholder with actual Syphon servers
    private var syphonShader: SyphonMetalServer?
    private var syphonFullLyrics: SyphonMetalServer?
    private var syphonRefrain: SyphonMetalServer?
    private var syphonSongInfo: SyphonMetalServer?
    
    init?(frame: NSRect) {
        // ... existing init code ...
        
        // Initialize Syphon servers (after super.init())
        syphonShader = SyphonMetalServer(
            name: "ShaderOutput",
            device: device,
            colorPixelFormat: .bgra8Unorm
        )
        
        syphonFullLyrics = SyphonMetalServer(
            name: "KaraokeFullLyrics",
            device: device,
            colorPixelFormat: .bgra8Unorm
        )
        
        syphonRefrain = SyphonMetalServer(
            name: "KaraokeRefrain",
            device: device,
            colorPixelFormat: .bgra8Unorm
        )
        
        syphonSongInfo = SyphonMetalServer(
            name: "KaraokeSongInfo",
            device: device,
            colorPixelFormat: .bgra8Unorm
        )
    }
    
    func draw(in view: MTKView) {
        // ... existing rendering code ...
        
        // Publish to Syphon servers
        if let texture = shaderRenderTarget {
            syphonShader?.publishFrameTexture(
                texture,
                onCommandBuffer: commandBuffer,
                imageRegion: NSRect(x: 0, y: 0, width: texture.width, height: texture.height),
                flipped: false
            )
        }
        
        if let texture = fullLyricsTarget {
            syphonFullLyrics?.publishFrameTexture(
                texture,
                onCommandBuffer: commandBuffer,
                imageRegion: NSRect(x: 0, y: 0, width: texture.width, height: texture.height),
                flipped: false
            )
        }
        
        if let texture = refrainTarget {
            syphonRefrain?.publishFrameTexture(
                texture,
                onCommandBuffer: commandBuffer,
                imageRegion: NSRect(x: 0, y: 0, width: texture.width, height: texture.height),
                flipped: false
            )
        }
        
        if let texture = songInfoTarget {
            syphonSongInfo?.publishFrameTexture(
                texture,
                onCommandBuffer: commandBuffer,
                imageRegion: NSRect(x: 0, y: 0, width: texture.width, height: texture.height),
                flipped: false
            )
        }
        
        // ... commit command buffer ...
    }
    
    func cleanup() {
        // Cleanup servers
        syphonShader = nil
        syphonFullLyrics = nil
        syphonRefrain = nil
        syphonSongInfo = nil
    }
}
```

### 5. Verify Syphon Output

#### Using Simple Server Browser
```bash
# Download Syphon's Simple Server Browser from:
# https://github.com/Syphon/Simple/releases
```

#### Using Magic Music Visuals
1. Launch SwiftVJ
2. Open Magic Music Visuals
3. Add Syphon input sources:
   - Look for "SwiftVJ - ShaderOutput"
   - Look for "SwiftVJ - KaraokeFullLyrics"
   - Look for "SwiftVJ - KaraokeRefrain"
   - Look for "SwiftVJ - KaraokeSongInfo"

## Troubleshooting

### Framework Not Found
- Verify framework is in `swift-vj/Frameworks/Syphon.framework`
- Check that framework search paths are correct
- Ensure bridging header is configured in build settings

### Syphon Servers Not Appearing
- Check Console.app for Syphon errors
- Verify Metal textures are being created correctly
- Ensure command buffer is committed before publishing
- Check that textures have proper pixel format (.bgra8Unorm)

### Performance Issues
- Profile with Instruments (Metal System Trace)
- Check texture sizes match output resolution
- Verify command buffers are being reused efficiently
- Consider using MTLHeap for texture allocation

## Metal + Syphon Best Practices

1. **Texture Format**: Always use `.bgra8Unorm` for Syphon compatibility
2. **Command Buffer**: Publish textures before committing the command buffer
3. **Region**: Specify exact texture region to avoid unnecessary copying
4. **Flipped**: Set to `false` for Metal textures (already in correct orientation)
5. **Resolution**: Match texture size to Syphon output requirements (1920x1080 for HD)

## References

- [Syphon Framework GitHub](https://github.com/Syphon/Syphon-Framework)
- [SyphonMetalServer.h](https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h)
- [Syphon Swift Example](https://github.com/pixlwave/Syphon-Swift-Example)
- [Metal Programming Guide](https://developer.apple.com/metal/)

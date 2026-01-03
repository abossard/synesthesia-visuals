# Syphon Integration Guide for SwiftVJ

> Build and integrate Syphon.framework as an XCFramework for SPM-based projects

## Overview

Syphon is an open-source macOS framework for sharing GPU textures between applications with zero latency. SwiftVJ uses Syphon to output VJ visuals to OBS, Resolume, Magic Music Visuals, etc.

**Current Status**: SwiftVJ uses a stub implementation. Follow this guide to enable real Syphon output.

---

## 1. Build Syphon XCFramework

### Prerequisites
- Xcode 14+ with Command Line Tools
- macOS 11+ (Big Sur or later)
- Git

### Step 1: Clone Syphon-Framework

```bash
cd /tmp
git clone https://github.com/Syphon/Syphon-Framework.git
cd Syphon-Framework
```

### Step 2: Build Universal XCFramework

Create a build script `build_xcframework.sh`:

```bash
#!/bin/bash
set -e

# Configuration
PROJECT="Syphon.xcodeproj"
SCHEME="Syphon"
OUTPUT_DIR="build"
XCFRAMEWORK_NAME="Syphon.xcframework"

# Clean
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Archive for Apple Silicon (arm64)
echo "Building for arm64..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS,arch=arm64" \
    -archivePath "$OUTPUT_DIR/Syphon-arm64.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Create XCFramework
echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -framework "$OUTPUT_DIR/Syphon-x86_64.xcarchive/Products/Library/Frameworks/Syphon.framework" \
    -framework "$OUTPUT_DIR/Syphon-arm64.xcarchive/Products/Library/Frameworks/Syphon.framework" \
    -output "$OUTPUT_DIR/$XCFRAMEWORK_NAME"

echo "✅ Created: $OUTPUT_DIR/$XCFRAMEWORK_NAME"
```

Run the script:

```bash
chmod +x build_xcframework.sh
./build_xcframework.sh
```

### Step 3: Copy XCFramework to Project

```bash
cp -R build/Syphon.xcframework /path/to/swift-vj/Frameworks/
```

---

## 2. Update Package.swift

Add the XCFramework as a binary target:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftVJ",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwiftVJApp", targets: ["SwiftVJApp"]),
        .library(name: "SwiftVJCore", targets: ["SwiftVJCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orchetect/OSCKit", from: "0.6.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        // Syphon XCFramework
        .binaryTarget(
            name: "Syphon",
            path: "Frameworks/Syphon.xcframework"
        ),
        
        // Syphon Swift wrapper
        .target(
            name: "SyphonKit",
            dependencies: ["Syphon"],
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("IOSurface"),
            ]
        ),
        
        // SwiftUI app
        .executableTarget(
            name: "SwiftVJApp",
            dependencies: [
                "SwiftVJCore",
                "SyphonKit",
            ]
        ),
        
        // Core library
        .target(
            name: "SwiftVJCore",
            dependencies: [
                .product(name: "OSCKit", package: "OSCKit"),
            ]
        ),
    ]
)
```

---

## 3. Create SyphonKit Swift Wrapper

Create `Sources/SyphonKit/SyphonSender.swift`:

```swift
import Foundation
import Metal
import Syphon

/// Thin Swift wrapper around SyphonMetalServer
public final class SyphonSender {
    private let server: SyphonMetalServer
    
    /// Name visible to Syphon clients
    public var name: String { server.name }
    
    /// Create a Syphon sender
    /// - Parameters:
    ///   - device: Metal device to use
    ///   - name: Server name (e.g., "SwiftVJ/Shader")
    public init(device: MTLDevice, name: String) {
        self.server = SyphonMetalServer(name: name, device: device, options: nil)
    }
    
    deinit {
        server.stop()
    }
    
    /// Publish a Metal texture to Syphon
    /// - Parameters:
    ///   - texture: The MTLTexture to share (must have .shaderRead usage)
    ///   - commandBuffer: Active command buffer (Syphon schedules its copy here)
    ///   - region: Region to publish (nil = full texture)
    ///   - flipped: Whether to flip Y axis (default false)
    public func publish(
        texture: MTLTexture,
        on commandBuffer: MTLCommandBuffer,
        region: MTLRegion? = nil,
        flipped: Bool = false
    ) {
        let imageRegion = region ?? MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: texture.width, height: texture.height, depth: 1)
        )
        
        server.publishFrameTexture(
            texture,
            onCommandBuffer: commandBuffer,
            imageRegion: imageRegion,
            flipped: flipped
        )
    }
    
    /// Convenience: publish with auto-created command buffer
    public func publish(texture: MTLTexture, commandQueue: MTLCommandQueue) {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        publish(texture: texture, on: commandBuffer)
        commandBuffer.commit()
    }
    
    /// Stop the server
    public func stop() {
        server.stop()
    }
}
```

Create `Sources/SyphonKit/SyphonReceiver.swift` (optional):

```swift
import Foundation
import Metal
import Syphon

/// Thin Swift wrapper around SyphonMetalClient
public final class SyphonReceiver {
    private var client: SyphonMetalClient?
    private let device: MTLDevice
    
    /// Currently connected server description
    public private(set) var serverDescription: [String: Any]?
    
    /// Whether connected to a server
    public var isConnected: Bool { client?.isValid ?? false }
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    deinit {
        client?.stop()
    }
    
    /// Get list of available Syphon servers
    public static var availableServers: [[String: Any]] {
        SyphonServerDirectory.shared().servers as? [[String: Any]] ?? []
    }
    
    /// Connect to a Syphon server
    /// - Parameter serverDescription: Server description from `availableServers`
    public func connect(to serverDescription: [String: Any]) {
        client?.stop()
        client = SyphonMetalClient(
            serverDescription: serverDescription,
            device: device,
            options: nil,
            newFrameHandler: nil
        )
        self.serverDescription = serverDescription
    }
    
    /// Get the current frame as a Metal texture
    /// Returns nil if no frame is available
    public func currentFrame() -> MTLTexture? {
        guard let client = client, client.isValid else { return nil }
        return client.newFrameImage()
    }
    
    /// Disconnect from current server
    public func disconnect() {
        client?.stop()
        client = nil
        serverDescription = nil
    }
}
```

---

## 4. Update SyphonOutput.swift

Replace the stub implementation in `Sources/SwiftVJApp/Rendering/SyphonOutput.swift`:

```swift
import Foundation
import Metal
import SyphonKit  // <-- Change this import

// Remove SyphonMetalServerStub and SyphonServerProtocol

/// Manages Syphon servers for all tile outputs
final class SyphonOutputManager {
    private var servers: [String: SyphonSender] = [:]
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    
    var isEnabled: Bool = true
    var serverCount: Int { servers.count }
    var serverNames: [String] { Array(servers.keys).sorted() }
    var isUsingStub: Bool { false }  // <-- Now using real Syphon
    
    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
    }
    
    deinit {
        stopAll()
    }
    
    func createServer(name: String) {
        guard servers[name] == nil else { return }
        let server = SyphonSender(device: device, name: name)
        servers[name] = server
        print("[Syphon] Created server: \(name)")
    }
    
    func createStandardServers() {
        let names = [
            TileConfig.shader.syphonName,
            TileConfig.mask.syphonName,
            TileConfig.lyrics.syphonName,
            TileConfig.refrain.syphonName,
            TileConfig.songInfo.syphonName,
            TileConfig.image.syphonName
        ]
        for name in names {
            createServer(name: name)
        }
    }
    
    func publish(name: String, texture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard isEnabled, let server = servers[name] else { return }
        server.publish(texture: texture, on: commandBuffer)
    }
    
    func publish(name: String, texture: MTLTexture) {
        guard isEnabled, let server = servers[name] else { return }
        server.publish(texture: texture, commandQueue: commandQueue)
    }
    
    func stopServer(name: String) {
        if let server = servers[name] {
            server.stop()
            servers.removeValue(forKey: name)
            print("[Syphon] Stopped server: \(name)")
        }
    }
    
    func stopAll() {
        for (name, server) in servers {
            server.stop()
            print("[Syphon] Stopped server: \(name)")
        }
        servers.removeAll()
    }
    
    func hasServer(name: String) -> Bool {
        servers[name] != nil
    }
}
```

---

## 5. MTKView Settings for Syphon

When using MTKView with Syphon, set:

```swift
let metalView = MTKView(frame: frame, device: device)
metalView.framebufferOnly = false  // Required for texture sharing!
metalView.colorPixelFormat = .bgra8Unorm
metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
```

**Important**: `framebufferOnly = false` is required because Syphon needs to read the texture. This has minimal performance impact.

---

## 6. Sample Usage

```swift
import Metal
import SyphonKit

// Setup
let device = MTLCreateSystemDefaultDevice()!
let commandQueue = device.makeCommandQueue()!
let syphonSender = SyphonSender(device: device, name: "SwiftVJ/Shader")

// Create render texture
let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .bgra8Unorm,
    width: 1920,
    height: 1080,
    mipmapped: false
)
textureDescriptor.usage = [.renderTarget, .shaderRead]
let renderTexture = device.makeTexture(descriptor: textureDescriptor)!

// Render loop
func render() {
    let commandBuffer = commandQueue.makeCommandBuffer()!
    
    // ... render your visuals to renderTexture ...
    
    // Publish to Syphon
    syphonSender.publish(texture: renderTexture, on: commandBuffer)
    
    commandBuffer.commit()
}

// Cleanup
syphonSender.stop()
```

---

## 7. Troubleshooting

### "Cannot import module 'Syphon'"

- Verify XCFramework structure:
  ```
  Syphon.xcframework/
  ├── Info.plist
  ├── macos-arm64/
  │   └── Syphon.framework/
  └── macos-x86_64/
      └── Syphon.framework/
  ```
- Check `Package.swift` path is correct
- Run `swift package clean && swift build`

### "Code signature invalid"

```bash
# Re-sign the framework
codesign --force --sign - Frameworks/Syphon.xcframework/macos-arm64/Syphon.framework
codesign --force --sign - Frameworks/Syphon.xcframework/macos-x86_64/Syphon.framework
```

### "Symbol not found" for Metal types

Add linker settings to target:
```swift
.target(
    name: "SyphonKit",
    dependencies: ["Syphon"],
    linkerSettings: [
        .linkedFramework("Metal"),
        .linkedFramework("IOSurface"),
    ]
)
```

### Syphon client (OBS, Resolume) doesn't see server

1. Verify app is not sandboxed (Syphon requires IOSurface sharing)
2. Check server is created: `syphonManager.serverCount > 0`
3. Try Simple Client from Syphon releases for testing

### Performance issues

- Use `.storageModePrivate` for render textures (Syphon copies anyway)
- Avoid calling `publish()` more than 60x/sec per server
- Use single command buffer for all servers in one frame

---

## 8. Testing with Syphon Client

Download Syphon demo apps from [syphon.info](https://syphon.info/):

1. **Simple Client** - Basic receiver for testing
2. **Simple Server** - Verify your receiver code

Test command:
```bash
# List active Syphon servers (requires Syphon Recorder or similar)
system_profiler SPExtensionsDataType | grep -i syphon
```

---

## References

- [Syphon Official Site](https://syphon.info/)
- [Syphon-Framework GitHub](https://github.com/Syphon/Syphon-Framework)
- [SyphonMetalServer.h](https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h)
- [Apple: Distributing Binary Frameworks](https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages)
- [Swift Evolution: Binary Targets](https://github.com/apple/swift-evolution/blob/main/proposals/0305-swiftpm-binary-target-improvements.md)

---

*Last Updated: 2026-01-03*

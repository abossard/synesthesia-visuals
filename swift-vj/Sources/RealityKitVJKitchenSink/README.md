# RealityKit VJ Kitchen Sink

Production-grade RealityKit example for VJ work. Demonstrates advanced RealityKit rendering features with Syphon output for live performance.

**Requirements**: macOS 15+ only, Swift Package Manager

## Features

- **5 Visual "Looks"**: Space Dome, Water, Laser Rig, Dancer/Character, Procedural Mesh
- **RealityKit Advanced APIs**: CustomMaterial, LowLevelMesh, ParticleEmitter, non-AR camera mode
- **Syphon Output**: Real-time Metal texture sharing to OBS, Resolume, or other VJ software
- **No AR Dependencies**: Pure virtual 3D rendering (no ARKit, no world tracking)
- **SwiftUI Controls**: Real-time parameter tweaking with immediate visual feedback
- **Modular Architecture**: Clean Look protocol for easy extension

## Quick Start

### Build and Run (CLI)

```bash
cd swift-vj
swift run RealityKitVJKitchenSink
```

### Build App Bundle

```bash
./Scripts/make-realitykit-app.sh
```

This creates `Build/RealityKitVJKitchenSink.app` which you can:
- Run: `open Build/RealityKitVJKitchenSink.app`
- Install: `cp -R Build/RealityKitVJKitchenSink.app /Applications/`

## Architecture

### Look System

Each "Look" is a self-contained visual scene following the `Look` protocol:

```swift
protocol Look: AnyObject {
    init(context: LookContext)
    func makeRootEntity() -> Entity
    func update(dt: Double, time: Double, globalParams: GlobalParams)
    func teardown()
}
```

**Benefits**:
- Clean separation of concerns
- Easy to add new looks
- Automatic resource cleanup on look switch

### Looks Overview

1. **Space Dome Look**
   - Inverted sphere sky dome with particle starfield
   - Time-based hue shifting
   - Camera orbital drift
   - Refs: [ParticleEmitterComponent](https://developer.apple.com/documentation/realitykit/particleemittercomponent)

2. **Water Look**
   - Large plane with CustomMaterial for animated waves
   - Metal shader for vertex displacement
   - Adjustable wave amplitude, frequency, specularity
   - Refs: [CustomMaterial](https://developer.apple.com/documentation/realitykit/custommaterial), [Modifying rendering](https://developer.apple.com/documentation/realitykit/modifying-realitykit-rendering-using-custom-materials)

3. **Laser Rig Look**
   - Array of emissive beam meshes in circular pattern
   - Color cycling and sweep animation
   - Requires bloom in post-process for glow effect
   - Demonstrates emissive materials + post-processing dependency

4. **Dancer / Character Look**
   - USDZ model loading (default: toy_robot_vintage.usdz)
   - 3-point lighting setup
   - Floor plane with adjustable reflectivity
   - Animation playback or manual idle animation
   - Refs: [Loading entities from file](https://developer.apple.com/documentation/realitykit/loading-entities-from-a-file), [Apple Quick Look models](https://developer.apple.com/augmented-reality/quick-look/)

5. **Procedural Mesh Look**
   - Dynamic ribbon/tube mesh updated every frame
   - Demonstrates LowLevelMesh for vertex manipulation
   - Noise-based deformation
   - Color gradient cycling
   - Refs: [LowLevelMesh](https://developer.apple.com/documentation/realitykit/lowlevelmesh), [Procedural assets](https://developer.apple.com/documentation/realitykit/adding-procedural-assets-to-a-scene)

### Rendering Pipeline

1. **ARView in non-AR mode**
   - Ref: [ARView.CameraMode.nonAR](https://developer.apple.com/documentation/realitykit/arview/cameramode-swift.enum/nonar)
   - No ARKit session, no world tracking
   - Manual camera control via transforms

2. **Post-Process Callback**
   - Ref: [ARView.RenderCallbacks.postProcess](https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess)
   - Accesses rendered MTLTexture each frame
   - Applies optional bloom/glow effect
   - Publishes to Syphon before commit

3. **Syphon Output**
   - Uses SyphonMetalServer to share textures
   - Ref: [Syphon Framework](https://github.com/Syphon/Syphon-Framework), [SyphonMetalServer.h](https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h)
   - Server name: "RealityKitVJKitchenSink"
   - Toggle on/off in UI

## Syphon Integration

### Viewing Syphon Output

Install a Syphon client to view the output:

- **Syphon Recorder** (simple viewer): [https://syphon.info/](https://syphon.info/)
- **OBS Studio** with Syphon plugin: Composite with other sources
- **Resolume Arena/Avenue**: VJ mixing software
- **MadMapper**: Projection mapping

### How It Works

1. RealityKit renders scene to Metal texture
2. Post-process callback accesses the texture via `context.targetColorTexture`
3. `SyphonOutput.publish()` encodes texture to Syphon command buffer
4. Command buffer committed → texture available to clients
5. Zero-copy texture sharing via IOSurface (minimal latency)

## Project Structure

```
Sources/RealityKitVJKitchenSink/
├── AppMain.swift              # SwiftUI app entry point
├── ContentView.swift          # UI + parameter controls
├── Renderer/
│   ├── RealityViewHost.swift  # NSViewRepresentable hosting ARView
│   ├── SceneCoordinator.swift # Owns ARView, camera, update loop
│   ├── SyphonOutput.swift     # SyphonMetalServer wrapper
│   └── PostProcess.swift      # Post-process callback (bloom + Syphon)
├── Looks/
│   ├── Look.swift             # Look protocol + parameter types
│   ├── LookManager.swift      # Look switching + cleanup
│   ├── SpaceDomeLook.swift
│   ├── WaterLook.swift
│   ├── LaserRigLook.swift
│   ├── DancerLook.swift
│   └── ProceduralMeshLook.swift
├── Utilities/
│   ├── Math.swift             # Vector math, HSV conversion, easing
│   ├── Noise.swift            # Deterministic Perlin noise
│   └── ParameterSmoothing.swift  # Time-based smoothing for UI params
└── Resources/
    ├── Models/                # USDZ files (e.g., toy_robot_vintage.usdz)
    └── Textures/              # Optional texture assets
```

## Adding a New Look

1. **Create look class** implementing `Look` protocol:

```swift
final class MyCustomLook: Look {
    required init(context: LookContext) { ... }
    func makeRootEntity() -> Entity { ... }
    func update(dt: Double, time: Double, globalParams: GlobalParams) { ... }
    func teardown() { ... }
}
```

2. **Add look type** to `LookType` enum in `Looks/Look.swift`:

```swift
enum LookType: String, CaseIterable {
    case myCustom
    // ...
    var displayName: String {
        case .myCustom: return "My Custom Look"
    }
}
```

3. **Add parameters class** (if needed):

```swift
@MainActor
class MyCustomParams: ObservableObject {
    @Published var someSetting: Double = 1.0
}
```

4. **Update LookManager factory** in `Looks/LookManager.swift`:

```swift
private func createLook(type: LookType) -> Look {
    switch type {
    case .myCustom: return MyCustomLook(context: context)
    // ...
    }
}
```

5. **Add UI controls** in `ContentView.swift` → `LookParametersView`

## Global Parameters

- **Pause**: Freeze time updates
- **Time Scale**: Speed multiplier (0.1x - 3.0x)
- **Camera Motion**: Orbital camera drift intensity
- **Environment Intensity**: Ambient/background lighting level
- **Bloom Intensity**: Post-process glow effect strength
- **Syphon Output**: Enable/disable texture publishing

## Per-Look Parameters

Each look has custom parameters (sliders in UI):

- **Space Dome**: Star density, hue speed, camera drift
- **Water**: Wave amplitude, frequency, specular, roughness
- **Laser Rig**: Beam count, sweep speed, glow intensity, color cycle speed
- **Dancer**: Animation speed, scale pulse, lighting, floor reflectivity
- **Procedural Mesh**: Ribbon length, thickness, noise scale, color gradient speed

## USDZ Models

The Dancer look expects a USDZ file at `Resources/Models/toy_robot_vintage.usdz`.

### Download Default Model

```bash
cd Sources/RealityKitVJKitchenSink/Resources/Models
curl -O https://developer.apple.com/augmented-reality/quick-look/models/vintagerobot2k/toy_robot_vintage.usdz
```

### Using Your Own Model

1. Place `.usdz` file in `Resources/Models/`
2. Update `DancerLook.swift` → `loadCharacter()` to reference your file
3. Rebuild

**Model Sources**:
- [Apple Quick Look Gallery](https://developer.apple.com/augmented-reality/quick-look/)
- Export from Blender (via USD export addon)
- Convert from other formats using Reality Converter

## Performance Notes

- **Target FPS**: 60 (depends on look complexity and hardware)
- **Optimization Tips**:
  - Reduce particle count in Space Dome
  - Lower beam count in Laser Rig
  - Decrease ribbon length in Procedural Mesh
  - Disable bloom if not needed
- **Metal GPU**: Required (integrated or discrete)
- **Syphon overhead**: Minimal (zero-copy via IOSurface)

## References

### RealityKit Documentation
- [ARView non-AR camera mode](https://developer.apple.com/documentation/realitykit/arview/cameramode-swift.enum/nonar)
- [Post-process callback](https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess)
- [CustomMaterial](https://developer.apple.com/documentation/realitykit/custommaterial)
- [Modifying rendering with custom materials](https://developer.apple.com/documentation/realitykit/modifying-realitykit-rendering-using-custom-materials)
- [LowLevelMesh](https://developer.apple.com/documentation/realitykit/lowlevelmesh)
- [Loading entities from file](https://developer.apple.com/documentation/realitykit/loading-entities-from-a-file)
- [Procedural assets overview](https://developer.apple.com/documentation/realitykit/adding-procedural-assets-to-a-scene)
- [ParticleEmitterComponent](https://developer.apple.com/documentation/realitykit/particleemittercomponent)
- [Post-processing effects overview](https://developer.apple.com/documentation/realitykit/postprocessing-effects)
- [Implementing special effects with post-processing](https://developer.apple.com/documentation/realitykit/implementing-special-rendering-effects-with-realitykit-postprocessing)

### Syphon Documentation
- [Syphon Framework](https://github.com/Syphon/Syphon-Framework)
- [Syphon.info](https://syphon.info/)
- [SyphonMetalServer header](https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h)

### USDZ Assets
- [Apple Quick Look model library](https://developer.apple.com/augmented-reality/quick-look/)
- [Example USDZ: Vintage Robot](https://developer.apple.com/augmented-reality/quick-look/models/vintagerobot2k/toy_robot_vintage.usdz)

## Troubleshooting

### App doesn't start / no window
- Ensure `NSApplication.shared.setActivationPolicy(.regular)` in AppDelegate
- Check console for errors: `Console.app` → filter "RealityKit"

### Syphon not visible to clients
- Verify server started: Look for "[Syphon] Started server" in console
- Check "Syphon Output" toggle is ON in UI
- Restart Syphon client app

### Low FPS / stuttering
- Reduce complexity via per-look parameters
- Disable bloom (set to 0)
- Check Activity Monitor for GPU usage
- macOS 15+ required (older versions not supported)

### USDZ not loading
- Ensure file exists: `ls Sources/RealityKitVJKitchenSink/Resources/Models/*.usdz`
- Check file permissions
- Download from Apple if missing (see USDZ Models section)

## License

Part of the Synesthesia Visuals project. See top-level LICENSE.

## Credits

- RealityKit: Apple Inc.
- Syphon Framework: [Syphon contributors](https://github.com/Syphon/Syphon-Framework)
- USDZ models: [Apple Quick Look Gallery](https://developer.apple.com/augmented-reality/quick-look/)

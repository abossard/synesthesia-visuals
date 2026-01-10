# RealityKit VJ Kitchen Sink

A macOS 15+ demonstration app showcasing RealityKit's advanced rendering capabilities with Syphon output for VJ integration.

## Features

- **5 Visual Looks**: Space Dome, Water, Laser Rig, Dancer, Procedural Mesh
- **RealityKit Rendering**: Non-AR camera mode, CustomMaterial, LowLevelMesh, ParticleEmitterComponent
- **Post-Processing**: Real-time bloom/glow effects
- **Syphon Output**: Publish rendered frames to any Syphon-compatible VJ software
- **SwiftUI Interface**: Modern control panel with per-look parameters

## Requirements

- macOS 15.0 or later
- Swift 5.9+
- Xcode 15+ (for building)

## Build & Run

### Using Swift Package Manager (Recommended)

```bash
# Navigate to the swift-vj directory
cd swift-vj

# Run directly
swift run RealityKitVJKitchenSink

# Or build first
swift build -c release --product RealityKitVJKitchenSink
.build/release/RealityKitVJKitchenSink
```

### Creating an App Bundle

```bash
# Make the script executable (first time only)
chmod +x Scripts/make-realitykit-app.sh

# Build and bundle
./Scripts/make-realitykit-app.sh

# Run the app
open Build/RealityKitVJKitchenSink.app
```

## Syphon Output

The app publishes rendered frames to Syphon with the server name: **"RealityKitVJKitchenSink"**

### Viewing Syphon Output

Any Syphon-compatible application can receive the output:
- Simple Syphon Client (for testing)
- VJ software (VDMX, Resolume, etc.)
- Other custom apps using SyphonKit

### How It Works

1. RealityKit renders the scene using ARView in non-AR mode
2. The postprocess callback captures the rendered Metal texture
3. Optional bloom post-processing is applied
4. The final texture is published via `SyphonMetalServer`

Toggle Syphon output on/off using the UI control panel.

## Visual Looks

### 1. Space Dome
- Inverted sphere sky dome with particle starfield
- Animated nebula clouds
- Time-based hue shifting

**Parameters:**
- Star Density: Controls starfield particle count
- Hue Speed: Rate of color cycling
- Camera Drift: Amplitude of subtle camera movement
- Nebula Intensity: Opacity of nebula clouds

### 2. Water
- Large plane with CustomMaterial for wave displacement
- GPU-based vertex animation
- Caustic lighting effects

**Parameters:**
- Wave Amplitude: Height of waves
- Wave Frequency: Wave pattern density
- Specular/Roughness: Surface reflectivity
- Caustic Tint: Underwater glow color

### 3. Laser Rig
- Array of emissive beam meshes
- Sweep animation and color cycling
- Designed for bloom post-processing

**Parameters:**
- Beam Count: Number of laser beams
- Sweep Speed: Animation rate
- Glow Intensity: Emissive brightness
- Color Cycle Speed: Color animation rate
- Fan Angle: Spread angle of beams

### 4. Dancer / Character
- Loads USDZ model (downloads if not bundled)
- 3-point lighting setup
- Idle animation with bob and rotation

**Parameters:**
- Animation Speed: Playback rate
- Scale Pulse: Breathing animation intensity
- Lighting Intensity: Overall light brightness
- Floor Reflectivity: Stage floor mirror quality
- Rotation Speed: Model spin rate

**Default USDZ Model:**
- Source: [Apple Quick Look Gallery](https://developer.apple.com/augmented-reality/quick-look/)
- Model: `toy_robot_vintage.usdz`
- Downloaded automatically on first run

### 5. Procedural Mesh
- Dynamic ribbon/tube using LowLevelMesh
- Noise-driven deformation
- Real-time geometry updates

**Parameters:**
- Ribbon Length: Number of segments
- Thickness: Tube radius
- Noise Scale: Deformation intensity
- Color Speed: Gradient animation rate
- Wave Count: Helix complexity

## Adding a New Look

1. Create a new file in `Looks/` (e.g., `MyLook.swift`)
2. Define parameters struct:
   ```swift
   struct MyParams: LookParams, Codable {
       var myValue: Double = 1.0
       static var defaults: MyParams { MyParams() }
   }
   ```

3. Implement the Look protocol:
   ```swift
   final class MyLook: Look {
       typealias Params = MyParams

       let rootEntity: Entity

       required init(context: LookContext) {
           self.rootEntity = Entity()
           // Setup entities...
       }

       func update(time: Double, deltaTime: Double, params: MyParams) {
           // Animation logic...
       }
   }
   ```

4. Add to `LookType` enum in `AppMain.swift`
5. Add parameters to `AppState`
6. Add case to `LookManager.createLook()`
7. Add UI controls in `ContentView.swift`

## Architecture

```
RealityKitVJKitchenSink/
├── AppMain.swift           # App entry, AppState (single source of truth)
├── ContentView.swift       # SwiftUI UI layout
├── Renderer/
│   ├── RealityViewHost.swift    # NSViewRepresentable for ARView
│   ├── SceneCoordinator.swift   # Scene management, camera, update loop
│   ├── SyphonOutput.swift       # Syphon publishing wrapper
│   └── PostProcess.swift        # Bloom effect pipeline
├── Looks/
│   ├── Look.swift              # Look protocol
│   ├── LookManager.swift       # Look lifecycle management
│   ├── SpaceDomeLook.swift     # Space/starfield scene
│   ├── WaterLook.swift         # Animated water with CustomMaterial
│   ├── LaserRigLook.swift      # Laser beam array
│   ├── DancerLook.swift        # USDZ character loading
│   └── ProceduralMeshLook.swift # LowLevelMesh ribbon
├── Utilities/
│   ├── Math.swift              # Vector/matrix utilities
│   ├── Noise.swift             # Procedural noise functions
│   └── ParameterSmoothing.swift # Animation smoothing
└── Resources/
    ├── Textures/
    └── Shaders/
```

## References

### RealityKit
- [ARView Non-AR Camera Mode](https://developer.apple.com/documentation/realitykit/arview/cameramode-swift.enum/nonar)
- [ARView Render Callbacks](https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess)
- [CustomMaterial](https://developer.apple.com/documentation/realitykit/custommaterial)
- [Modifying Rendering with Custom Materials](https://developer.apple.com/documentation/realitykit/modifying-realitykit-rendering-using-custom-materials)
- [LowLevelMesh](https://developer.apple.com/documentation/realitykit/lowlevelmesh)
- [Loading Entities from Files](https://developer.apple.com/documentation/realitykit/loading-entities-from-a-file)
- [Procedural Assets](https://developer.apple.com/documentation/realitykit/adding-procedural-assets-to-a-scene)
- [ParticleEmitterComponent](https://developer.apple.com/documentation/realitykit/particleemittercomponent)
- [Postprocessing Effects](https://developer.apple.com/documentation/realitykit/postprocessing-effects)
- [Special Rendering Effects](https://developer.apple.com/documentation/realitykit/implementing-special-rendering-effects-with-realitykit-postprocessing)

### Syphon
- [Syphon Framework](https://github.com/Syphon/Syphon-Framework)
- [Syphon Website](https://syphon.info/)
- [SyphonMetalServer Header](https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h)

### USDZ Assets
- [Apple Quick Look Gallery](https://developer.apple.com/augmented-reality/quick-look/)
- [Sample Robot Model](https://developer.apple.com/augmented-reality/quick-look/models/vintagerobot2k/toy_robot_vintage.usdz)

## License

Part of the SwiftVJ project. See repository root for license information.

# RealityKit Kitchen Sink VJ

A macOS 15+ RealityKit VJ example built with Swift Package Manager only. This target renders multiple RealityKit looks, applies a post-process callback, and publishes frames via Syphon.

## Requirements

- macOS 15+
- Swift 5.9+
- Syphon framework (already vendored in this repo)

## Build & Run (SPM)

```bash
swift run RealityKitVJKitchenSink
```

## Build a .app Bundle

```bash
./Scripts/make-app.sh
```

The script uses `swift build -c release` and produces:

```
Build/RealityKitVJKitchenSink.app
```

## Syphon Output

The app publishes the post-processed Metal texture via `SyphonMetalServer` under the server name:

```
RealityKitVJKitchenSink
```

Enable/disable Syphon output using the UI toggle. Any Syphon-capable client can subscribe to this server.

Syphon references:
- https://syphon.info/
- https://github.com/Syphon/Syphon-Framework
- https://github.com/Syphon/Syphon-Framework/blob/main/SyphonMetalServer.h

## Looks

- Space Dome (sky sphere + starfield emitter)
- Water (CustomMaterial surface + vertex displacement)
- Laser Rig (emissive beams + post-process glow)
- Dancer (USDZ character + lighting)
- Procedural Mesh (LowLevelMesh ribbon)

## Adding a New Look

1. Create a new file in `Sources/RealityKitVJKitchenSink/Looks/` that conforms to `Look`.
2. Add a params struct conforming to `LookParams`.
3. Register the look in `LookKind` and `LookManager.switchLook`.
4. Add UI controls in `ContentView` for the new params.

## USDZ Assets

The Dancer look loads `toy_robot_vintage.usdz` from `Sources/RealityKitVJKitchenSink/Resources/Models/`.

If you want a bundled model, download it from Apple Quick Look and place it in the Models folder:
- Quick Look model library: https://developer.apple.com/augmented-reality/quick-look/
- Example USDZ: https://developer.apple.com/augmented-reality/quick-look/models/vintagerobot2k/toy_robot_vintage.usdz

## RealityKit References

- ARView non-AR camera mode: https://developer.apple.com/documentation/realitykit/arview/cameramode-swift.enum/nonar
- ARView render callbacks / postprocess: https://developer.apple.com/documentation/realitykit/arview/rendercallbacks-swift.struct/postprocess
- CustomMaterial: https://developer.apple.com/documentation/realitykit/custommaterial
- Modifying rendering using custom materials: https://developer.apple.com/documentation/realitykit/modifying-realitykit-rendering-using-custom-materials
- LowLevelMesh: https://developer.apple.com/documentation/realitykit/lowlevelmesh
- Loading entities from file (USDZ): https://developer.apple.com/documentation/realitykit/loading-entities-from-a-file
- Procedural assets overview: https://developer.apple.com/documentation/realitykit/adding-procedural-assets-to-a-scene
- ParticleEmitterComponent: https://developer.apple.com/documentation/realitykit/particleemittercomponent
- Postprocessing effects overview: https://developer.apple.com/documentation/realitykit/postprocessing-effects
- Special effects with postprocessing: https://developer.apple.com/documentation/realitykit/implementing-special-rendering-effects-with-realitykit-postprocessing

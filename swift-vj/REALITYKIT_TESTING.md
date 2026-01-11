# RealityKit VJ Kitchen Sink - Testing Guide

This document provides instructions for testing the RealityKit VJ Kitchen Sink on macOS 15+.

## Prerequisites

- **macOS 15.0+** (Sequoia or later) - REQUIRED for RealityKit advanced features
- Xcode 16+ with Swift 5.9+
- Metal-capable GPU (integrated or discrete)

## Build Instructions

### Option 1: CLI Build and Run

```bash
cd swift-vj

# Build the project
swift build --target RealityKitVJKitchenSink

# Run directly
swift run RealityKitVJKitchenSink
```

### Option 2: Create App Bundle

```bash
cd swift-vj

# Create .app bundle
./Scripts/make-realitykit-app.sh

# Run the app
open Build/RealityKitVJKitchenSink.app
```

## Expected Behavior

### On Launch

1. **Window appears**: Main SwiftUI window with left control panel and render view
2. **Default look loads**: Space Dome look should be visible with rotating starfield
3. **FPS counter**: Top-right corner shows frame rate (~60 FPS expected)
4. **Controls active**: All sliders and toggles respond immediately

### Testing Each Look

Switch between looks using the segmented control at top of left panel:

1. **Space Dome**
   - Inverted sphere dome (you're inside it)
   - Stars should be visible as particles
   - Hue should slowly shift over time
   - Test: Adjust "Hue Speed" slider → color changes faster

2. **Water**
   - Large plane at origin
   - Should have water-like appearance (cyan/blue tint)
   - Test: Adjust "Wave Amplitude" → surface should deform (if CustomMaterial working)

3. **Laser Rig**
   - Multiple thin beams arranged in circle
   - Beams should rotate/sweep
   - Colors should cycle through spectrum
   - Test: Adjust "Beam Count" → beams added/removed
   - **Note**: Requires "Bloom" > 0 for glow effect

4. **Dancer**
   - If USDZ loaded: Character model visible
   - If fallback: Orange capsule with sphere head
   - Floor plane should be visible below
   - Character should animate (bob + spin)
   - Test: Adjust "Animation Speed" → movement faster

5. **Procedural Mesh**
   - Ribbon/tube mesh (magenta/pink by default)
   - Should rotate slowly
   - Test: Adjust "Color Gradient Speed" → hue cycles faster

### Testing Global Parameters

**Pause**: Freezes all animation (time stops)
**Time Scale**: 
- 0.1x = slow motion
- 3.0x = fast motion

**Camera Motion**: 
- 0 = static camera
- 1.0 = full orbital camera drift around scene

**Bloom Intensity**:
- 0 = no bloom
- 0.5 = moderate glow on bright objects
- 1.0 = strong bloom (especially visible on Laser Rig)

**Syphon Output**:
- Toggle ON → check for Syphon server in client apps
- Toggle OFF → Syphon publishing disabled

### Testing Syphon Output

1. **Install Syphon Client**
   - Simple Syphon (free viewer): [https://syphon.info/](https://syphon.info/)
   - Or use OBS with Syphon plugin

2. **Verify Server**
   - Launch a Syphon client app
   - Look for server named: **"RealityKitVJKitchenSink"**
   - Select it → should see same visuals as main app

3. **Test Frame Sync**
   - Switch looks in main app
   - Syphon client should update immediately
   - Adjust parameters → changes visible in both windows

## Troubleshooting

### Build Errors

**"RealityKit not found"**
- macOS 15+ required (check: `sw_vers`)
- Ensure Xcode 16+ installed

**"Cannot find 'SyphonKit' in scope"**
- Ensure Syphon.xcframework exists at: `swift-vj/Frameworks/Syphon.xcframework`
- Rebuild if needed: `swift build --clean`

### Runtime Errors

**App launches but no window**
- Check Console.app for errors
- Look for: "RealityKit", "Metal", "AppKit"

**Black screen / no rendering**
- Check Metal GPU available: System Settings → About → Graphics
- Try different look (some may fail gracefully)

**USDZ not loading (Dancer look)**
- Expected if model not downloaded
- Should see fallback (orange capsule) instead
- Download model:
  ```bash
  cd Sources/RealityKitVJKitchenSink/Resources/Models
  curl -O https://developer.apple.com/augmented-reality/quick-look/models/vintagerobot2k/toy_robot_vintage.usdz
  ```

**Low FPS / Stuttering**
- Expected on integrated GPUs with complex looks
- Reduce parameters:
  - Space Dome: Lower "Star Density"
  - Laser Rig: Lower "Beam Count"
  - Procedural Mesh: Lower "Ribbon Length"
- Disable Bloom (set to 0)

**Syphon not visible**
- Check console for: "[Syphon] Started server"
- Verify toggle is ON in UI
- Restart Syphon client app
- Try toggling Syphon off/on in UI

## Performance Benchmarks

Expected FPS on various hardware (macOS 15.0):

- **M1 Max / M2 Pro** (discrete GPU): 60 FPS sustained (all looks)
- **M1 / M2** (integrated GPU): 40-60 FPS (depends on look)
- **Intel Mac** (2019+): 30-50 FPS (bloom impacts performance)

## Console Output

Normal operation should show:

```
[SceneCoordinator] Started with look: Space Dome
[Syphon] Started server: RealityKitVJKitchenSink
[LookManager] Switched to: Space Dome
```

When switching looks:

```
[LookManager] Switched to: Water
[LookManager] Switched to: Laser Rig
```

USDZ loading (if model present):

```
[DancerLook] USDZ loaded successfully
```

USDZ fallback (if model missing):

```
[DancerLook] USDZ not found, using fallback
```

## Validation Checklist

- [ ] App builds without errors
- [ ] App launches and shows window
- [ ] All 5 looks render correctly
- [ ] FPS counter shows reasonable values (>30)
- [ ] Look switching works instantly
- [ ] All parameter sliders affect visuals
- [ ] Pause/Play works
- [ ] Time Scale affects animation speed
- [ ] Camera Motion creates orbital movement
- [ ] Bloom creates glow on emissive objects
- [ ] Syphon server appears in client apps
- [ ] Syphon output matches main window
- [ ] No crashes when switching looks rapidly
- [ ] No memory leaks over 5+ minutes

## Known Limitations

1. **CustomMaterial geometry modifier**: Water look uses simplified approach
   - Full vertex displacement requires Metal shader library
   - Current implementation shows basic material

2. **LowLevelMesh dynamic updates**: Procedural Mesh uses static mesh + transform
   - Full per-frame vertex updates require more complex setup
   - Demonstrates mesh generation, not real-time deformation

3. **Post-process bloom**: Simplified implementation
   - Production version would use multi-pass Gaussian blur
   - Current version shows blit-based approach

4. **No audio reactivity**: All animation is time-based
   - Intentional per requirements (no audio/FFT dependency)

## Success Criteria

✅ Project compiles on macOS 15+
✅ All 5 looks render distinct visuals
✅ Syphon output works with external clients
✅ UI controls update visuals in real-time
✅ No crashes during normal operation
✅ FPS acceptable on M1+ hardware

## Next Steps

After validation:

1. **Add USDZ models**: Download sample models from Apple
2. **Optimize shaders**: Implement full CustomMaterial Metal shaders
3. **Add more looks**: Follow README guide for extending
4. **Performance tuning**: Profile and optimize hot paths
5. **Production deployment**: Bundle as .app for installation

## Support

For issues:
1. Check Console.app for errors
2. Review this guide's troubleshooting section
3. Verify macOS version (must be 15+)
4. Test on different looks (isolate failures)

# VJSims - Non-Interactive VJ Simulation Framework

A minimal, non-interactive visual framework for VJ performances. Designed to run continuously with Synesthesia Audio OSC input.

## Features

- **Non-Interactive**: Auto-running visuals, no keyboard/MIDI control needed
- **Audio-Reactive**: Ready for Synesthesia Audio OSC (bass, mid, high envelopes)
- **Syphon Output**: Streams visuals for compositing in Magic/Synesthesia/Resolume
- **Lightweight**: Minimal dependencies, simple codebase

## Architecture

```
VJSims.pde          - Main sketch (auto-running loop)
AudioEnvelope.pde   - Audio envelope simulation
SharedContext.pde   - Shared state (minimal)
SketchConfig.pde    - Configuration
```

## Requirements

- Processing 4.x (Intel/x64 build on Apple Silicon for Syphon compatibility)
- Syphon library (for frame sharing)
- oscP5 library (for Synesthesia Audio OSC - TODO)

## Usage

1. **Open in Processing**: Load `VJSims.pde`
2. **Run**: Press play - visuals auto-start
3. **Syphon Output**: Outputs as "VJSims" server
4. **Receive in VJ Software**: Use Syphon to receive in Magic/Synesthesia/Resolume

## Audio Integration

### Current (Simulated Audio)
Auto-generates beat triggers at ~120 BPM for testing:
- Bass: Every 0.5s
- Mid: Every 0.25s  
- High: Every ~0.12s

### Future (Synesthesia Audio OSC)
Will receive real-time audio analysis from Synesthesia:
- Bass/Mid/High levels (0-1)
- BPM detection
- Beat detection
- Spectrum data

## Customization

Edit `renderSimulation()` in `VJSims.pde` to create custom visuals:

```java
void renderSimulation(PGraphics pg, float dt) {
  // Your visual code here
  // Access audio levels:
  //   bassEnv.getLevel() - bass energy (0-1)
  //   midEnv.getLevel()  - mid energy (0-1)
  //   highEnv.getLevel() - high energy (0-1)
  //   time               - elapsed time
}
```

## Configuration

Edit constants in `SketchConfig.pde`:
- Resolution
- Frame rate
- Syphon server name

## Performance

- **60 FPS** target
- **P3D** renderer for GPU acceleration
- **Off-screen rendering** to PGraphics for clean Syphon output

## Comparison to VJUniverse

| Feature | VJSims | VJUniverse |
|---------|--------|------------|
| Shaders | No | Yes (GLSL) |
| Interactivity | None | Full (MIDI, keyboard) |
| Purpose | Auto-running sims | Manual shader control |
| Audio | Synesthesia OSC | Synesthesia integration |
| Output | Syphon only | Syphon + screen |

## TODO

- [ ] Implement Synesthesia Audio OSC listener
- [ ] Add more built-in visual simulations
- [ ] Performance optimizations
- [ ] Configuration file support

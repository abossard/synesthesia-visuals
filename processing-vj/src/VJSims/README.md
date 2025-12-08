# VJSims - VJ Simulation Framework

A highly interactive simulation framework for VJ performances, designed for creative visual expression through code.

## Overview

VJSims is a Processing-based framework for creating interactive audio-reactive simulations. It provides:

- **Launchpad Integration**: Control simulations with Akai Launchpad Mini Mk3
- **Synesthesia Audio OSC**: Real-time audio analysis from Synesthesia (bass, mid, high, BPM, spectrum)
- **Syphon Output**: Send visuals to Magic Music Visuals or other VJ software
- **State Machine**: Robust level state management (idle → playing → victory → game over)
- **Keyboard Fallback**: Full functionality without hardware controllers

## Features

### Audio Reactivity

VJSims supports **Synesthesia Audio OSC** for professional audio analysis:

- Per-band energy (bass, mid, high)
- Beat detection and BPM
- Spectral features (centroid, flux)
- Low-latency (~10-30ms)

**TODO**: Implement OSC listener module to receive Synesthesia audio data

### Visual Framework

The framework provides:

- **Level System**: Multiple visual "levels" (simulations) that can be switched on the fly
- **Launchpad Control**: 8x8 pad grid for interaction, top row for level selection
- **Audio Envelope**: Smoothed audio signals with configurable attack/decay
- **Syphon Output**: Real-time frame sharing at 1280x720 HD

## Requirements

- Processing 4.x (Intel/x64 build on Apple Silicon for Syphon compatibility)
- Libraries:
  - The MidiBus (MIDI I/O)
  - Syphon (frame sharing)
  - oscP5 + netP5 (OSC communication - for Synesthesia audio)
- Hardware (optional):
  - Akai Launchpad Mini Mk3 (set to Programmer mode)
  - Synesthesia running with OSC audio output enabled

## Usage

1. **Start Synesthesia** with audio OSC output enabled (default port 9000)
2. **Launch VJSims** in Processing
3. **Select a level** using Launchpad top row or number keys 1-8
4. **Interact** using pad grid or keyboard

### Keyboard Controls

When Launchpad is not connected, use keyboard:

**Level Selection:**
- `1-8` - Switch to level 1-8
- `← →` - Previous/Next level

**Level Control:**
- `S` - Start level
- `R` - Reset level
- `P` - Pause/Resume

**Audio Simulation** (when Synesthesia OSC not available):
- `SPACE` - Trigger beat (all bands)
- `B` - Bass hit
- `M` - Mid hit
- `H` - High hit

## Architecture

### Core Components

- **SharedContext**: Manages framebuffer, Syphon server, audio envelope, configuration
- **LevelManager**: Handles level lifecycle, switching, and state
- **LaunchpadGrid/HUD**: MIDI I/O and LED feedback
- **Inputs**: Collects pad events, keyboard, and audio data per frame
- **Level**: Base class for all simulations (see EmptyLevel.pde)

### Creating a New Level

1. Create a new `.pde` file (e.g., `MySimulation.pde`)
2. Extend the `Level` class
3. Implement required methods:
   - `String getName()` - Display name
   - `void onStart()` - Initialization when level starts
   - `void onUpdate(float dt, Inputs inputs)` - Per-frame update
   - `void onDraw(PGraphics g)` - Rendering to offscreen buffer
   - `void onDispose()` - Cleanup when level stops

4. Register in `VJSims.pde` → `registerLevels()`

### Synesthesia Audio OSC Integration (TODO)

To receive audio from Synesthesia:

1. Add oscP5 listener in `SharedContext.pde`
2. Map OSC messages to `AudioEnvelope` properties:
   - `/audio/bass` → `setBass(float)`
   - `/audio/mid` → `setMid(float)`
   - `/audio/high` → `setHigh(float)`
   - `/audio/bpm` → BPM tracking
3. Update documentation once implemented

## Performance

- Target: 60 FPS at 1280x720
- Use `P3D` renderer for GPU acceleration
- Offscreen buffer (`PGraphics`) prevents direct drawing overhead
- Audio envelope smoothing prevents jitter

## Launchpad Setup

1. Put Launchpad Mini Mk3 in **Programmer mode**:
   - Hold `Session` button
   - Press top-left orange pad
   - Release both
2. LEDs will pulse to confirm mode
3. VJSims auto-detects device on startup

## Syphon Output

VJSims outputs to Syphon server named `"VJSims"`. Receive in:

- Magic Music Visuals (Media Sources → Syphon)
- Synesthesia (Import → Syphon)
- MadMapper, VPT, or any Syphon client

## Example Levels (TODO)

Planned simulation levels:

1. Gravity Wells - Particle attraction/repulsion
2. Jelly Blobs - Metaball physics
3. Wave Interference - 2D wave simulation
4. Fluid Dynamics - GPU-accelerated flow
5. Geometric Morphing - Shape transitions
6. Particle Storms - Mass particle systems
7. Audio Landscape - Terrain generation from audio
8. And more...

## License

See individual files for licensing. Original concept and framework by the Synesthesia Visuals project.

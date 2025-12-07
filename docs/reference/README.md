# Reference Documentation

Technical references, guides, and API documentation for the VJ toolkit components.

## Processing Guides

### Comprehensive Guide Series
- **[Processing VJ Guides](processing-guides/README.md)** - Complete series for creating interactive, audio-reactive simulations
  - [Overview](processing-guides/00-overview.md) - System architecture, quick start, performance targets
  - [Core Concepts](processing-guides/01-core-concepts.md) - Module lifecycle, coordinate systems, anti-patterns
  - [Audio Reactivity](processing-guides/02-audio-reactivity.md) - FFT analysis, beat detection, BPM calculation
  - [Particle Systems](processing-guides/03-particle-systems.md) - CPU & GPU particles, PixelFlow (100k+ particles)
  - [Fluid Simulations](processing-guides/04-fluid-simulations.md) - Reaction-diffusion, flow fields, GPU fluids
  - [Design Philosophy](processing-guides/05-design-philosophy.md) - VJ design principles and best practices
  - [Interactivity](processing-guides/06-interactivity.md) - MIDI, OSC, and user input patterns
  - [Code Patterns](processing-guides/08-code-patterns.md) - Copy-paste ready modules and algorithms
  - [Resources](processing-guides/09-resources.md) - Libraries, tools, examples, learning materials

### Advanced Examples
- **[Processing Levels](processing-levels/README.md)** - 14 detailed visual concept implementations
  - Gravity Wells, Jelly Blobs, Agent Trails
  - Reaction Diffusion, Recursive City, Liquid Floor
  - Cellular Automata, Portal Raymarcher, Rope Simulation
  - Logo Wind Tunnel, Swarm Cameras, Time Smear
  - Mirror Rooms, Text Engine
  - [Common Reference](processing-levels/00-common.md) - Shared patterns and conventions

## Shader References

- **[ISF to Synesthesia Migration](isf-to-synesthesia-migration.md)** - Complete guide for converting shaders
  - ISF/Shadertoy to Synesthesia SSF format
  - Uniform mapping and audio reactivity
  - Control patterns and best practices
  - Troubleshooting common issues

## Audio & Analysis

See also: [Python VJ Documentation](../../python-vj/README.md)

### Core Documentation
- **Audio Analyzer** - Essentia-based audio analysis
  - [Essentia Integration](../../python-vj/ESSENTIA_INTEGRATION.md) - Advanced beat/tempo/pitch detection
  - [EDM Features Guide](../../python-vj/EDM_FEATURES_GUIDE.md) - Electronic music feature extraction
  - [OSC Visual Mapping](../../python-vj/OSC_VISUAL_MAPPING_GUIDE.md) - Audio → Visual parameter mapping

### MIDI Routing
- **[MIDI Router](../../python-vj/MIDI_ROUTER.md)** - Stateful MIDI middleware with toggle management
- **[MIDI Router Quick Reference](../../python-vj/MIDI_ROUTER_QUICK_REF.md)** - Command cheat sheet

### Feature Comparisons
- **[Python vs MMV Features](../../python-vj/FEATURE_COMPARISON_PYTHON_VS_MMV.md)** - Capability comparison

## Key Technologies

### Processing
- **Resolution**: Always use 1920x1080 (Full HD) for VJ output
- **Renderer**: Use P3D (required for Syphon on macOS)
- **Libraries**: The MidiBus, Syphon, PixelFlow

### Synesthesia (SSF Format)
- **Auto-injected uniforms**: TIME, RENDERSIZE, syn_BassLevel, syn_Spectrum, etc.
- **File structure**: .synScene/ directories with main.glsl, scene.json, optional script.js
- **Audio reactivity**: Built-in audio analysis uniforms

### Python VJ Stack
- **Audio**: sounddevice, Essentia, NumPy FFT
- **Communication**: python-osc, MIDI via mido
- **UI**: Textual for terminal interface

### Frame Sharing
- **Syphon** (macOS) - Low-latency frame sharing between apps
- **Spout** (Windows) - Alternative for Windows
- **NDI** (Cross-platform) - Network-based video

## Conventions & Standards

### Processing Type Safety
```java
// Use float for hue/saturation/brightness
float hue = 0.5f;  // Add 'f' suffix to literals

// Cast explicitly when mixing types
int x = (int)pos.x;

// PVector coordinates
PVector pos = new PVector(100, 200);
```

### Launchpad Grid (Programmer Mode)
```
8x8 pad grid: notes 11-88
note = (row+1)*10 + (col+1)

Utility functions in lib/LaunchpadUtils.pde:
- noteToGrid(note) → PVector(col, row)
- gridToNote(col, row) → MIDI note
- isValidPad(note) → boolean
```

### SSF Shader Pattern
```glsl
// Don't declare these - auto-injected by Synesthesia
uniform float TIME;
uniform vec2 RENDERSIZE;
uniform float syn_BassLevel;

vec4 renderMain(void) {
    // Your shader code
    return vec4(color, 1.0);
}
```

### VJ Output Design Principles
1. **No UI on screen** - No status text, scores, or instructions
2. **Design for overlay compositing** - Black backgrounds, high contrast
3. **Emphasize particle effects** - Dramatic, dynamic, always moving
4. **Separate controller and visual logic** - MIDI for performer, screen for audience

## Performance Targets

### Processing Sketches
- **Target**: 60 fps at 1920x1080
- **CPU**: <15% per sketch
- **Particles**: 100k+ with GPU acceleration (PixelFlow)

### Python Audio Analyzer
- **Latency**: ~10ms analysis + <1ms OSC transmission
- **CPU**: 5-10%
- **Frame rate**: 60+ fps

### End-to-End Pipeline
- **Total latency**: ~30ms (audio → visual output)
- **Combined CPU**: ~10-15%

## API Quick Reference

### Processing + Syphon
```java
import codeanticode.syphon.*;
SyphonServer syphon;

void settings() { size(1920, 1080, P3D); }
void setup() { syphon = new SyphonServer(this, "GameName"); }
void draw() { 
    // render
    syphon.sendScreen();
}
```

### Processing + MIDI
```java
import themidibus.*;
MidiBus midi;

void setup() {
    midi = new MidiBus(this, "Launchpad Mini MK3", "Launchpad Mini MK3");
}

void noteOn(int channel, int pitch, int velocity) {
    // handle MIDI input
}
```

### Python OSC
```python
from pythonosc import osc_message_builder, udp_client

client = udp_client.SimpleUDPClient("127.0.0.1", 9000)
client.send_message("/audio/level", [0.5, 0.3, 0.8])
```

## See Also

- [Setup Guides](../setup/) - Installation and configuration
- [Operation Guides](../operation/) - How to use in performance
- [Development Plans](../development/) - Implementation roadmaps
- [Architecture](../architecture/) - System design (when created)

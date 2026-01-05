# Reference Documentation

Technical references, guides, and API documentation for the VJ toolkit components.

## Swift-VJ Reference

### Core Documentation
- **[Swift-VJ README](../../swift-vj/README.md)** - Overview and quick start
- **[Swift-VJ Rewrite Plan](../../swift-vj/REWRITE_PLAN.md)** - Complete architecture and feature inventory
  - Domain types and pure functions
  - Adapters (LyricsFetcher, OSCHub, VDJMonitor, etc.)
  - Modules (Playback, Lyrics, AI, Shaders, Pipeline, Launchpad)
  - SwiftUI application and Metal rendering
  - 197 tests with TDD approach

### Metal Rendering
- **Shader tiles**: GLSL shaders rendered with Metal pipeline
- **Text tiles**: Lyrics, refrain, song info with SwiftUI
- **Image tiles**: Beat-synced image cycling with crossfades
- **Syphon output**: Frame sharing to VJ software

### Launchpad MIDI Control
- **CoreMIDI integration**: Native device discovery
- **4 pad modes**: SELECTOR, TOGGLE, ONE_SHOT, PUSH
- **Learn mode**: Interactive pad mapping
- **LED control**: 10 colors × 3 brightness levels
- **Beat sync**: BPM-based LED blinking

## Archived: Processing Guides

> **⚠️ ARCHIVED:** Processing guides have been archived as of 2026-01-05. See [PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md](../../PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md).

### Comprehensive Guide Series (Archived)
- **[Processing VJ Guides](processing-guides/README.md)** - Complete series for creating interactive, audio-reactive simulations
  - Preserved for reference in `archive/processing-vj/`
  - Replaced by Swift-VJ Metal rendering

### Advanced Examples (Archived)
- **[Processing Levels](processing-levels/README.md)** - 14 detailed visual concept implementations
  - Archived - use Swift-VJ shader tiles instead

## Shader References

- **[ISF to Synesthesia Migration](isf-to-synesthesia-migration.md)** - Complete guide for converting shaders
  - ISF/Shadertoy to Synesthesia SSF format
  - Uniform mapping and audio reactivity
  - Control patterns and best practices
  - Troubleshooting common issues

## Audio & Analysis

### Synesthesia Integration
- **Primary audio analysis**: Synesthesia native OSC output (port 9999)
- **Swift-VJ integration**: OSCHub receives and forwards audio data
- **Low latency**: ~10-30ms for tight audio reactivity
- **Features**: Bass/mid/high levels, beat detection, BPM, spectrum

### Archived: Python-VJ Audio
- **[Python VJ Documentation](../../archive/python-vj/README.md)** - Legacy Python VJ Console
- **Audio Analyzer** - Replaced by Synesthesia native OSC
  - Archived Essentia-based implementation
  - See migration guide for feature parity

## Key Technologies

### Swift-VJ
- **Platform**: macOS 14.0+ (Sonoma)
- **Language**: Swift 5.9+
- **Rendering**: Metal for GLSL shaders
- **UI**: SwiftUI native
- **MIDI**: CoreMIDI
- **Tests**: 197 tests with TDD

### Synesthesia (SSF Format)
- **Auto-injected uniforms**: TIME, RENDERSIZE, syn_BassLevel, syn_Spectrum, etc.
- **File structure**: .synScene/ directories with main.glsl, scene.json, optional script.js
- **Audio reactivity**: Built-in audio analysis uniforms

### Archived: Processing
- **Status**: Archived 2026-01-05
- **Replacement**: Swift-VJ Metal rendering
- **Legacy docs**: See `archive/processing-vj/` for preserved code

### Frame Sharing
- **Syphon** (macOS) - Low-latency frame sharing between apps
- **Spout** (Windows) - Alternative for Windows
- **NDI** (Cross-platform) - Network-based video

## Conventions & Standards

### Swift-VJ OSC Messages
```swift
// Playback
/textler/track [active, source, artist, title, album, duration, has_lyrics]
/textler/line/active [index]

// Audio (from Synesthesia)
/audio/bass [level]
/audio/mid [level]
/audio/high [level]

// Shaders
/shader/load [name, energy, valence]
```

### Launchpad Grid (Programmer Mode)
```
8x8 pad grid: notes 11-88
note = (row+1)*10 + (col+1)

Swift-VJ provides learn mode for easy pad mapping
CoreMIDI handles device discovery automatically
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
3. **Emphasize dynamic motion** - Particle effects, animations, always moving
4. **Separate controller and visual logic** - MIDI for performer, screen for audience

## Performance Targets

### Swift-VJ
- **Rendering**: 60 fps at configurable resolution
- **Metal shaders**: GPU-accelerated, minimal CPU overhead
- **Latency**: ~30ms total (audio → visual output)
- **CPU usage**: <10% for typical workload

### End-to-End Pipeline
- **Synesthesia analysis**: ~10-30ms latency
- **OSC transmission**: <1ms
- **Swift-VJ rendering**: ~16ms (60 fps)
- **Total latency**: ~30-50ms (audio → visual output)

## API Quick Reference

### Swift-VJ + Syphon
```swift
import Syphon

class SyphonOutput {
    private var server: SyphonServer?
    
    func start(name: String) {
        server = SyphonServer(name: name)
    }
    
    func publish(texture: MTLTexture) {
        server?.publish(texture: texture)
    }
}
```

### Swift-VJ + CoreMIDI
```swift
import CoreMIDI

class MIDIManager {
    func discoverDevices() -> [MIDIDevice] {
        // Automatic device discovery
    }
    
    func sendNoteOn(note: UInt8, velocity: UInt8) {
        // Send MIDI note
    }
}
```

### Swift OSC
```swift
import OSCKit

let client = OSCClient(host: "127.0.0.1", port: 9000)
client.send("/audio/level", [0.5, 0.3, 0.8])
```

## See Also

- [Setup Guides](../setup/) - Installation and configuration
- [Operation Guides](../operation/) - How to use in performance
- [Development Plans](../development/) - Implementation roadmaps
- [Migration Guide](../../PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md) - Python-VJ/Processing-VJ to Swift-VJ
- [Archived Components](../../archive/README.md) - Legacy systems and documentation

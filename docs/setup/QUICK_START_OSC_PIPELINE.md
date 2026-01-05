# Quick Start: Synesthesia Audio Analysis Pipeline

This guide shows how to use Synesthesia for audio analysis in your VJ setup.

## What You Get

**Synesthesia** (professional audio analysis engine)
  ↓ OSC messages (port 9999)
**Swift-VJ OSC Hub** (central router in swift-vj)
  ↓ OSC messages (port 9000)
**Swift-VJ/Magic/Resolume** (VJ visuals)
  ↓ Syphon frames
**Final output** (projectors, screens, streaming)

## Why Synesthesia?

- **Professional-grade** audio analysis with superior accuracy
- **Low latency** (~10-30ms) for tight audio reactivity
- **Built-in** shader support with audio uniforms
- **Reliable** and actively maintained
- **No dependencies** - everything included

## Setup (5 minutes)

### 1. Install Synesthesia

Download from [synesthesia.live](https://synesthesia.live/)

### 2. Configure Audio Input

**Option A: BlackHole (recommended for system audio)**
```bash
# Install BlackHole 2ch from https://existential.audio/blackhole/
# Create Multi-Output Device in Audio MIDI Setup:
#   1. Built-in Output + BlackHole 2ch
#   2. Set as system output
#   3. Synesthesia will detect BlackHole
```

**Option B: Microphone**
- Synesthesia will use default input device
- Or select manually in Synesthesia preferences

### 3. Configure Synesthesia OSC Output

1. Open Synesthesia preferences
2. Navigate to OSC settings
3. Enable "Send audio analysis via OSC"
4. **Set target to localhost:9999** (Swift-VJ Hub receives here)
5. Configure which features to send (bass, mid, high, spectrum, etc.)

### 4. Start Swift-VJ

Swift-VJ includes an OSC hub that receives audio data from Synesthesia and routes it to other applications:

```bash
cd swift-vj
swift build
swift run swift-vj  # Starts OSC hub automatically
```

## Using with VJ Software

### Architecture Overview

```
Synesthesia (port 9999) → Swift-VJ OSC Hub (port 9000) → VJ Apps/Rendering
```

Swift-VJ acts as a central router, receiving OSC from Synesthesia and forwarding to all VJ applications. It also uses the audio data for its own Metal-based rendering engine.

### Swift-VJ Rendering

Swift-VJ includes built-in rendering that receives audio data directly from the OSC hub:

- **Shader tiles**: Audio-reactive GLSL shaders rendered with Metal
- **Text tiles**: Lyrics and song info with beat-synced animations
- **Image tiles**: Beat-synced image cycling with crossfades
- **Syphon output**: Send to Magic, Resolume, VDMX, etc.

### VJ Software Integration

- **Magic Music Visuals**: Built-in Synesthesia support
- **Resolume**: Use OSC routing
- **VDMX**: Configure OSC input
- **MadMapper**: OSC control mapping

## Migrating from Python-VJ

Python-VJ has been archived and replaced by Swift-VJ. See [PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md](../../PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md) for details.

Benefits of Swift-VJ:

| Feature | Python-VJ | Swift-VJ |
|---------|-----------|----------|
| Rendering | Processing/Java | Metal (2x faster) |
| UI | Textual TUI | Native SwiftUI |
| MIDI | rtmidi wrapper | CoreMIDI |
| OSC | python-osc | Native Swift |
| Platform | Cross-platform | macOS optimized |
| Tests | Some | 197 tests |

## Troubleshooting

**No audio detected:**
- Check audio input device in Synesthesia preferences
- Verify Multi-Output Device includes BlackHole
- Try adjusting input gain

**OSC not working:**
- Verify OSC enabled in Synesthesia preferences
- Check port number matches (default 9999 for Synesthesia → Swift-VJ)
- Check Swift-VJ OSC debug view for incoming messages

**Migration from Python analyzer:**
- Synesthesia provides all audio analysis features
- Superior quality and reliability
- Native shader integration

## Next Steps

- Explore Synesthesia's built-in shaders with audio reactivity
- Create custom shaders using the [Shadertoy to Synesthesia converter](../../.github/prompts/shadertoy-to-synesthesia-converter.prompt.md)
- Configure Swift-VJ rendering with custom tiles and parameters
- Set up Launchpad MIDI control for live performance

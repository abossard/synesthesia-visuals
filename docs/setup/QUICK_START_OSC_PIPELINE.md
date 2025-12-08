# Quick Start: Synesthesia Audio Analysis Pipeline

This guide shows how to use Synesthesia for audio analysis in your VJ setup.

## What You Get

**Synesthesia** (professional audio analysis engine)
  ↓ OSC messages  
**Processing/Magic/VPT** (VJ visuals)
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

### 3. Enable OSC Output in Synesthesia

1. Open Synesthesia preferences
2. Navigate to OSC settings
3. Enable "Send audio analysis via OSC"
4. Set target port (default: 9000)
5. Configure which features to send (bass, mid, high, spectrum, etc.)

## Using with Processing/VJ Software

### Processing Integration

Processing sketches can receive Synesthesia's OSC messages:

```processing
import oscP5.*;
import netP5.*;

OscP5 oscP5;

void setup() {
  oscP5 = new OscP5(this, 9000);  // Synesthesia default port
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/audio/bass")) {
    float bassLevel = msg.get(0).floatValue();
    // Use bassLevel for visuals
  }
}
```

See `processing-vj/src/VJSims/` for examples of Synesthesia OSC integration.

### VJ Software Integration

- **Magic Music Visuals**: Built-in Synesthesia support
- **Resolume**: Use OSC routing
- **VDMX**: Configure OSC input
- **MadMapper**: OSC control mapping

## Migrating from Python Audio Analyzer

The Python/Essentia audio analyzer has been removed. Benefits of switching to Synesthesia:

| Feature | Python Analyzer | Synesthesia |
|---------|-----------------|-------------|
| Latency | ~50-100ms | ~10-30ms |
| Accuracy | Good | Excellent |
| Setup | Complex (dependencies) | Simple (standalone) |
| Reliability | Occasional crashes | Rock solid |
| Integration | Custom OSC | Native + OSC |

## Troubleshooting

**No audio detected:**
- Check audio input device in Synesthesia preferences
- Verify Multi-Output Device includes BlackHole
- Try adjusting input gain

**OSC not working:**
- Verify OSC enabled in Synesthesia preferences
- Check port number matches (default 9000)
- Test with OSC monitor tool

**Previous Python analyzer removed:**
- Synesthesia provides all audio analysis features
- Superior quality and reliability
- Native shader integration

## Next Steps

- Explore Synesthesia's built-in shaders with audio reactivity
- Create custom shaders using the [Shadertoy to Synesthesia converter](.github/prompts/shadertoy-to-synesthesia-converter.prompt.md)
- Build interactive visuals in Processing with VJSims framework

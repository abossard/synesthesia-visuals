# Copilot Instructions for synesthesia-visuals

## Project Overview
A VJ performance toolkit combining:
- **Synesthesia shaders** (`.synScene` directories with GLSL + JSON + JS)
- **Processing games** (Java sketches with Launchpad MIDI control)
- **Syphon pipeline** for frame sharing between apps

## Repository Structure
```
synesthesia-shaders/     # SSF scenes (main.glsl, scene.json, optional script.js)
processing-vj/
  ├── examples/          # Game implementations (WhackAMole, SnakeGame, etc.)
  └── lib/               # LaunchpadUtils.pde - shared MIDI utilities
docs/                    # ISF migration guide, live setup, MIDI controller docs
```

## Synesthesia Shader (SSF) Conventions

### File Structure
Each `.synScene/` directory requires:
- `main.glsl` - fragment shader with `vec4 renderMain(void)` entry point
- `scene.json` - metadata, controls, passes, media config
- `script.js` (optional) - per-frame state/smoothing logic

### Key SSF Uniforms (DO NOT declare these)
```glsl
// Auto-injected by Synesthesia:
TIME, RENDERSIZE, PASSINDEX, FRAMECOUNT
_xy (pixel coords), _uv (normalized 0-1), _uvc (aspect-correct)
_mouse, _muv, _textureMedia(), _loadMedia()
syn_BassLevel, syn_MidLevel, syn_HighLevel, syn_Level
syn_BassHits, syn_HighHits, syn_BeatTime, syn_BPM
syn_Spectrum (sampler1D), syn_LevelTrail (sampler1D)
```

### Control Mapping Pattern
```json
// scene.json controls → uniform auto-injection
{
  "NAME": "warp_amount",      // becomes `uniform float warp_amount;`
  "TYPE": "slider",           // slider | xy | color | toggle | bang | dropdown
  "MIN": 0.0, "MAX": 1.0, "DEFAULT": 0.3,
  "UI_GROUP": "Warp"          // groups controls in UI
}
```

### Audio Reactivity Pattern
```glsl
// Always-moving base + audio boost
float baseTime = TIME * 0.3;
float audioTime = syn_Time * 0.5;
float t = baseTime + audioTime * bpm_sync;

// Bass-triggered effects with threshold
float bassActive = smoothstep(bass_threshold, bass_threshold + 0.1, syn_BassHits);
```

## Processing Game Conventions

### Critical Requirements
- **Resolution**: Always use **1920x1080** (Full HD) for VJ output compatibility
- **Syphon Output**: Always include `SyphonServer` with `sendScreen()` in draw loop
- **MIDI Robustness**: MIDI can fail - always auto-detect devices and provide mouse/keyboard fallback
- **Renderer**: Use `P3D` (required for Syphon on macOS)
- **Type Safety**: Processing is strict about types:
  - Use `float` for hue/saturation/brightness values, not `color`
  - Add `f` suffix to float literals in expressions (e.g., `0.3f` not `0.3`)
  - Cast explicitly when mixing int/float (e.g., `(int)pos.x`)

### VJ Output Design Principles

All Processing projects are designed for live VJ performance. Follow these critical visual guidelines:

1. **No Controller UI on Screen**: The screen output should NEVER reveal that it's Launchpad-controlled
   - ❌ No "Launchpad Connected" / "Mouse Mode" status text
   - ❌ No grid representations showing controller layout
   - ❌ No score counters, lives, or game state text
   - ❌ No instructions or debug overlays

2. **Design for Overlay Compositing**: Projects will be layered using blend modes in VJ software
   - Use `background(0)` - black becomes transparent in Add/Screen blend modes
   - Use high contrast white/bright elements that punch through overlays
   - Prefer outlines over filled shapes for cleaner blending
   - Monochrome (black/white) visuals composite cleanly

3. **Emphasize Particle Effects**: VJ visuals should be dramatic and dynamic
   - Use hundreds/thousands of particles for explosions
   - Semi-transparent backgrounds for trail/ghosting effects
   - Use PixelFlow for GPU-accelerated fluid simulations
   - Always-moving visuals even without input

4. **Separation of Controller and Visual Logic**:
   - Launchpad LEDs = feedback for performer (private)
   - Screen output = visuals for audience (public via Syphon)

### MIDI Setup Pattern
```java
// Always scan for device, fall back gracefully
MidiBus launchpad;
boolean hasLaunchpad = false;

void initMidi() {
  String[] inputs = MidiBus.availableInputs();
  for (String dev : inputs) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      try {
        launchpad = new MidiBus(this, dev, dev);
        hasLaunchpad = true;
      } catch (Exception e) {
        hasLaunchpad = false;
      }
      break;
    }
  }
  // Games must work keyboard/mouse-only when no Launchpad connected
}

// Guard ALL MIDI calls
void lightPad(int col, int row, int color) {
  if (!hasLaunchpad || launchpad == null) return;
  launchpad.sendNoteOn(0, gridToNote(col, row), color);
}
```

### Launchpad Grid (Programmer Mode)
- 8x8 pad grid: notes 11-88 where `note = (row+1)*10 + (col+1)`
- Utility functions in `lib/LaunchpadUtils.pde`:
  - `noteToGrid(note)` → `PVector(col, row)` (0-7)
  - `gridToNote(col, row)` → MIDI note
  - `isValidPad(note)` → excludes scene buttons
  - Color constants: `LP_RED=5`, `LP_GREEN=21`, `LP_BLUE=45`, etc.

### Required Libraries
- **The MidiBus** - MIDI I/O
- **Syphon** - frame sharing (x86_64 only on Apple Silicon - use Intel Processing)
- **PixelFlow** (optional) - GPU fluid/particles

### Syphon Pattern (Required for all games)
```java
import codeanticode.syphon.*;
SyphonServer syphon;

void settings() { size(1920, 1080, P3D); }  // Full HD, P3D required
void setup() { syphon = new SyphonServer(this, "GameName"); }
void draw() { 
  // ... render game ...
  syphon.sendScreen();  // Always at end of draw()
}
```

**Off-screen buffer pattern** (for projection mapping):
```java
PGraphics canvas;
SyphonServer server;

void setup() {
  size(1280, 720, P3D);
  canvas = createGraphics(1280, 720, P3D);
  server = new SyphonServer(this, "ProcessingCanvas");
}

void draw() {
  canvas.beginDraw();
  canvas.background(0);
  // draw all content into canvas
  canvas.endDraw();
  image(canvas, 0, 0);
  server.sendImage(canvas);  // Send off-screen buffer
}
```

**Receiving Syphon frames**:
```java
SyphonClient client;
PGraphics canvas;

void setup() {
  client = new SyphonClient(this);  // Connects to first available server
  // Or specify: new SyphonClient(this, "AppName", "ServerName");
}

void draw() {
  if (client.newFrame()) {
    canvas = client.getGraphics(canvas);
    image(canvas, 0, 0);
  }
}
```

## Development Workflows

### Testing Shaders
1. Copy `.synScene/` to Synesthesia custom library folder
2. Reload library in Synesthesia
3. Use Stats overlay to verify performance

### Testing Processing Games
1. Put Launchpad in Programmer mode: hold Session → press orange button → release
2. Run sketch from Processing IDE
3. Keyboard fallbacks should work without Launchpad

### Live Rig Audio Routing (macOS)
- Install BlackHole for audio loopback
- Create Multi-Output Device (speakers + BlackHole)
- Set Synesthesia audio input to BlackHole

## Key Files Reference
- [docs/reference/isf-to-synesthesia-migration.md](../docs/reference/isf-to-synesthesia-migration.md) - comprehensive shader conversion guide
- [docs/setup/live-vj-setup-guide.md](../docs/setup/live-vj-setup-guide.md) - full Syphon/Magic/VPT pipeline
- [docs/setup/midi-controller-setup.md](../docs/setup/midi-controller-setup.md) - Launchpad/MIDImix configuration
- [processing-vj/lib/LaunchpadUtils.pde](../processing-vj/lib/LaunchpadUtils.pde) - grid conversion, LED colors

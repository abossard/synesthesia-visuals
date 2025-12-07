# Processing VJ System — Common Reference

Shared guidance for all levels in the Processing → Syphon VJ system.

## Launchpad Control Guidance

- **Device/mode:** Launchpad Mini Mk3 in **Programmer mode** (enter Settings → press the orange Scene Launch button → exit Settings). This exposes the full 8×8 grid plus the right-column scene buttons without DAW behavior.

### Pad Note Layout

- Grid rows from bottom to top use notes `11–18`, `21–28`, …, `81–88`
- Right-column scene buttons use `19–89`
- See [MIDI Controller Setup](../../setup/midi-controller-setup.md) for details

Convert notes to grid coords:
```
col = (note % 10) - 1
row = (note / 10) - 1
```

### LED Colors

Send note-on with velocity to set pad color:
- `0` = off
- `4–7` = red
- `8–11` = orange  
- `16` = green
- `21` = bright green
- `45` = blue

Light pads that are active; dim pads for available actions.

### Baseline Mapping Template

| Row | Notes | Purpose |
|-----|-------|---------|
| **Top (7)** | 71–78 | Level selection / global toggles |
| **Row 6** | 61–68 | Per-level macro toggles |
| **Row 5** | 51–58 | Transport / parameter group A |
| **Row 4** | 41–48 | Parameter group B |
| **Row 3** | 31–38 | Global macros (camera, audio-reactivity) |
| **Middle** | 21–28, etc. | Per-effect controls |
| **Bottom (1)** | 11–18 | Transport: start/stop, tap tempo, BPM sync |
| **Scene buttons** | 19–89 | Shift modifiers, exit arm |

### Continuous Parameters via Pads

- **Tap-to-cycle:** each column cycles through 4–8 preset values; LED color indicates current level
- **Hold + tap:** hold scene button as "shift", then tap grid pad to increment/decrement
- **Velocity sensitivity:** pad velocity sets initial intensity

### Starter Code Snippet

```java
void settings() {
  size(1920, 1080, P3D);  // Always use P3D for Syphon + 3D camera/particle effects
}

// Convert Launchpad note to grid coordinate
void noteOn(int channel, int pitch, int velocity) {
  int col = (pitch % 10) - 1;
  int row = (pitch / 10) - 1; // 0 = bottom row
  if (col >= 0 && col < 8 && row >= 0 && row < 8) {
    handlePadPress(col, row, velocity);
    lightPad(pitch, velocity > 0 ? 16 : 0); // example LED echo
  }
}
```

Keep this mapping consistent across all levels so the Launchpad feels like a shared "HUD".

---

## Quick Build Pipeline

1. Prototype in Processing with **P3D renderer** (required for Syphon, enables 3D camera, particles, perspective effects)
2. Add Syphon output: `SyphonServer server = new SyphonServer(this, "Processing");`
3. Map Launchpad pads via [The MidiBus](http://www.smallbutdigital.com/themidibus.php); use tap-to-cycle for continuous parameters
4. Feed Syphon into Magic/Synesthesia; layer ISF shaders for color grading, warps, feedback, kaleidoscope

---

## Level State Machine Pattern

Every level owns a small FSM with an explicit `Exit` state:

- **Idle states** still animate lightly so motion never fully stops
- **Pads/scene buttons** advance the local FSM
- **Global manager** handles level swaps when FSM reaches Exit

### Common States

| State | Description |
|-------|-------------|
| `Idle` | Minimal animation, waiting for input |
| `Active` / `Play` | Main interaction mode |
| `Peak` | Maximum intensity, triggered by audio or pad |
| `Cooldown` / `Settle` | Returning to idle |
| `Exit` | Ready for level transition |

---

## Architecture Overview

### Core Components

```
state: intro → levelSelect → level(n) → transition → level(n+1 mod N)
```

- **State manager:** enum (`INTRO, SELECT, LEVEL, TRANSITION`) with `Level` interface
- **Per-level FSMs:** each level owns its own small FSM
- **Shared services:** MIDI router, Syphon server, audio envelope, history buffer
- **Transitions:** crossfade or radial wipe between levels

### Launchpad as Level HUD

- **Top row (71–78):** level slots 1–8, press to jump, hold to arm "next on drop"
- **Row 6:** per-level macros (freeze, randomize, palette)
- **Row 5:** transport controls
- **Scene buttons:** shift modifiers, exit arm
- **LED feedback:** green = active, amber = queued, red pulse = transitioning

### Resource Management

- Each level keeps own `PGraphics`/`PShader` objects
- Shared audio and MIDI callbacks dispatch to active level
- Use `frameRate(60)` with global budget; heavy levels use lower internal resolution

---

## Coding Guidance

Based on *Grokking Simplicity* and *A Philosophy of Software Design*:

- **Make state explicit:** keep level data in plain `LevelState` objects
- **Isolate effects:** MIDI, audio, Syphon in thin adapters
- **Deep modules:** each module owns its invariants (`LaunchpadGrid` owns note↔cell math)
- **No temporal coupling:** `init()` returns ready objects
- **Name for intent:** `EnergySlam` > `PadX17`

### Module Layout

```
midi/
  LaunchpadGrid.pde   — note↔cell math, LED helpers
fsm/
  LevelFSM.pde        — table-driven FSM
levels/
  Level.pde           — interface
  GravityWellsLevel.pde
  ...
core/
  LevelManager.pde    — global loop, level swaps
  SharedContext.pde   — framebuffer, syphon, config
graphics/
  LazyBuffer.pde      — allocate-once wrapper
  HistoryBuffer.pde   — circular buffer for trails
```

### Level Interface

```java
interface Level {
  void init(SharedContext ctx);
  void update(float dt, Inputs inputs);
  void draw(PGraphics g);
  void handlePad(int col, int row, int velocity);
  LevelFSM getFSM();
  void dispose();
}
```

---

## Related Documents

- [Implementation Plan](../../development/processing-implementation-plan.md) — step-by-step build guide
- [MIDI Controller Setup](../../setup/midi-controller-setup.md) — Launchpad configuration
- [Live VJ Setup Guide](../../setup/live-vj-setup-guide.md) — Syphon + Magic pipeline
- [Level Index](./README.md) — all 14 level designs

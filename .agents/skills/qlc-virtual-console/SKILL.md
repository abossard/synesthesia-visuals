---
name: qlc-virtual-console
description: >
  Design QLC+ Virtual Console layouts — covers audio-reactive OSC faders,
  submaster control, frame-based grouping, and layer architecture for VC widgets.
  USE FOR: VC slider setup, OSC input mapping, submaster patterns, audio reactivity
  control, frame organization, level vs submaster modes.
  DO NOT USE FOR: function creation (use qlc-moving-head), fixture patching, shader code.
metadata:
  author: André Bossard
  version: "1.0"
---

# QLC+ Virtual Console Patterns

## Audio-Reactive OSC Control

### Architecture: Frame + Submaster

Use a **frame** with a **submaster slider** to control all audio-reactive inputs as a group.

```
┌─ Audio Reactive Frame ──────────────────┐
│                                          │
│  [Wash OSC]   [Spot OSC]   [Sub Master] │
│   level        level        submaster    │
│   ch13         ch5          (scales all) │
│   ← OSC in     ← OSC in                 │
│                                          │
└──────────────────────────────────────────┘
```

### How it works

1. **OSC level sliders** receive values from external sources (e.g. Magic Music Visuals shader)
2. Each slider targets a specific fixture channel in **level mode**
3. The **submaster slider** scales all output from sibling widgets proportionally:
   - Submaster 0% → all outputs zero (audio reactivity off)
   - Submaster 50% → all outputs halved
   - Submaster 100% → full passthrough
4. The **frame enable button** provides instant on/off toggle

### Creating the widgets

```
1. Create a Frame (parent container) using pageIndex
   - For nested frames, use parentID instead of pageIndex
2. Add level sliders inside the frame:
   - mode: "level"
   - channels: [{fixtureID: 0, channel: 13}]  (wash dimmer example)
   - Map OSC input via: inputUniverse + inputChannel
3. Add one submaster slider inside the same frame:
   - mode: "submaster"
   - No channel binding needed — it scales all siblings
```

> **Note:** Channel numbers are fixture-specific. Always call `query_fixture_channels` first to discover the correct channel indices for your fixtures.

### OSC Input Mapping

To connect a slider to an OSC source:
- **inputUniverse**: QLC+ universe index (0-based) with OSC plugin configured
- **inputChannel**: Auto-detect by sending OSC from source, or look up in Input/Output panel
- **Multiple inputs**: Use `map_vc_inputs` with `mode: "add"` to bind multiple controllers to one widget

QLC+ derives OSC channel numbers from the OSC address path. Use auto-detect when setting up manually.

### Slider Modes

| Mode | Purpose | Channel binding |
|------|---------|----------------|
| **level** | Writes directly to DMX channel(s) | Required — specify fixture + channel |
| **submaster** | Scales all sibling widgets' output | None — affects parent frame's children |

### Key Behaviors

- Level sliders are **always active** — they write to DMX continuously, like Simple Desk faders
- They participate in HTP/LTP like any other source
- Submaster only affects widgets in the **same frame**
- Frame enable button stops all child widget output instantly

## Layer Separation with VC

### Problem: Channel Conflicts

When multiple sources write to the same DMX channel:
- **HTP channels** (default for intensity): highest value wins — can't dim below other sources
- **LTP channels**: last writer wins — continuous OSC updates override scene values

### Solution: Exclusive Channel Ownership

Each layer (movement, look, wash) must own its channels exclusively:

| Layer | Channels | VC Widgets | Functions |
|-------|----------|------------|-----------|
| Movement | 0–5 | — | MV: scenes/chasers |
| Look | 6–12 | — | LK: scenes |
| Wash | 13–18 | OSC sliders | WS: scenes |

**Critical rule:** No scene outside the wash layer should include ch13–18. No VC slider should target movement channels.

## Combining OSC with Scene-Based Control

### Use Case: Audio-reactive wash in a chaos buildup

The chaos buildup chaser steps through collections, each with a wash scene setting RGBW colors. The OSC fader independently drives wash dimmer (ch13).

**When ch13 is LTP** (forced via `configure_channels`):
- The scene and the OSC slider both write to ch13
- Whichever wrote last wins
- OSC at ~60Hz usually wins over static scene values

**Practical solution for phased control:**
- Phases 1–3: wash scenes set ch13 to fixed values (0, 80, 180) — scene controls brightness
- Phases 4–5: wash scenes omit ch13 — OSC fader takes over (audio-reactive brightness)
- Use the submaster to scale overall audio reactivity intensity

### Frame Enable as Phase Gate

Alternative approach: keep the audio reactive frame **disabled** during early phases. Enable it manually or via a button when you want audio reactivity to kick in. The frame enable button acts as a binary gate.

# Light Brief 26 — Laser Imitation System

## Concept
Imitate a laser beam using the Hero Spot Wash 140's tight gobo + focused beam. The wash section of the fixture acts as a "pre-glow" that foreshadows the beam color before it ignites.

## Fixture Setup

### Hero Spot Wash 140 (Fixture 0, 23ch)
| Channel | Function | Laser Role |
|---------|----------|------------|
| 0–1 | Pan (16-bit) | Beam aim horizontal |
| 2–3 | Tilt (16-bit) | Beam aim vertical |
| 4 | PT Speed | Always 0 (max speed) |
| 5 | Spot Dimmer (**LTP**) | Beam on/off |
| 6 | Spot Strobe | Glitch strobes, audio-reactive |
| 7 | Color Wheel | Beam color |
| 8 | Static Gobo | **Gobo 1 on "Gobo 2" = tight beam** (value 16) |
| 9 | Gobo Wheel | Open (0) |
| 10 | Gobo Rotation | Stop (0) |
| 11 | Focus | **0 = tightest** (near focus = smallest beam) |
| 12 | Prism | Glitch prism effects |
| 13 | Wash Dimmer (**LTP**) | Pre-glow on/off |
| 14 | Wash Strobe | Audio-reactive wash strobe |
| 15–18 | RGBW | Wash color (matches beam) |

### Color Wheel Values (ch 7)
| Color | Value | DMX Range |
|-------|-------|-----------|
| White | 0 | 0–4 |
| Red | 18 | 14–22 |
| Orange | 36 | 32–40 |
| Green | 54 | 50–58 |
| Blue | 72 | 68–76 |
| Yellow | 90 | 86–94 |
| Light Blue | 108 | 104–112 |
| Purple | 126 | 122–130 |

## Architecture

### Layer Separation
```
LASER SYSTEM (LZ: prefix)

┌─────────────────────────────────────────────┐
│ BEAM LAYER (spot side)                       │
│  ch 5 (LTP), 6, 7, 8, 9, 10, 11, 12        │
│  Controls: on/off, color, gobo, focus, prism │
├─────────────────────────────────────────────┤
│ WASH PRE-GLOW LAYER (wash side)              │
│  ch 13 (LTP), 14, 15, 16, 17, 18            │
│  Controls: pre-glow color, strobe            │
├─────────────────────────────────────────────┤
│ POSITION LAYER (movement)                    │
│  ch 0, 1, 2, 3, 4                            │
│  Controls: aim, speed                        │
└─────────────────────────────────────────────┘
```

### Charge-Burst Sequence (the signature move — 32 beats)

The charge-burst is a 3-layer composition: **direction chaser** drives the envelope,
**color scene** sets the palette, **glitch/texture** adds chaos on top.

```
CHARGE-BURST TIMELINE (32 beats = 8 bars)
─────────────────────────────────────────────────────────────────
         GLOW PHASE (12 beats)
Beat 1      Ready position (head moves dark, instant)
Beat 1–4    ░░▒▒▓▓  Wash charges 0→70% over 4 beats
Beat 5–8    ▓▓▒▒░░  Wash fades 70%→0 (2 beat fade + 2 beat dark)
Beat 9–12   ░▒▓███  Wash charges 0→100% (3 beat fade + 1 beat hold)
            ↓
         LASER ACTION — eased sweep (18 beats)
Beat 13     ██      BEAM FIRES — spot on, wash off, starts moving
Beat 13–17  ·····▸  Ease-in: slow start (15° over 5 beats)just
Beat 31–32  ▪▪  All off, 2 beats darkness
─────────────────────────────────────────────────────────────────

Easing is simulated by splitting the sweep into 3 linear segments:
small distance + many beats = slow, large distance + few beats = fast.
```

**Audio reactivity during charge:** The wash dimmer (ch 13) is driven by an OSC
audio slider. The chaser controls RGBW (envelope ceiling), the audio slider
controls wash dimmer (modulation). Result: `RGBW × (wash_dim/255)` — organic
pulsing within the charge shape.

### How to use
1. Pick a **COLOR** (solo frame — one at a time) → sets RGBW + color wheel
2. Pick a **DIRECTION** (solo frame — one at a time) → fires the 32-beat chaser
3. Optionally layer **GLITCH** (flash buttons) → prism/strobe chaos on top
4. **AUDIO** sliders modulate in real time during the whole sequence

## Scenes Created

### Config & Envelope Scenes
| Scene | ID | Purpose |
|-------|----|---------|
| LZ: Beam Config | 27 | Gobo 1, focus tight, strobes off, prism off |
| LZ: Ready Top | 28 | Position top, all dark |
| LZ: Ready Left | 29 | Position left, all dark |
| LZ: Ready Bottom | 43 | Position bottom, all dark |
| LZ: Glow Mid | 30 | Wash dimmer 180 (70%), spot off |
| LZ: Glow Off | 31 | Wash dimmer 0, spot off |
| LZ: Glow Full | 32 | Wash dimmer 255 (100%), spot off |

### Burst Scenes (spot on, wash off, position)
| Scene | ID | Position |
|-------|----|----------|
| LZ: Burst Top | 33 | Pan 180°, Tilt 100° |
| LZ: Burst Bottom | 34 | Pan 180°, Tilt 180° |
| LZ: Burst Left | 35 | Pan 160°, Tilt 130° |
| LZ: Burst Right | 36 | Pan 200°, Tilt 130° |
| LZ: Burst Center | 44 | Pan 180°, Tilt 130° |
| LZ: Burst Near Top | 65 | Pan 180°, Tilt 115° (ease waypoint) |
| LZ: Burst Near Bottom | 66 | Pan 180°, Tilt 165° (ease waypoint) |
| LZ: Burst Near Left | 67 | Pan 170°, Tilt 130° (ease waypoint) |
| LZ: Burst Near Right | 68 | Pan 190°, Tilt 130° (ease waypoint) |

### Color Scenes (sets RGBW + color wheel together)
| Scene | ID | Wash RGBW | Color Wheel |
|-------|----|-----------|-------------|
| LZ: Color Red | 37 | R:255 | 18 |
| LZ: Color Green | 38 | G:255 | 54 |
| LZ: Color Blue | 39 | B:255 | 72 |
| LZ: Color White | 40 | W:255 | 0 |
| LZ: Color Purple | 41 | R:200 B:255 | 126 |
| LZ: Color Orange | 42 | R:255 G:80 | 36 |

### Strobe & Glitch Scenes (texture layer)
| Scene | ID | Effect |
|-------|----|--------|
| LZ: Glitch Prism Strobe | 48 | Static prism + medium strobe |
| LZ: Glitch Prism Spin | 49 | Spinning prism + fast strobe |
| LZ: Glitch Color Spin | 50 | Color wheel spin + fast strobe |
| LZ: Strobe Slow | 51 | Spot strobe ~80 |
| LZ: Strobe Fast | 52 | Spot strobe ~180 |
| LZ: Strobe Max | 53 | Spot strobe 250 |

## Chasers Created

### Charge-Burst Chasers (SingleShot, 32 beats, beat-based)
| Chaser | ID | Direction |
|--------|----|-----------|
| LZ: Charge TopBot | 45 | Ready top → charge → burst sweeps to bottom |
| LZ: Charge LeftRight | 46 | Ready left → charge → burst sweeps to right |
| LZ: Charge BotTop | 47 | Ready bottom → charge → burst sweeps to top |

#### Step detail (all three share same timing)
| Step | Scene | FadeIn | Hold | Subtotal | What |
|------|-------|--------|------|----------|------|
| 1 | Ready pos | 0 | 0 | 0 | Position in dark |
| 2 | Glow Mid | 4 | 0 | 4 | Charge to 70% |
| 3 | Glow Off | 2 | 2 | 4 | Fade back + pause |
| 4 | Glow Full | 3 | 1 | 4 | Second charge 100% |
| | | | **Glow** | **12** | |
| 5 | Burst start | 0 | 0 | 0 | BEAM fires instantly |
| 6 | Burst near-start | 5 | 0 | 5 | Ease-in: 15° slow |
| 7 | Burst near-end | 8 | 0 | 8 | Fast middle: 50° |
| 8 | Burst end | 5 | 0 | 5 | Ease-out: 15° slow |
| | | | **Laser** | **18** | |
| 9 | Glow Off | 0 | 2 | 2 | Reset darkness |
| | | | **Total** | **32** | |

### Loop Chasers (beat-based)
| Chaser | ID | Pattern |
|--------|----|---------|
| LZ: Glitch Chaos | 54 | Rotating prism/color/strobe hits (6 beats/loop) |

## Collections Created

| Collection | ID | Components |
|------------|----|------------|
| LZ: Red Charge TopBot | 55 | Beam Config + Color Red + Charge TopBot |
| LZ: Blue Charge TopBot | 56 | Beam Config + Color Blue + Charge TopBot |
| LZ: Green Charge TopBot | 57 | Beam Config + Color Green + Charge TopBot |
| LZ: White Charge TopBot | 58 | Beam Config + Color White + Charge TopBot |
| LZ: Purple Charge TopBot | 59 | Beam Config + Color Purple + Charge TopBot |
| LZ: Orange Charge TopBot | 60 | Beam Config + Color Orange + Charge TopBot |
| LZ: Red Charge LR | 61 | Beam Config + Color Red + Charge LeftRight |
| LZ: Blue Charge LR | 62 | Beam Config + Color Blue + Charge LeftRight |
| LZ: Red Charge BotTop | 63 | Beam Config + Color Red + Charge BotTop |
| LZ: Blue Charge BotTop | 64 | Beam Config + Color Blue + Charge BotTop |

## Virtual Console Layout

### LASER controls (inside LEVELS frame, id:38)
```
┌─ LZ: DIRECTION (Solo Frame 19) ──────────────────────────────┐
│ ┌──────────┬──────────┬──────────┐                            │
│ │ TOP→BOT  │ LEFT→RGT │ BOT→TOP  │  (toggle — one at a time) │
│ └──────────┴──────────┴──────────┘                            │
├─ LZ: COLOR (Solo Frame 20) ──────────────────────────────────┤
│ ┌─────┬─────┬─────┬─────┬─────┬─────┐                       │
│ │ RED │GREEN│BLUE │WHITE│PURPL│ORNGE│  (toggle — one at time) │
│ └─────┴─────┴─────┴─────┴─────┴─────┘                       │
├─ LZ: GLITCH (Frame 76) ─────────────────────────────────────┤
│ ┌──────────┬──────────┬──────────┬──────────┬──────────┐     │
│ │PRISM+STR │PRISM SPIN│CLR SPIN  │ CHAOS    │ STROBE   │     │
│ │ (flash)  │ (flash)  │ (flash)  │ (toggle) │ (flash)  │     │
│ └──────────┴──────────┴──────────┴──────────┴──────────┘     │
├─ LZ: AUDIO (Frame 77) ──────────────────────────────────────┤
│ ┌───┬───┬───┬───┬───┬───┬───┐                               │
│ │SPT│WSH│PRM│FOC│WSH│SPT│LZ │  ← Connect OSC for audio     │
│ │STR│STR│   │   │DIM│DIM│SUB│    reactivity                 │
│ │   │   │   │   │   │   │   │                               │
│ └───┴───┴───┴───┴───┴───┴───┘                               │
└──────────────────────────────────────────────────────────────┘
```

### Slider Purposes (connect OSC for audio reactivity)
| Slider | Channel | OSC Usage |
|--------|---------|-----------|
| SPOT STROBE | ch 6 | Map to bass/sub-bass for beat-synced strobe |
| WASH STROBE | ch 14 | Map to high freq for glitchy wash flicker |
| PRISM | ch 12 | Map to mid-range for texture modulation |
| FOCUS | ch 11 | Manual tweak (or map to slow envelope) |
| WASH DIM | ch 13 | Audio-reactive modulation within charge envelope |
| SPOT DIM | ch 5 | Master beam intensity |
| LZ SUB | submaster | Scales all laser frame output |

## Configuration Notes

### LTP Channels (configured)
- **ch 5** (Spot Dimmer) — LTP so blackout scenes win over HTP
- **ch 13** (Wash Dimmer) — LTP so wash on/off is deterministic

### Beat Timing Reference
At 120 BPM: 1 beat = 500ms
At 130 BPM: 1 beat = 461ms
At 140 BPM: 1 beat = 429ms

---

## Future Ideas
_Add new ideas below this line. Keep the LZ: naming prefix for consistency._


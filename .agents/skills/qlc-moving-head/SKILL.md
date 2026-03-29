---
name: qlc-moving-head
description: >
  Program moving head fixtures in QLC+ — covers 16-bit pan/tilt DMX addressing,
  degree-to-DMX conversion, and phantom sweep chaser patterns.
  Channel layouts shown are for the Hero Spot Wash 140; use query_fixture_channels
  to discover channels for other fixtures.
  USE FOR: pan/tilt positioning, moving head scenes, phantom sweep, chaser with
  blackout reset, beat-synced chasers, Hero Spot Wash fixture programming.
  DO NOT USE FOR: wash-only fixtures, LED strip effects, ISF shaders.
metadata:
  author: André Bossard
  version: "1.0"
---

# QLC+ Moving Head Programming

## 16-Bit Pan/Tilt Addressing

Moving heads use two DMX channels per axis for 16-bit precision:

- **Coarse channel** (MSB) = high byte, controls broad positioning
- **Fine channel** (LSB) = low byte, controls micro-adjustment

### Conversion formulas

**Degrees → DMX (coarse + fine):**

```
dmx_16bit = degrees / max_degrees × 65535
coarse = dmx_16bit ÷ 256  (integer part)
fine   = dmx_16bit mod 256
```

**DMX → Degrees:**

```
dmx_16bit = coarse × 256 + fine
degrees = dmx_16bit / 65535 × max_degrees
```

### Hero Spot Wash 140 specifics

| Axis | Max degrees | Coarse ch | Fine ch |
|------|------------|-----------|---------|
| Pan  | 540°       | 0         | 1       |
| Tilt | ~190°      | 2         | 3       |

**Base position (180°/180° = straight into room):**
- Pan: coarse **85**, fine **85** (16-bit: 21845)
- Tilt: coarse **242**, fine **133** (16-bit: 62085)

### Common pan positions around 180° center

| Degrees | Coarse | Fine  | Notes |
|---------|--------|-------|-------|
| 160°    | 75     | 202   | 20° left of center |
| 170°    | 80     | 144   | 10° left |
| 180°    | 85     | 85    | Center |
| 190°    | 90     | 27    | 10° right |
| 200°    | 94     | 208   | 20° right of center |

### Channel 4: Pan/Tilt Speed

- **0** = maximum motor speed (fastest snap)
- **255** = slowest motor speed
- For phantom effects, always use **0** (max speed) so the head returns as fast as possible during blackout.

## Phantom Sweep Pattern

A phantom sweep creates the illusion of one-directional beam movement by blacking out during the return trip.

### How it works

```
[LEFT ON] ──3-beat fade──▶ [RIGHT ON] ──instant──▶ [BLACKOUT + snap back] ──▶ loop
   beam visible, sweeping right         beam off, motor returns to left
```

### Required scenes (3)

1. **Phantom Left On** — beam at left position, spot dimmer 255
2. **Phantom Right On** — beam at right position, spot dimmer 255
3. **Phantom Blackout Reset** — beam at left position, spot dimmer 0

All scenes must include:
- Both coarse AND fine channels for pan and tilt
- `pt_speed = 0` (max motor speed)
- `wash_dim = 0` (spot only)
- Consistent tilt across all steps

Scenes are created with explicit `channelValues` — each entry is `{fixtureID, channel, value}`. Use `query_fixture_channels` to discover channel indices for your fixture.

### Chaser configuration

| Step | Scene | FadeIn | Hold | Purpose |
|------|-------|--------|------|---------|
| 1 | Left On | 0 | 0 | Instant beam appears at left |
| 2 | Right On | 3 beats | 0 | Visible sweep left→right |
| 3 | Blackout Reset | 0 | 1 beat | Dark while motor snaps back |

- **Run order:** loop
- **Tempo type:** beats (syncs to BPM)
- Total loop: 4 beats

### Key design decisions

1. **Narrow the sweep range** — ±20° (not ±40°) reduces motor travel distance, enabling shorter blackout holds.

2. **Spot dimmer must be LTP** — by default, QLC+ treats dimmer channels as HTP (Highest Takes Precedence). The blackout scene's dim=0 will be overridden by dim=255 from adjacent steps. Change `spot_dim` (ch 5) precedence to **LTP** via `configure_channels`.

3. **No dimmer fades on return** — ramping the dimmer up during the snap-back looks broken. Use instant on/off only.

4. **Beat sync vs time** — beat mode automatically scales the sweep speed with BPM. At 120 BPM: 3 beats = 1.5s sweep, 1 beat = 500ms blackout. At 170 BPM: 3 beats = 1.06s sweep, 1 beat = 353ms blackout (tight but workable with ±20° range at max motor speed).

### Common tilt positions

| Degrees | Coarse | Fine  | Notes |
|---------|--------|-------|-------|
| 100°    | 134    | 188   | Far up |
| 130°    | 175    | 38    | Mid up |
| 170°    | 228    | 236   | Near horizontal |
| 180°    | 242    | 133   | Straight (base) |
| 190°    | 255    | 255   | Max tilt |

## Layer Architecture

Split channels into two independent layers so movement and look can be swapped independently.

### Movement Layer (MV:)
Owns: pan (0,1), tilt (2,3), pt_speed (4), **spot_dim (5)**

Controls position and on/off. The dimmer lives here (not in the look layer) so the phantom chaser can black out the beam without HTP conflicts.

### Look Layer (LK:)
Owns: color_wheel (7), gobo (8), gobo_wheel (9), gobo_rot (10), focus (11), prism (12)

Controls beam appearance only. No pan/tilt, no dimmer.

### Why dimmer belongs to movement, not look
- Dimmer must be **LTP** (set via `configure_channels`) so the chaser's dim=0 actually wins
- If both layers set dimmer, they fight — keep ownership exclusive
- Strobe channel for blackout is unreliable (fixture-specific values, not always a clean close)

### Usage pattern: Collections
Combine one MV chaser + one LK scene in a QLC+ Collection. This lets you:
- Swap looks without stopping movement
- Swap movement patterns without changing the look
- Pre-build every combo (movement × color) as a one-click trigger

## Tilt Phantom Sweep

Same phantom principle applied to the tilt axis — beam sweeps vertically then snaps back in blackout.

### Tested beat ratios

| Name | Sweep | Dark | Total | Notes |
|------|-------|------|-------|-------|
| Fast | 6 beats | 2 beats | 8 | Energetic, needs short tilt range |
| Mid | 14 beats | 2 beats | 16 | Smooth, fits 4-bar phrases |
| Slow | 28 beats | 4 beats | 32 | Glacial, dramatic builds |

### Recommended tilt range
- **170° → 100°** (70° travel) works well for dramatic vertical sweeps
- Shorter ranges (e.g. 180° → 130°) need less blackout time but less visual impact
- At max motor speed (pt_speed=0), 2 beats at 120 BPM (1s) is enough for 70° return

### Variations

- **Reverse phantom:** swap start/end scenes — beam appears to move in opposite direction
- **Pan phantom:** same pattern on pan axis (±20° around 180° center, 3/1 beat ratio)
- **Diagonal:** vary both pan and tilt across steps
- **Multiple speeds:** create Fast/Mid/Slow chasers sharing the same position scenes, only differing in beat ratios

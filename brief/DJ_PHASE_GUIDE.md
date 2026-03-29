# DJ Set Lighting Phase Guide

Creative ruleset for a 4-phase DJ show design. This guide is intentionally platform-agnostic: it defines artistic direction, structure, and constraints rather than tool operations.

---

## Core Intent

- Lighting should feel musical, not random.
- Each phase must have a clear visual identity.
- Energy changes should read within 5-10 seconds, even to someone not facing the booth.
- Color and motion should support transitions, not fight them.

---

## Non-Negotiable Rules

1. **Palette discipline**
   - Keep at least 80% of scene runtime inside the active phase palette.
   - Use at most one accent color outside the phase palette.
2. **Contrast rhythm**
   - Every scene needs both a "rest state" and a "hit state" (brightness, density, or mask difference).
   - Avoid full-intensity continuity longer than 45 seconds.
3. **Audio-reactivity minimum**
   - Every scene must include at least one audio-reactive component.
4. **Strobe restraint**
   - Strobes are accents, not baseline texture.
   - Avoid sustained high-frequency strobe blocks longer than 8 seconds.
5. **Scene naming clarity**
   - Scene names must be unique and phase-scoped (`P1-...`, `P2-...`, etc.).
   - Do not repeat the same scene name in one playlist.
6. **Transition ownership**
   - Entry and exit scenes per phase should be softer than the phase peak scenes.

---

## Blender Composition Rules (Critical)

Blender scenes should use three roles:
- **Background layer:** space, atmosphere, tonal bed.
- **Foreground layer:** the primary musical motion.
- **Mask layer:** rhythmic gating, punctuation, reveal/hide control.

### Audio-Reactivity Requirement

Each blender scene must have **1-2 audio-reactive layers**.

Allowed:
- 1 reactive: foreground reactive, background slow/static, mask static/off.
- 2 reactive: mask reactive plus one of foreground/background reactive.

Not allowed:
- 0 reactive layers (looks dead).
- 3 reactive layers (usually chaotic and unreadable).

### Additional Blender Constraints

- Keep background brightness conservative (typically `0.10-0.35`) so foreground details remain readable.
- Use mask as structure, not constant noise.
- Do not run two strobe-family behaviors at once (for example, strobe-like foreground plus strobe mask).
- In high-energy phases, prefer reactive mask + one melodic/reactive foreground.

### Blender Archetypes (Recommended)

Use these as reusable "recipes" across all phases:

| Archetype | Background | Foreground | Mask | Feel |
|---|---|---|---|---|
| Wobble Bed | gradient/singleColor (chill) | `wavelength` or `energy` (wobble) | `singleColor` low/open | Musical sway, readable groove |
| Flow Mist | `singleColor`/gradient low brightness | `energy2` or `wavelength` (flow) | gradient (soft structure) | Chill movement with shape |
| Hard Cut Reactor | dark singleColor or contrast gradient | `blade_power_plus`/`power` (hard) | reactive `energy` or short strobe | Aggressive impact windows |
| Bullet Tunnel | directional gradient | `scroll`/`scan` (bullet profile) | reactive mask (`energy` or strobe accent) | Rapid "lightning bullet" trajectories |

---

## Phase Overview

| Phase | Name | Energy | Mood | Color Direction |
|---|---|---|---|---|
| P1 | Jungle/Disco Starter | Low-Medium | Warm, welcoming, rhythmic | Green + yellow with subtle blue accents |
| P2 | Buildup | Medium-High | Tension, lift, anticipation | Blue/cyan with purple support |
| P3 | Peak | Maximum | Intense, aggressive, high contrast | Purple/magenta/red with black contrast |
| P4 | Release | Medium | Relief, glide, reset | Blue/lavender/aqua, softer transitions |

---

## Phase Color Anchors

### P1 Jungle/Disco Starter
- Background anchor: `#001a00`
- Palette anchors: `#228b22`, `#00aa00`, `#ffff00`, `#0096c8`
- Target brightness: `0.60-0.75`

### P2 Buildup
- Background anchor: `#000a22`
- Palette anchors: `#0044aa`, `#00ffff`, `#9900ff`
- Target brightness: `0.75-0.90`

### P3 Peak
- Background anchor: `#000000`
- Palette anchors: `#9900ff`, `#ff00aa`, `#ff0000`
- Target brightness: `0.90-1.00` with intentional blackout pockets

### P4 Release
- Background anchor: `#000022`
- Palette anchors: `#3366cc`, `#cc99ff`, `#00ccff`
- Target brightness: `0.65-0.82`

---

## Phase-Specific Creative Rules

### P1 Starter
- Motion: smooth and legible, moderate tempo, obvious groove.
- Prioritize rhythmic readability over intensity.
- Never use full black as the base look in this phase.
- Good families: `wavelength`, `energy`, `scroll`, `gradient`, atmospheric motion.
- Avoid aggressive strobe behavior except short punctuation.

### P2 Buildup
- Motion: tighter, sharper, more directional.
- Introduce stronger beat articulation and contrast.
- Good families: `blade_power_plus`, `bands`, `scan`, `pitchSpectrum`, `energy`.
- Strobes should signal tension, not dominate runtime.

### P3 Peak
- Motion: fast, high contrast, impact-forward.
- Use short black gaps to make hits feel bigger.
- Good families: `power`, `blade_power_plus`, `real_strobe`, aggressive reactive masks.
- Keep strobe sections short and intentional; alternate with non-strobe impact scenes.

### P4 Release
- Motion: de-escalate without going flat.
- Reintroduce flow and melody emphasis.
- Good families: `energy2`, `plasma2d`, `wavelength`, gentle `scroll`.
- If using strobes, keep them sparse and short.

---

## Rapid Flow ("Lightning Bullet") Rules

- Bullet scenes should feel directional and transient, not constant.
- Preferred carriers: `scroll`, `scan`, fast `wavelength` variants.
- Layering recommendation in blender:
  - Foreground: bullet carrier.
  - Background: low-contrast gradient (keeps depth).
  - Mask: reactive gate (`energy`) or brief strobe accent.
- Typical bullet scene duration: `9-12s`.
- Avoid chaining more than two bullet scenes back-to-back in one phase playlist.

---

## Playlist Architecture Rules

- Build each phase playlist as a mixed arc (not single-effect runs):
  - At least **3 different effect families** per phase playlist.
  - At least **2 blender scenes** in each phase playlist.
  - At least **1 bullet-flow scene** in each phase playlist.
  - No more than **2 strobe-accent scenes** per phase playlist.
- Typical phase playlist length: `8-12 scenes` (mixed direct + blender).
- Typical dwell ranges:
  - Standard scene: `12-22s`
  - Bullet scene: `9-12s`
  - Strobe accent: `6-8s`
- Always include:
  - 1 entry scene (lower complexity).
  - 1 high-contrast hard/peak scene.
  - 1 exit scene (prepares next phase).

### Suggested Scene Flow Pattern

- `Entry -> Wobble/Flow -> Build -> Bullet -> Hard Peak -> Accent -> Exit`

This pattern should hold in all phases, with P3 biasing toward harder peak segments and P4 biasing toward flow/chill.

---

## Effect Role Matrix

| Role | Typical Effect Families | Notes |
|---|---|---|
| Tonal bed (background) | `singleColor`, `gradient`, slow atmospheric | Keep low brightness and low clutter |
| Musical body (foreground) | `wavelength`, `energy`, `blade_power_plus`, `power` | Main reader of rhythm/melody |
| Accent gate (mask) | beat-reactive bars, selective strobe, rhythmic textural masks | Short bursts, clear rhythmic function |

---

## Live Operation Cues

- Move from P1 to P2 when crowd is locked and movement is consistent.
- Move into P3 only when musical arrangement and room energy can sustain it.
- Do not hold P3 crazy continuously; rotate in and out for impact.
- Use P4 as an intentional breath before the next buildup cycle.

---

## Quality Checklist Before Showtime

- Phase palettes are visually distinct at a glance.
- Scene names are unique and phase-prefixed.
- Every scene has at least one audio-reactive component.
- Every blender scene has exactly 1-2 reactive layers.
- No playlist contains repeated scene IDs or repeated scene names.
- Strobe-heavy scenes are distributed, not clustered end-to-end.
- Entry and exit scenes exist for each phase variant.
- Every phase playlist includes at least one bullet-flow scene.
- Every phase playlist includes both direct and blender scenes.
- No phase playlist relies on only one effect family.

---

---

## Fixture Inventory

### LedFX — WLED LED Strips (4x 5m RGB)

| Strip | Controller | Role | Placement |
|---|---|---|---|
| WLED Strip 1 | WLED | Ambient / background wash | Back wall or ceiling edge |
| WLED Strip 2 | WLED | Ambient / background wash | Opposite wall or DJ booth surround |
| WLED Strip 3 | WLED | Reactive accent | Floor edge or audience-facing |
| WLED Strip 4 | WLED | Reactive accent | Floor edge or audience-facing |

- Controlled via LedFX (audio-reactive effects, gradients, chases).
- All strips share the same LedFX instance; assign effects per virtual.
- These carry the **background and foreground layers** in the blender model.

### QLC+ — DMX Fixtures

| Fixture | ID | Type | Channels | Key Capabilities | Role |
|---|---|---|---|---|---|
| Varytec Hero Spot Wash 140 2in1 RGBW+W | 0 | Moving Head (Spot + Wash) | 23 | Pan/Tilt, RGBW, Gobo (static + rotating), Prism, Color wheel, Strobe, Focus | Beam accent, gobo projection, movement |
| Cameo Thunderwash 600 UV | 1 | UV Strobe/Wash | 4 | Dimmer, Strobe, Duration, Sound mode | UV wash, strobe accent, impact hits |
| Stairville Hz-200 DMX | 2 | Hazer | 2 | Haze output, Fan speed | Atmosphere (always-on low during show) |

---

## Layering Principle — Two-System Architecture

The show runs on **two parallel systems** that together form the blender composition:

```
┌─────────────────────────────────────────────────────┐
│                   BLENDER MODEL                      │
│                                                      │
│  Background ──► LedFX strips (ambient wash/gradient) │
│  Foreground ──► LedFX strips (audio-reactive effects)│
│  Beam/Gobo  ──► Hero Spot Wash (movement, texture)   │
│  Mask/Hit   ──► Thunderwash UV (strobe, UV punch)    │
│  Atmosphere ──► Hz-200 Hazer (always-on haze bed)    │
└─────────────────────────────────────────────────────┘
```

### Layer Assignments

| Layer | System | Fixtures | Controls |
|---|---|---|---|
| **Background wash** | LedFX | Strips 1 + 2 | Default black. Only use color/gradient when the scene already has multiple bright colors elsewhere (e.g. Hero Spot wash + reactive strips both active). |
| **Foreground reactive** | LedFX | Strips 3 + 4 | Audio-reactive effects (energy, wavelength, scroll) — the musical body |
| **Beam / texture** | QLC+ | Hero Spot Wash (ID 0) | Pan/tilt movement, gobo projection, prism, color wheel — directional accents |
| **Impact / mask** | QLC+ | Thunderwash UV (ID 1) | Short UV/strobe bursts timed to drops and transitions — the punctuation layer |
| **Atmosphere** | QLC+ | Hz-200 Hazer (ID 2) | Low continuous haze to catch beams; increase slightly before P3 peak |

### Layer Interaction Rules

1. **LedFX background strips default to black.** Strips 1+2 stay off unless the scene already has multiple bright color sources (reactive strips + Hero Spot both active and colorful). When they do come on, keep them inside the phase palette.
2. **LedFX reactive strips own color temperature.** Strips 3+4 define the dominant palette for each phase. QLC+ fixtures accent within that palette, not against it.
2. **Hero Spot Wash adds depth, not competing color.** Use it for:
   - Gobo textures on walls/ceiling (P1: organic patterns, P3: sharp geometric).
   - Slow sweeping pan/tilt during P1/P4; fast snaps during P2/P3.
   - Wash mode RGBW should complement, not duplicate, the strip colors.
3. **Thunderwash is a weapon, not wallpaper.** Fire it for:
   - Drop hits (P2→P3 transition, in-P3 peaks).
   - UV wash during P1 chill sections (low dimmer, no strobe) for a glow effect on white clothing.
   - Never run continuous strobe longer than 8 seconds (from Non-Negotiable Rule 4).
4. **Hazer runs constantly** at low output (20-40%) to make beams visible. Bump to 50-60% heading into P3 for thicker atmosphere.
5. **Separation of concerns:**
   - LedFX handles audio-reactivity for color/pattern — it's always listening.
   - QLC+ handles position, gobo, and timed accent hits — it's cue-driven or manually triggered.
   - Do not try to make QLC+ scenes audio-reactive for color; let LedFX do that job.

### Phase-Specific Fixture Usage

#### P1 — Jungle/Disco Starter
- **Strips 1-2:** Black (off). Let the reactive strips and Hero Spot carry the look.
- **Strips 3-4:** Gentle `wavelength` or `energy` effect, green/yellow.
- **Hero Spot:** Wash mode, warm white + green tint, slow pan sweep. Organic gobo at low intensity.
- **Thunderwash:** UV only at 15-25% dimmer (glow accent), no strobe.
- **Hazer:** 25% output.

#### P2 — Buildup
- **Strips 1-2:** Black (off). Only bring up color if reactive strips + Hero Spot are both bright.
- **Strips 3-4:** Tighter reactive effects (`blade_power_plus`, `scan`), blue/purple.
- **Hero Spot:** Spot mode, geometric gobo with rotation, medium-speed pan/tilt. Prism on for wider beam spread.
- **Thunderwash:** Short UV flashes on downbeats, building frequency toward P3.
- **Hazer:** 35% output.

#### P3 — Peak
- **Strips 1-2:** Black (off). Exception: brief color flash synced to massive drops when everything else is already bright.
- **Strips 3-4:** Aggressive reactive (`power`, `real_strobe` equivalent), magenta/red/white.
- **Hero Spot:** Fast snap positions, tight beam + gobo + prism. Spot strobe channel active for beam flicker. Color wheel for hard color changes.
- **Thunderwash:** Full strobe bursts on drops (6-8s max), UV wash between bursts.
- **Hazer:** 50-60% output for maximum beam visibility.

#### P4 — Release
- **Strips 1-2:** Black (off). Can bring up a very soft gradient if the mood is especially floaty and other layers are active.
- **Strips 3-4:** Flowing effects (`energy2`, `plasma2d`), aqua/lavender.
- **Hero Spot:** Return to wash mode, slow sweep, cool white + blue. Remove gobo or use soft organic pattern.
- **Thunderwash:** Off or very low UV glow only.
- **Hazer:** Back to 30%.

---

*Creative specification for DJ lighting phases.*

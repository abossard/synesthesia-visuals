# Magic Music Visuals: A Guide for Software Engineers

A comprehensive technical guide to Magic Music Visuals for developers and engineers. This guide covers modular architecture, audio reactivity, ISF shaders, reusable pipelines, and advanced control patterns.

## Table of Contents

1. [Overview](#overview)
2. [Core Architecture](#core-architecture)
3. [Global Parameters](#global-parameters)
4. [Audio Reactivity](#audio-reactivity)
5. [Reference Setup: Complete Global and Modifier Configuration](#reference-setup-complete-global-and-modifier-configuration)
6. [ISF Shader Integration](#isf-shader-integration)
7. [Effect Chains: Wobble, Glitch, Sparkle](#effect-chains-wobble-glitch-sparkle)
8. [Reusable Scenes and Pipelines](#reusable-scenes-and-pipelines)
9. [Post-Processing Scene Pattern](#post-processing-scene-pattern)
10. [Song Stage Control](#song-stage-control)
11. [MIDI Control Patterns](#midi-control-patterns)
12. [Processing + Syphon Integration](#processing--syphon-integration)
13. [Templates and Best Practices](#templates-and-best-practices)
14. [Resources](#resources)

---

## Overview

**Magic Music Visuals** is a modular visual synthesis environment designed for live VJ performance. For software engineers, think of it as a visual dataflow programming environment where:

- **Modules** = functions/nodes that process or generate visuals
- **Connections** = data pipes between modules (like Unix pipes)
- **Scenes** = reusable compositions (like functions you can call)
- **Global Parameters** = shared state accessible across all scenes
- **Expressions** = inline code for dynamic parameter values

### Key Concepts

| Magic Concept | Programming Analogy |
|---------------|---------------------|
| Module | Function/Node |
| Connection | Pipe / Data Flow |
| Scene | Reusable Component / Function |
| Global Parameter | Global Variable / Environment Variable |
| Expression | Inline Lambda / Computed Property |
| Playlist | State Machine / Scene Manager |
| Post-Processing Scene | Middleware / Decorator Pattern |

### Editions

| Edition | Key Features |
|---------|--------------|
| **Magic** (Free) | Core functionality, limited sources |
| **Performer** | Syphon/NDI input, more modules |
| **Pro** | FFGL plugins, Spout, advanced routing |

For VJ work with Processing integration, **Performer** edition is recommended (Syphon input support). The free Magic edition works well for learning and basic setups, but lacks Syphon input which is essential for receiving frames from Processing.

---

## Core Architecture

### Module Graph

Magic's architecture is a directed acyclic graph (DAG) of modules:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Source    │───▶│   Effect    │───▶│   Output    │
│  (Image,    │    │  (Blur,     │    │  (Magic,    │
│   Video,    │    │   Color,    │    │   Syphon,   │
│   Syphon)   │    │   ISF)      │    │   File)     │
└─────────────┘    └─────────────┘    └─────────────┘
```

### Module Categories

| Category | Purpose | Examples |
|----------|---------|----------|
| **Sources** | Generate/input visuals | Image, Video, Syphon, Webcam, Text |
| **Generators** | Procedural patterns | Bars, Noise, Plasma, Clock |
| **Effects** | Transform visuals | Blur, Color, Transform, Feedback |
| **ISF** | Shader effects | Any ISF-format shader |
| **Mix** | Combine layers | Mix, Composite, Add, Multiply |
| **Utilities** | Control flow | Router, Selector, Time |
| **Output** | Final destination | Magic (main output), Syphon Server |

### Connection Types

- **Visual (RGBA)**: Image data between modules
- **Audio**: Audio signal routing
- **Control**: Parameter modulation signals

---

## Global Parameters

Global parameters are shared variables accessible from any module in any scene. They're the key to consistent behavior across your entire project.

### Creating Global Parameters

1. Open **Global Parameters** panel (View → Global Parameters)
2. Click **+** to add a new parameter
3. Configure:
   - **Name**: Identifier (e.g., `BassGlobal`, `intensity`)
   - **Type**: Float, Integer, Boolean, Color
   - **Default**: Starting value
   - **Range**: Min/Max bounds

### Essential VJ Globals

Set up these globals for consistent audio-reactive control:

| Name | Type | Range | Purpose |
|------|------|-------|---------|
| `BassGlobal` | Float | 0.0–1.0 | Bass frequency energy (kicks, subs) |
| `MidsGlobal` | Float | 0.0–1.0 | Mid frequency energy (vocals, guitars) |
| `HighGlobal` | Float | 0.0–1.0 | High frequency energy (hats, cymbals) |
| `intensity` | Float | 0.0–1.0 | Master effect intensity |
| `energy` | Float | 0.0–2.0 | Overall energy (can exceed 1.0 for peaks) |
| `buildLevel` | Float | 0.0–1.0 | Buildup progress toward drop |
| `dropActive` | Float | 0.0–1.0 | Drop state (1.0 = in drop) |
| `bpm` | Float | 60–200 | Tempo for synced effects |
| `chaos` | Float | 0.0–1.0 | Randomness/glitch amount |
| `palette` | Integer | 0–7 | Color scheme selector |

### Linking Audio to Globals

To make globals audio-reactive:

1. Add an **Audio** source module
2. Add a **Range** modifier module
3. Connect Audio → Range → Global Parameter
4. Configure Range:
   - **Input Range**: 0.0–1.0 (audio normalized)
   - **Output Range**: Your desired effect range
5. Add **Smooth** modifier to reduce jitter

```
Audio Source (Band: Low) → Range (0-1 → 0-0.8) → Smooth (0.3) → BassGlobal
Audio Source (Band: Mid) → Range (0-1 → 0-0.6) → Smooth (0.4) → MidsGlobal  
Audio Source (Band: High) → Range (0-1 → 0-0.5) → Smooth (0.2) → HighGlobal
```

### Referencing Globals in Expressions

Use square brackets to reference globals in any parameter field:

```
// Direct reference
[intensity]

// Math operations
[BassGlobal] * 0.5

// Conditional (ternary-style with min/max)
max(0, [dropActive] - 0.5) * 2

// Combining globals
([BassGlobal] + [MidsGlobal] * 0.5) * [intensity]

// Time-based with global modulation
sin([time] * [bpm] / 60 * 6.28) * [intensity]
```

### Expression Syntax Reference

| Operator/Function | Example | Description |
|-------------------|---------|-------------|
| `+`, `-`, `*`, `/` | `[a] * 2.0` | Arithmetic |
| `sin()`, `cos()` | `sin([time])` | Trigonometry |
| `abs()` | `abs([x] - 0.5)` | Absolute value |
| `min()`, `max()` | `max(0, [x])` | Clamping |
| `pow()` | `pow([x], 2)` | Power/Easing |
| `sqrt()` | `sqrt([x])` | Square root |
| `fmod()` | `fmod([time], 1)` | Modulo |
| `clamp()` | `clamp([x], 0, 1)` | Range limit |
| `lerp()` | `lerp([a], [b], [t])` | Linear interpolation |
| `step()` | `step(0.5, [x])` | Step function |
| `smoothstep()` | `smoothstep(0, 1, [x])` | Smooth step |
| `[time]` | `sin([time])` | Seconds since start |
| `[frame]` | `[frame] % 60` | Frame count |
| `[random]` | `[random] * [chaos]` | Random 0–1 each frame |

---

## Audio Reactivity

### Audio Module Setup

Magic's Audio module provides frequency-band analysis:

1. Add **Audio** source module
2. Configure input device (use BlackHole for system audio)
3. Set frequency band:
   - **Low**: 20–200 Hz (bass, kicks)
   - **Mid**: 200–2000 Hz (vocals, snare)
   - **High**: 2000–20000 Hz (cymbals, air)
   - **Full**: Entire spectrum

### Three-Band System

The standard approach uses three audio bands mapped to globals:

```
┌─────────────────────────────────────────────────────────────────┐
│                    AUDIO ANALYSIS CHAIN                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Audio Input (BlackHole)                                         │
│       │                                                           │
│       ├──▶ Band: Low ──▶ Range ──▶ Smooth ──▶ BassGlobal        │
│       │                                                           │
│       ├──▶ Band: Mid ──▶ Range ──▶ Smooth ──▶ MidsGlobal        │
│       │                                                           │
│       └──▶ Band: High ──▶ Range ──▶ Smooth ──▶ HighGlobal       │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Modifier Chain

For each audio band, apply modifiers to shape the response:

| Modifier | Purpose | Typical Settings |
|----------|---------|------------------|
| **Range** | Scale output | In: 0–1, Out: 0–0.8 |
| **Smooth** | Reduce jitter | 0.2–0.5 (lower = faster response) |
| **Peak** | Detect transients | Threshold: 0.6, Decay: 0.9 |
| **Threshold** | Gate low values | Threshold: 0.1 |
| **Invert** | Flip behavior | For "ducking" effects |

### Best Practices

1. **Always smooth audio signals** - Raw audio is too jittery for most effects
2. **Use Peak for transients** - Bass hits, snare hits should spike then decay
3. **Different smoothing per band**:
   - Bass: Higher smoothing (0.3–0.5) for sustained response
   - Mids: Medium smoothing (0.2–0.4)
   - Highs: Lower smoothing (0.1–0.3) for quick response
4. **Test with various music** - EDM, rock, ambient all behave differently

---

## Reference Setup: Complete Global and Modifier Configuration

This section provides a production-ready configuration of Globals and Modifiers for EDM/Techno performance in Magic. This is a complete, coherent system you can implement directly in your Magic project.

**Assumptions:**
- **Source 0** = main stereo music input (e.g., BlackHole)
- **Source 4** = MIDI controller
- You already have basic globals like `Blackout`, `Buildup`, and `Drop`

For each Global below, we list:
- **Name** – Source / Feature
- **Modifiers** (top → bottom) with concrete values and expressions

---

### 1. Core Audio Bands

These are your main building blocks for most audio-reactive parameters.

#### 1.1 Multi (Overall Sensitivity, from MIDI)

**Multi** – Source 4 / Feature CC #23

Modifiers:
1. **Step**: 0.1
2. **Offset**: 0.5

This gives roughly 0.5–1.5 in 0.1 steps. Adjust the range by changing Offset/Step values to taste.

---

#### 1.2 Bass

**Bass** – Source 0 / Feature Freq. Range 20–120 Hz

Modifiers:
1. **Smooth**: 0.15
2. **Expression**: `min(max(x * Multi * 2.0, 0), 1)`

Use for kicks, bass-reactive scale, zoom, etc.

---

#### 1.3 LowMid

**LowMid** – Source 0 / Feature Freq. Range 120–350 Hz

Modifiers:
1. **Smooth**: 0.15
2. **Expression**: `min(max(x * Multi * 2.0, 0), 1)`

Good for the body of drums and low synths.

---

#### 1.4 VoiceMid

**VoiceMid** – Source 0 / Feature Freq. Range 350–2k Hz

Modifiers:
1. **Smooth**: 0.15
2. **Expression**: `min(max(x * Multi * 2.0, 0), 1)`

Good for vocals and lead synth presence.

---

#### 1.5 Highs

**Highs** – Source 0 / Feature Freq. Range 2k–6k Hz

Modifiers:
1. **Smooth**: 0.15
2. **Expression**: `min(max(x * Multi * 2.0, 0), 1)`

Use for brightness, detail, sharper glows.

---

#### 1.6 VeryHigh

**VeryHigh** – Source 0 / Feature Freq. Range 6k–20k Hz

Modifiers:
1. **Smooth**: 0.15
2. **Peak**: 0.5
3. **Expression**: `min(max(x * Multi * 2.0, 0), 1)`

Use for hi-hat sparkle, fine flicker, outlines.

---

### 2. Drum-Oriented Globals (Kick, Hats, Beat Counter)

#### 2.1 Kick (Envelope + Pulse)

**KickRaw** – Source 0 / Feature Freq. Range 40–120 Hz

Modifiers:
1. **Smooth**: 0.05
2. **Peak**: 0.5

**KickEnv** – Source KickRaw / Feature Value

Modifiers:
1. **Smooth**: 0.35
2. **Expression**: `min(x * 2.0, 1)`

This is a soft envelope that bumps on each kick and decays between beats.

**KickPulse** – Source KickEnv / Feature Value

Modifiers:
1. **Threshold**: 0.6 (outputs ~0 or 1)
2. (Optional) **Trigger (Integer)** with Threshold: 0.5

**Usage:**
- Use `KickEnv` for continuous modulation (e.g., scale/zoom).
- Use `KickPulse` after Threshold/Trigger for one-shot triggers (flashes, step changes).

---

#### 2.2 Hats

**Hats** – Source 0 / Feature Freq. Range 6k–14k Hz

Modifiers:
1. **Smooth**: 0.08
2. **Peak**: 0.4
3. **Expression**: `min(x * Multi * 2.0, 1)`

Use for fast, small movements: line jitter, edge flicker, subtle strobe.

---

#### 2.3 Beat4 (4-Beat Counter Per Bar)

**Beat4** – Source KickPulse / Feature Value

Modifiers (in this order):
1. **Trigger (Integer)** – Threshold: 0.5
2. **Increase** – Step: 1
3. **Wrap** – 4.0

`Beat4` cycles 0 → 1 → 2 → 3 → 0… in sync with the kick.

**Typical usages in Expressions:**
- `Beat4 == 0` for "bar 1" accents
- `(Beat4 % 2)` for every second beat
- `1 + 0.2 * (Beat4 == 0)` to boost things slightly on the first beat

---

### 3. Energy Over Time (Fast and Slow)

#### 3.1 EnergyFast (Instant Intensity)

**EnergyFast** – Source 0 (any) / Feature Value

Modifiers:
1. **Expression**: `Bass*0.5 + LowMid*0.3 + Highs*0.2`
2. **Smooth**: 0.4
3. **Expression**: `min(max(x, 0), 1)`

**Notes:**
- This global doesn't use its own Source value; it just combines other Globals in the Expression.
- Use it as the main "how loud/intense is it right now" control.

---

#### 3.2 EnergySlow (Build-Up Level)

**EnergySlow** – Source EnergyFast / Feature Value

Modifiers:
1. **Average**: 4.0 (averages about last 4 seconds; 6–8 also works for slower EDM)
2. **Expression**: `min(max(x, 0), 1)`

**Use EnergySlow for:**
- Layer count, geometry complexity
- Strength of non-audio-reactive effects
- Slowly growing brightness or feedback as the track intensifies

---

### 4. Drop / Build Controls

#### 4.1 MIDI-Based Drop and Buildup

You may already have:

**Buildup** – Source 4 / Feature CC #27

(No modifiers or just a simple Smooth)

**Drop** – Source 4 / Feature Note V.#9

Modifiers:
1. **Trigger**: 0.5
2. **Wrap**: 2.0 (if you want it to toggle between 0 and 1)

This gives you:
- `Buildup` slider for manual "how much tension"
- `Drop` button to fire a drop scene / toggle mode

---

#### 4.2 HighEnergyFlag (Audio-Based "High Energy" Flag)

**HighEnergyFlag** – Source EnergySlow / Feature Value

Modifiers:
1. **Expression**: `EnergySlow > 0.8`

Since Magic treats boolean expressions as 0/1, this becomes:
- 0 when EnergySlow ≤ 0.8
- 1 when EnergySlow > 0.8

You can AND this with Drop in Expressions:
- Example: `DropActive = Drop * HighEnergyFlag`
- → Only allow heavy drop visuals when the track is actually intense.

---

### 5. Video Time Remap / Audio-Reactive Speed

#### 5.1 VidSpeed (Speed from Fast Energy)

**VidSpeed** – Source EnergyFast / Feature Value

Modifiers:
1. **Smooth**: 0.3
2. **Expression**: `0.4 + x*1.6`

**Behavior:**
- Quiet sections: x ≈ 0 → speed ≈ 0.4 (slow-mo)
- Loud/intense: x ≈ 1 → speed ≈ 2.0 (fast-forward)

**On your VideoFile module:**
- Set **Looping**: On
- Link **Speed** parameter to VidSpeed (Source: VidSpeed, Feature: Value)

---

#### 5.2 VidSpeedKick (Kick-Driven Bursts, Optional)

If you want bursts of speed on kicks:

**VidSpeedKick** – Source KickEnv / Feature Value

Modifiers:
1. **Expression**: `1 + x*1.5`

**Behavior:**
- No kick: x ≈ 0 → speed ≈ 1
- On kick: x spikes, so speed briefly jumps to ≈ 2.5 and falls back

Use either `VidSpeed` or `VidSpeedKick`, or blend:
- Expression: `mix(VidSpeed, VidSpeedKick, 0.5)`
- Or: `0.5*VidSpeed + 0.5*VidSpeedKick` (if `mix` isn't available)

---

### 6. Quick Usage Notes

- **Map Bass / LowMid / VoiceMid / Highs / VeryHigh** directly to shader parameters, mask opacity, distortions, etc.
- **Use KickEnv and KickPulse** for "big moves" and triggering things.
- **Use Hats** for fine texture jitter.
- **Use EnergyFast and EnergySlow** as your main "how crazy should the whole scene be" dials.
- **Use Beat4** for structured changes every beat or bar.
- **Use Drop + HighEnergyFlag** to switch into special "drop" scenes and heavy effects.
- **Drive VideoFile Speed** with VidSpeed / VidSpeedKick for audio-reactive time remapping.

You can copy this configuration directly into your Magic project and adjust any numeric values to taste. This provides a complete, coherent global+modifier setup for EDM/Techno in Magic.

---

## ISF Shader Integration

ISF (Interactive Shader Format) is a standardized GLSL shader format with JSON metadata. Magic supports ISF natively.

### ISF Basics

An ISF shader consists of:

```glsl
/*{
    "DESCRIPTION": "My effect description",
    "CREDIT": "Author Name",
    "CATEGORIES": ["Stylize"],
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "amount",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1.0
        }
    ]
}*/

void main() {
    vec2 uv = isf_FragNormCoord;
    vec4 color = IMG_NORM_PIXEL(inputImage, uv);
    
    // Your effect code here
    
    gl_FragColor = color;
}
```

### Installing ISF Shaders

1. Find ISF shaders:
   - [ISF.video](https://isf.video/) - Official shader library
   - [Vidvox ISF files](https://github.com/Vidvox/ISF-Files)
   - [Magic's ISF forum threads](https://magicmusicvisuals.com/forums)

2. Install location:
   - macOS: `~/Documents/Magic/ISF/`
   - Windows: `Documents\Magic\ISF\`

3. Restart Magic to load new shaders

### Recommended ISF Effects by Category

#### Wobble / Water / Refraction

| Shader | Description | Key Parameters |
|--------|-------------|----------------|
| **Ripples.fs** | Radial water ripple | center, radius, frequency, amplitude |
| **Refract.fs** | Glass refraction | refractImage, amount |
| **BumpDistortion** | Bulge/pinch lens | center, radius, amount |
| **WaterDrop.fs** | Droplet splash | position, size, phase |

#### Glitch / Digital Distortion

| Shader | Description | Key Parameters |
|--------|-------------|----------------|
| **Chromatic.fs** | RGB channel split | amount, angle |
| **VHS Glitch.fs** | VHS tape effect | glitchAmount, scanlines, colorBleed |
| **CRT.fs** / **CRT2.fs** | Old TV effect | scanlines, curvature, vignette |
| **Digital Glitch.fs** | Block glitching | amount, blockSize |
| **RGB Shift.fs** | Color channel offset | redOffset, greenOffset, blueOffset |

#### Sparkle / Glow / Bloom

| Shader | Description | Key Parameters |
|--------|-------------|----------------|
| **Glow.fs** | Soft glow | intensity, radius |
| **Bloom.fs** | HDR bloom | threshold, intensity, radius |
| **Blur.fs** | Gaussian blur | radius |
| **Sharpen.fs** | Edge enhancement | amount |

### Using ISF in Magic

1. **Add ISF Module**: Right-click → Add → ISF → [Shader Name]
2. **Connect Input**: Source → ISF module → Output
3. **Map Parameters**: Click parameter → Link to Global or Expression

### Linking ISF Parameters to Audio

Example: Making wobble respond to mids:

1. Add Ripples.fs to your chain
2. Click on the `amplitude` parameter
3. Click the link icon (chain)
4. Choose **Global** → **MidsGlobal**
5. Add Modifiers:
   - Range: 0–1 → 0–0.6
   - Smooth: 0.3

Result: More mid-frequency energy = stronger ripple wobble.

---

## Effect Chains: Wobble, Glitch, Sparkle

This section details specific effect combinations for common VJ needs.

### The Wobble + Glitch + Sparkle Stack

A versatile effect chain that makes any input (lyrics, logos, video) look dynamic:

```
Input Source (Syphon/Video)
    │
    ├──▶ Transform (positioning, scale)
    │
    ├──▶ Wobble ISF (Ripples or BumpDistortion)
    │         └── amplitude ← [MidsGlobal] × 0.6
    │
    ├──▶ Glitch ISF (VHS Glitch or Chromatic)
    │         └── amount ← [BassGlobal] × 0.7
    │
    └──▶ Glow Chain (see below)
              └── intensity ← [HighGlobal] × 0.8
```

### Glow Chain Pattern

To add sparkle/glow, duplicate the signal and blend:

```
                    ┌───────────────────────────────────────┐
                    │                                       │
Input ──┬──────────▶│ Main Path (dry signal)               │──┐
        │           └───────────────────────────────────────┘  │
        │                                                       │
        │           ┌───────────────────────────────────────┐  │
        └──────────▶│ Blur (radius ← [HighGlobal] × 10)    │  ├──▶ Mix (Add/Screen) ──▶ Output
                    │     ↓                                 │  │
                    │ Color (brightness ← 1.0 + [HighGlobal])│  │
                    └───────────────────────────────────────┘──┘
```

Configuration:
- **Blur radius**: Link to `[HighGlobal]` → Range 0–1 → 0–10 pixels
- **Color brightness**: Expression `1.0 + [HighGlobal] * 2.0`
- **Mix B-opacity**: Link to `[HighGlobal]` → Range 0–1 → 0–1

Result: High-frequency content (hi-hats, cymbals) triggers sparkle halos.

### Wobble Effect: Mids-Reactive

Connect wobble intensity to mid-frequency energy (vocals, guitars):

```
ISF: Ripples.fs
├── center: 0.5, 0.5 (or link to [mouse_x], [mouse_y])
├── frequency: 10.0
├── amplitude: ← [MidsGlobal] via Range (0–1 → 0–0.6) + Smooth (0.3)
└── speed: 2.0
```

Or using BumpDistortion:
```
ISF: BumpDistortion
├── center: 0.5, 0.5
├── radius: 0.5
└── amount: ← [MidsGlobal] via Range (0–1 → -0.3–0.3)
```

### Glitch Effect: Bass-Reactive

Connect glitch intensity to bass (kicks, 808s):

```
ISF: VHS Glitch.fs
├── glitchAmount: ← [BassGlobal] via Peak (threshold 0.7) + Range (0–1 → 0–0.8)
├── scanlineAmount: 0.3
├── colorBleed: ← [BassGlobal] × 0.5
└── noiseAmount: ← [chaos] × 0.2
```

Using Peak modifier creates punchy, transient-triggered glitches on bass hits.

### Sparkle Effect: Highs-Reactive

Connect glow/bloom to high frequencies:

```
ISF: Bloom.fs
├── threshold: 0.6
├── intensity: ← [HighGlobal] via Range (0–1 → 0.5–2.0)
└── radius: ← [HighGlobal] via Range (0–1 → 5–20)
```

---

## Reusable Scenes and Pipelines

Magic supports scene reuse through two patterns: Scene modules and Post-Processing scenes.

### Pattern 1: Scene as Reusable Component

Create a standalone scene that can be embedded anywhere:

1. **Create the FX scene**:
   - New Scene: "FX_WobbleGlitchSparkle"
   - Build your effect chain with an input placeholder
   - Reference globals for audio reactivity

2. **Scene structure**:
   ```
   [Scene Input] ──▶ Wobble ──▶ Glitch ──▶ Glow Chain ──▶ [Scene Output]
                       ↓           ↓            ↓
                 [MidsGlobal] [BassGlobal] [HighGlobal]
   ```

3. **Use in other scenes**:
   - Add a **Scene** module
   - Set it to reference "FX_WobbleGlitchSparkle"
   - Connect your source to the Scene module

### Pattern 2: Post-Processing Scene

The Post-Processing scene is applied to ALL scenes automatically—perfect for consistent effects across your set.

1. **Create/open Post-Processing scene**:
   - Scene → Add/Update Post-Processing Scene
   - This scene receives the output of all other scenes

2. **Post-Processing structure**:
   ```
   [Scene Input] ─────────────────────────────────────┐
         │                                            │
         └──▶ Master FX (color grade, vignette) ──────┼──▶ [Magic Output]
                                                      │
   [Syphon: Lyrics] ──▶ Wobble/Glitch/Glow ──────────┘
   ```

3. **Common post-processing effects**:
   - Master color grading (always on)
   - Vignette (always on)
   - Lyrics overlay with effects
   - Watermark/logo
   - Emergency "dim to black" control

### Scene Inheritance Pattern

Build a hierarchy of reusable scenes:

```
Base Effects (parent)
├── FX_Wobble (standalone wobble)
├── FX_Glitch (standalone glitch)
└── FX_Sparkle (standalone glow)

Composite Scenes (children)
├── FX_WobbleGlitchSparkle (combines all three)
└── FX_TextEnhancer (optimized for text/lyrics)

Content Scenes (production)
├── Scene_Intro (uses FX_Wobble)
├── Scene_Buildup (uses FX_WobbleGlitchSparkle)
└── Scene_Drop (uses FX_Glitch + custom)
```

### Template Project Pattern

Save a complete project as a template:

1. **Set up your standard configuration**:
   - All global parameters defined
   - Audio analysis chain configured
   - Post-processing scene with standard effects
   - MIDI mappings configured
   - Reusable FX scenes created

2. **Save as template**:
   - File → Save As: `Magic_VJ_Template.magic`

3. **For new shows**:
   - Open the template
   - Save As new project name
   - Add content scenes
   - Keep infrastructure intact

---

## Post-Processing Scene Pattern

The Post-Processing scene is a powerful pattern for consistent, reusable effects.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     POST-PROCESSING SCENE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Scene Input ─────────────────────────────────────────────────┐  │
│       │                                                        │  │
│       ├──▶ Color Grade (always applied)                        │  │
│       │                                                        │  │
│       ├──▶ Vignette (always applied)                          │  │
│       │                                                        │  │
│       └──▶ Mix ◀─────────────────────────────────────────────┐│  │
│             │                                                 ││  │
│             │    ┌──────────────────────────────────────────┐││  │
│             │    │ Syphon (Lyrics)                          │││  │
│             │    │     ↓                                    │││  │
│             │    │ Wobble ← [MidsGlobal]                   │││  │
│             │    │     ↓                                    │││  │
│             │    │ Glitch ← [BassGlobal]                   │││  │
│             │    │     ↓                                    │││  │
│             │    │ Glow   ← [HighGlobal]                   │┘│  │
│             │    └──────────────────────────────────────────┘ │  │
│             │                                                  │  │
│             └──▶ Master Dim (× [intensity]) ──▶ Magic Output  │  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Benefits

1. **Consistency**: Same effects applied regardless of active scene
2. **Isolation**: Content scenes stay simple; FX logic centralized
3. **Failsafe**: Master dim control for emergencies
4. **Overlays**: Lyrics, logos, watermarks always visible

### Implementation Steps

1. **Create Post-Processing Scene**:
   ```
   Scene → Add/Update Post-Processing Scene
   ```

2. **Add Scene Input** (receives output from active scene):
   ```
   Right-click → Add → Utility → Scene Input
   ```

3. **Build effect chain**:
   ```
   Scene Input → Color Grade → Vignette → Mix (with overlays) → Master Dim → Magic
   ```

4. **Add overlay branch**:
   ```
   Syphon (lyrics) → Transform → Wobble → Glitch → Glow → Mix
   ```

5. **Connect to globals**:
   - Wobble amplitude ← [MidsGlobal]
   - Glitch amount ← [BassGlobal]
   - Glow intensity ← [HighGlobal]
   - Master Dim opacity ← [intensity]

---

## Song Stage Control

Effective VJ performance follows the energy arc of music. This section covers strategies for different song stages.

### Song Structure Map

```
│   INTRO   │   VERSE   │  BUILDUP  │   DROP   │   BREAK   │   OUTRO   │
│           │           │           │          │           │           │
│  low      │  moderate │  rising   │  PEAK    │  moderate │  low      │
│  energy   │  energy   │  tension  │  energy  │  recovery │  energy   │
│           │           │           │          │           │           │
│ 0.2-0.4   │  0.4-0.6  │  0.6→1.0  │ 1.0-1.2  │  0.5-0.7  │  0.2-0.4  │
│ intensity │ intensity │ intensity │intensity │ intensity │ intensity │
```

### Global Parameters for Stage Control

| Parameter | Intro | Verse | Buildup | Drop | Break | Outro |
|-----------|-------|-------|---------|------|-------|-------|
| `intensity` | 0.3 | 0.5 | 0.6→1.0 | 1.0 | 0.6 | 0.3 |
| `energy` | 0.2 | 0.4 | 0.5→1.0 | 1.5 | 0.6 | 0.2 |
| `buildLevel` | 0.0 | 0.0 | 0.0→1.0 | 0.0 | 0.0 | 0.0 |
| `dropActive` | 0.0 | 0.0 | 0.0 | 1.0 | 0.3 | 0.0 |
| `chaos` | 0.1 | 0.2 | 0.3→0.8 | 0.7 | 0.3 | 0.1 |

### Stage-Specific Expressions

#### Intro/Outro (Minimal)
```
// Gentle movement, low intensity
zoom: 1.0 + sin([time] * 0.5) * 0.05 * [intensity]
rotation: [time] * 0.1
blur: (1.0 - [intensity]) * 5.0
```

#### Verse (Moderate)
```
// Steady pulse, responsive to audio
scale: 1.0 + [BassGlobal] * [intensity] * 0.1
brightness: 0.7 + [MidsGlobal] * 0.3
saturation: 0.8 + [HighGlobal] * 0.2
```

#### Buildup (Rising Tension)
```
// Accelerating movement, increasing effects
zoom: 1.0 + [buildLevel] * [buildLevel] * 0.5
rotation: [time] * (1.0 + [buildLevel] * 4.0)
chaos: 0.1 + [buildLevel] * 0.7
strobe_rate: 1.0 + [buildLevel] * 10.0
color_shift: [time] * [buildLevel] * 2.0
```

#### Drop (Maximum Impact)
```
// Snap to maximum, then sustain
intensity: [dropActive] + (1.0 - [dropActive]) * 0.7
zoom: 1.0 + [BassGlobal] * 0.3 * [dropActive]
glitch: [BassGlobal] * [dropActive] * 0.8
flash: step(0.9, [BassGlobal]) * [dropActive]
```

#### Break (Recovery)
```
// Gradual cooldown
blur: (1.0 - [intensity]) * 3.0
zoom: 1.0 + sin([time]) * 0.1 * [intensity]
saturation: 0.5 + [intensity] * 0.5
```

### Transition Techniques

#### Ramp-Up (for buildups)
```java
// In Processing, send OSC to Magic
void updateBuildLevel() {
  buildLevel += 0.001;  // Gradual over ~16 bars
  buildLevel = min(buildLevel, 1.0);
  sendOSC("/magic/buildLevel", buildLevel);
}
```

#### Snap-Reset (for drops)
```java
void triggerDrop() {
  dropActive = 1.0;
  buildLevel = 0.0;
  sendOSC("/magic/dropActive", 1.0);
  sendOSC("/magic/buildLevel", 0.0);
}
```

#### Decay (for sustains)
```
// In Magic expression
dropActive: max(0, [dropActive] - 0.02)  // Decay over ~50 frames
```

### Scene Switching by Stage

Map scenes to Launchpad scene buttons:

| Button | Scene | Stage |
|--------|-------|-------|
| Scene 1 | Minimal_Ambient | Intro/Outro |
| Scene 2 | Verse_Moderate | Verse |
| Scene 3 | Buildup_Intense | Buildup |
| Scene 4 | Drop_Maximum | Drop |
| Scene 5 | Break_Recovery | Break |
| Scene 6 | Special_Effect | Special moments |

---

## MIDI Control Patterns

### Recommended Controller Mapping

#### Akai MIDImix Mapping

| Control | MIDI | Maps To | Purpose |
|---------|------|---------|---------|
| Fader 1 | CC 19 | `[intensity]` | Master intensity |
| Fader 2 | CC 23 | `[energy]` | Overall energy |
| Fader 3 | CC 27 | `[buildLevel]` | Manual buildup |
| Fader 4 | CC 31 | `[chaos]` | Randomness |
| Fader 5 | CC 49 | `[BassGlobal]` override | Manual bass |
| Fader 6 | CC 53 | `[MidsGlobal]` override | Manual mids |
| Fader 7 | CC 57 | `[HighGlobal]` override | Manual highs |
| Fader 8 | CC 61 | `[zoom]` | Global zoom |
| Knob 1 | CC 16 | Wobble amount | Effect control |
| Knob 2 | CC 17 | Glitch amount | Effect control |
| Knob 3 | CC 18 | Glow amount | Effect control |
| Master | CC 62 | `[master_dim]` | Emergency dim |

#### Launchpad Mapping

| Pad | Action |
|-----|--------|
| Scene 1-4 | Switch scenes |
| Scene 5-8 | Trigger effects |
| Grid row 8 | Scene presets |
| Grid row 7 | Transition triggers |
| Grid row 1-6 | Custom triggers |
| Bottom-left | `[dropActive]` toggle |

### MIDI Learn in Magic

1. Right-click any parameter
2. Select **MIDI Learn**
3. Move your controller
4. Parameter is now mapped

### Expression with MIDI Override

Allow MIDI to override audio when moved:

```
// Use MIDI if recently moved, otherwise use audio
bass_control: max([BassGlobal], [midi_cc_49] * [midi_cc_49_active])
```

Where `midi_cc_49_active` is 1.0 when recently moved, decaying to 0.0.

---

## Processing + Syphon Integration

### Basic Integration Pattern

```java
// Processing sketch sending to Magic
import codeanticode.syphon.*;

SyphonServer syphon;

void settings() {
  size(1920, 1080, P3D);
}

void setup() {
  syphon = new SyphonServer(this, "ProcessingViz");
}

void draw() {
  background(0);
  // Your visuals here
  syphon.sendScreen();
}
```

In Magic:
1. Add **Syphon Client** module
2. Select "ProcessingViz" as source
3. Route through effect chain

### Multi-Source Setup

```
┌─────────────────────────────────────────────────────────────────┐
│                     MAGIC PROJECT                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Syphon: "ProcessingGame" ──┐                                    │
│                              │                                    │
│  Syphon: "ProcessingLyrics"─┼──▶ Mix ──▶ Post-FX ──▶ Magic      │
│                              │                                    │
│  Syphon: "Synesthesia" ─────┘                                    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### OSC Control from Processing

Control Magic globals from Processing via OSC:

```java
// Processing sketch
import oscP5.*;
import netP5.*;

OscP5 oscP5;
NetAddress magicAddress;

void setup() {
  oscP5 = new OscP5(this, 8001);
  magicAddress = new NetAddress("127.0.0.1", 8000);
}

void sendToMagic(String param, float value) {
  OscMessage msg = new OscMessage("/magic/" + param);
  msg.add(value);
  oscP5.send(msg, magicAddress);
}

void triggerDrop() {
  sendToMagic("dropActive", 1.0);
  sendToMagic("buildLevel", 0.0);
  sendToMagic("intensity", 1.0);
}
```

### Bidirectional Communication

Processing can both send visuals AND control signals:

```
┌─────────────┐                      ┌─────────────┐
│ Processing  │──── Syphon ─────────▶│    Magic    │
│             │                      │             │
│  Visuals    │──── OSC (control) ──▶│  Globals    │
│  + Control  │                      │  + Effects  │
│             │◀─── OSC (feedback) ──│             │
└─────────────┘                      └─────────────┘
```

---

## Templates and Best Practices

### Project Template Checklist

When creating a new VJ project, set up:

- [ ] **Global Parameters**
  - [ ] Audio bands: BassGlobal, MidsGlobal, HighGlobal
  - [ ] Control: intensity, energy, buildLevel, dropActive
  - [ ] Style: chaos, palette, zoom
  - [ ] Master: master_dim (safety control)

- [ ] **Audio Analysis Chain**
  - [ ] Audio input (BlackHole or device)
  - [ ] Three-band analysis with Range + Smooth
  - [ ] Peak detection for transients

- [ ] **Post-Processing Scene**
  - [ ] Scene Input connected
  - [ ] Master color grade
  - [ ] Vignette
  - [ ] Overlay branch for lyrics/logos
  - [ ] Master dim control

- [ ] **Reusable FX Scenes**
  - [ ] FX_Wobble (mids-reactive)
  - [ ] FX_Glitch (bass-reactive)
  - [ ] FX_Sparkle (highs-reactive)
  - [ ] FX_Combined (all three)

- [ ] **MIDI Mappings**
  - [ ] Faders → intensity, energy, buildLevel
  - [ ] Knobs → effect amounts
  - [ ] Buttons → scene triggers, toggles
  - [ ] Master fader → safety dim

- [ ] **Syphon Sources**
  - [ ] Processing game/viz input
  - [ ] Lyrics input
  - [ ] Any additional sources

### Performance Best Practices

1. **Always have a master dim** - Map to easily accessible control
2. **Test with various music** - Your presets should work across genres
3. **Keep baseline values sane** - Even at intensity 0.0, something should be visible
4. **Smooth everything** - Jerky visuals are rarely intentional
5. **Less is more during verses** - Save intensity for drops
6. **Pre-load all scenes** - Avoid loading lag during performance
7. **Have fallback scenes** - Simple scenes that always work
8. **Document your mappings** - You'll forget which knob does what

### Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| No audio reactivity | Audio input not configured | Check Audio module input device |
| Jerky effects | No smoothing on audio | Add Smooth modifier (0.2-0.4) |
| Effects too strong | Range mapping too wide | Reduce output range |
| Effects too weak | Range mapping too narrow | Increase output range |
| Syphon not appearing | Wrong server name | Match exact spelling in Magic |
| High CPU usage | Too many effects | Reduce ISF shader count |
| MIDI not responding | Wrong channel/CC | Check MIDI learn or manual mapping |

---

## Resources

### Official Documentation
- [Magic User's Guide](https://magicmusicvisuals.com/documentation) - Complete reference
- [Magic User's Guide (HTML)](https://magicmusicvisuals.com/downloads/Magic_UsersGuide.html) - Downloadable reference
- [Magic Tutorials](https://magicmusicvisuals.com/tutorials) - Video tutorials
- [Magic Resources](https://magicmusicvisuals.com/resources) - Community resources

### Forums and Community
- [Magic Forums](https://magicmusicvisuals.com/forums) - Official community
- [Expressions/Variables Thread](https://magicmusicvisuals.com/forums/viewtopic.php?t=3207) - Syntax guide
- [Global Input Volume](https://magicmusicvisuals.com/forums/viewtopic.php?t=2611) - Audio control
- [ISF/FFGL Integration](https://magicmusicvisuals.com/forums/viewtopic.php?t=412) - Plugin guide
- [Shadertoy Converter](https://magicmusicvisuals.com/forums/viewtopic.php?t=495) - Shader conversion

### ISF Resources
- [ISF.video](https://isf.video/) - Official ISF site and shader library
- [Vidvox ISF Files](https://github.com/Vidvox/ISF-Files) - Large shader collection
- [ISF Specification](https://github.com/mrRay/ISF_Spec) - Technical specification
- [ISF Circular Waveform Example](https://gist.github.com/jangxx/9b9e273c1640efa5ab3695da1907a6dd) - Practical example

### Related Guides in This Repository
- [Live VJ Setup Guide](live-vj-setup-guide.md) - Full rig architecture
- [MIDI Controller Setup](midi-controller-setup.md) - Launchpad and MIDImix configuration
- [Processing Games Guide](processing-games-guide.md) - Processing integration details
- [ISF to Synesthesia Migration](isf-to-synesthesia-migration.md) - Shader format conversion

### Audio Routing
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) - macOS audio loopback

### Additional Tools
- [Syphon](http://syphon.info/) - Frame sharing framework
- [OSC Protocol](http://opensoundcontrol.org/) - Open Sound Control for app communication

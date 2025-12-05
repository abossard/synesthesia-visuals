# Magic Music Visuals: Master Pipeline Guide

A complete, production-ready pipeline for live VJ performance using Magic Music Visuals (MMV). This guide provides a coherent, copy-paste-ready setup with precise naming, expressions, and detailed diagrams.

## Table of Contents

1. [High-Level Pipeline Overview](#high-level-pipeline-overview)
2. [MIDImix Controller Mapping](#midimix-controller-mapping)
3. [Audio Analysis Globals](#audio-analysis-globals)
4. [Energy and Beat Globals](#energy-and-beat-globals)
5. [Buildup and Drop Controls](#buildup-and-drop-controls)
6. [Generator Bank System](#generator-bank-system)
7. [Scene Structures](#scene-structures)
8. [Karaoke Integration](#karaoke-integration)
9. [Main Scene Assembly](#main-scene-assembly)
10. [Quick Reference](#quick-reference)

---

## High-Level Pipeline Overview

This pipeline uses a modular bus architecture for clean signal flow and audio-reactive control:

**Components:**
- **2 generator buses**: `GEN_BUS_A`, `GEN_BUS_B` (crossfaded by buildup/drop)
- **1 mask bus**: `MASK_BUS` (applies masks and karaoke text overlay)
- **1 FX bus**: `FX_BUS` (global distortion, warp, color processing)
- **Karaoke input**: Via Syphon from external app
- **MIDI controller**: Akai MIDImix for all manual controls
- **Globals**: Audio bands, energy, buildup, drop, bus selection, randomization

```mermaid
flowchart TD
    subgraph INPUT["Audio & MIDI Input"]
        AUDIO["Audio In<br/>(BlackHole)"]
        MIDI["MIDImix<br/>MIDI Controller"]
    end
    
    subgraph ANALYSIS["Audio Analysis"]
        AUDIO --> BANDS["Frequency Bands<br/>Bass, LowMid, Highs"]
        AUDIO --> ENERGY["Energy Tracking<br/>EnergyFast, EnergySlow"]
        AUDIO --> KICK["Kick Detection<br/>KickRaw, KickEnv, KickPulse"]
        AUDIO --> BEAT["Beat Counter<br/>Beat4"]
    end
    
    subgraph CONTROL["Manual Controls"]
        MIDI --> MULTI["Multi<br/>(Sensitivity)"]
        MIDI --> BUILDUP["Buildup"]
        MIDI --> DROP_BTN["Drop Button"]
        MIDI --> MASTER_INT["MasterIntensity"]
        MIDI --> BLACKOUT["Blackout"]
    end
    
    subgraph GLOBALS["Global Expressions"]
        BANDS --> GLOBAL_EX["Expression Engine"]
        ENERGY --> GLOBAL_EX
        KICK --> GLOBAL_EX
        BEAT --> GLOBAL_EX
        MULTI --> GLOBAL_EX
        BUILDUP --> GLOBAL_EX
        DROP_BTN --> GLOBAL_EX
        MASTER_INT --> GLOBAL_EX
    end
    
    subgraph GENERATORS["Generator Buses"]
        GLOBAL_EX --> GENA["GEN_BUS_A<br/>(Intro/Verse)"]
        GLOBAL_EX --> GENB["GEN_BUS_B<br/>(Buildup/Drop)"]
        GENA --> GENMIX["GenBankMix<br/>(A/B Crossfade)"]
        GENB --> GENMIX
        GENMIX --> GENOUT["GEN_OUT"]
    end
    
    subgraph MASKING["Mask & Karaoke"]
        GENOUT --> MASK_IN["MASK_BUS<br/>SceneInput"]
        KARAOKE["Karaoke<br/>(Syphon)"] --> MASK_IN
        MASK_IN --> MASK_OUT["MASK_OUT"]
    end
    
    subgraph FX["Effects Processing"]
        MASK_OUT --> FX_IN["FX_BUS<br/>SceneInput"]
        FX_IN --> FX_PROC["Warp + Color<br/>Processing"]
        FX_PROC --> FX_OUT["FX_OUT"]
    end
    
    subgraph OUTPUT["Master Output"]
        FX_OUT --> MASTER_MIX["Master Mix<br/>(Intensity × Blackout)"]
        BLACKOUT --> MASTER_MIX
        MASTER_MIX --> SCREEN["Screen Output"]
    end
    
    style INPUT fill:#e1f5ff
    style ANALYSIS fill:#fff3e0
    style CONTROL fill:#f3e5f5
    style GLOBALS fill:#e8f5e9
    style GENERATORS fill:#fff9c4
    style MASKING fill:#fce4ec
    style FX fill:#e0f2f1
    style OUTPUT fill:#f1f8e9
```

**Conceptual Signal Flow:**

```
Audio → Bands + Energy + Kick + Beat4
           ↓
MIDImix → Multi, Buildup, Drop, Master
           ↓
      Globals/Expressions
           ↓
    ┌──────────────┐
    │  GEN_BUS_A   │ (Intro/Verse shaders)
    └──────────────┘
           ↓
    ┌──────────────┐
    │  GEN_BUS_B   │ (Buildup/Drop shaders)
    └──────────────┘
           ↓
   Mix(A,B) with GenBankMix → GEN_OUT
           ↓
    ┌──────────────┐
    │  MASK_BUS    │ (GEN_OUT + Karaoke text)
    └──────────────┘
           ↓
    ┌──────────────┐
    │   FX_BUS     │ (Warp, color processing)
    └──────────────┘
           ↓
  Master control → Screen
```

---

## MIDImix Controller Mapping

The Akai MIDImix provides 8 strips with faders, knobs, and buttons, plus a master fader. This section defines the **exact** CC numbers and roles for each control.

### Strip 8: Global Master Controls

**Purpose**: Overall sensitivity, buildup, randomization, and master intensity.

| Control | CC# | Global Name | Range | Purpose |
|---------|-----|-------------|-------|---------|
| Knob 1 | 24 | `Multi` | 0.3–2.0 | Audio sensitivity multiplier |
| Knob 2 | 25 | `Buildup` | 0.0–1.0 | Manual buildup level |
| Knob 3 | 26 | `RandGlobalAmt` | 0.0–1.0 | Global randomization amount |
| Fader | 27 | `MasterIntensity` | 0.0–1.0 | Master effect intensity |
| Button A (lower) | Note 27 | `Drop` | 0/1 toggle | Drop trigger |
| Button B (upper) | Note 43 | `Blackout` | 0/1 toggle | Emergency blackout |

### Strip 1: Generator Bank Controls

**Purpose**: Generator bus selection, density, randomization.

| Control | CC# | Global Name | Range | Purpose |
|---------|-----|-------------|-------|---------|
| Knob 1 | 16 | `GenBankManual` | 0.0–1.0 | Manual A/B crossfade |
| Knob 2 | 17 | `GenLayerDensity` | 0.0–1.0 | Layer visibility density |
| Knob 3 | 18 | `GenRandAmt` | 0.0–1.0 | Generator randomization amount |
| Fader | 19 | `GenIntensityManual` | 0.0–1.0 | Generator intensity control |
| Button A | Note 1 | `GenRandomize` | Bang | Randomize gen indices |
| Button B | Note 17 | `GenRandLock` | 0/1 toggle | Lock randomization |

### Strip 2: Mask Bus Controls

**Purpose**: Mask strength, karaoke opacity, randomization.

| Control | CC# | Global Name | Range | Purpose |
|---------|-----|-------------|-------|---------|
| Knob 1 | 20 | `MaskAmountManual` | 0.0–1.0 | Mask strength control |
| Knob 2 | 21 | `KaraokeOpacityManual` | 0.0–1.0 | Karaoke text opacity |
| Knob 3 | 22 | `MaskRandAmt` | 0.0–1.0 | Mask randomization amount |
| Fader | 23 | `MaskBusMix` | 0.0–1.0 | Mask bus mix level |
| Button A | Note 2 | `MaskRandomize` | Bang | Randomize mask index |
| Button B | Note 18 | `MaskRandLock` | 0/1 toggle | Lock mask randomization |

### Strip 3: FX Bus Controls

**Purpose**: Effects processing (warp, color shift).

| Control | CC# | Global Name | Range | Purpose |
|---------|-----|-------------|-------|---------|
| Knob 1 | 28 | `FXAmountManual` | 0.0–1.0 | FX intensity control |
| Knob 2 | 29 | `FXWarpManual` | 0.0–1.0 | Warp/distortion amount |
| Knob 3 | 30 | `FXColorShiftManual` | 0.0–1.0 | Color shift amount |
| Fader | 31 | `FXBusMix` | 0.0–1.0 | FX bus mix level |
| Button A | Note 3 | `FXRandomize` | Bang | Randomize FX selection |
| Button B | Note 19 | `FXRandLock` | 0/1 toggle | Lock FX randomization |

### Strips 4–7: Reserved for Expansion

These strips are available for:
- Camera controls (position, zoom, rotation)
- Color palette selection
- Special effect triggers
- Scene-specific parameters

---

## Audio Analysis Globals

All audio analysis uses **Source 0** (main stereo audio input, typically BlackHole).

**Note**: In all expressions below, `x` refers to the incoming value at that stage of the modifier chain.

### Multi (Overall Sensitivity)

**Multi** – Source: MIDI CC #24 (Strip 8 / Knob 1)

Modifiers:
1. **Expression**: `0.3 + x * 1.7`

**Result**: Knob position [0,1] → Multi ≈ [0.3, 2.0]

**Purpose**: Global sensitivity multiplier for all audio bands.

```mermaid
flowchart TD
    MIDI_IN["MIDI CC #24<br/>(Strip 8 Knob 1)"] --> EXPR["Expression:<br/>0.3 + x * 1.7"]
    EXPR --> MULTI["Multi<br/>(Range: 0.3–2.0)"]
    
    style MIDI_IN fill:#e3f2fd
    style EXPR fill:#fff3e0
    style MULTI fill:#e8f5e9
```

---

### Frequency Bands

#### Bass

**Bass** – Source 0 / Feature: Freq. Range 20–120 Hz

Modifiers:
1. **Smooth**: `0.15`
2. **Expression**: `min(max(x * Multi * 2.0, 0), 1)`

**Purpose**: Kick drum and sub-bass detection.

```mermaid
flowchart TD
    AUDIO["Audio Source 0<br/>(20–120 Hz)"] --> SMOOTH1["Smooth: 0.15"]
    SMOOTH1 --> EXPR1["Expression:<br/>min(max(x × Multi × 2.0, 0), 1)"]
    EXPR1 --> BASS["Bass<br/>(Range: 0–1)"]
    
    MULTI2["Multi"] -.-> EXPR1
    
    style AUDIO fill:#e3f2fd
    style SMOOTH1 fill:#fff3e0
    style EXPR1 fill:#fff9c4
    style BASS fill:#e8f5e9
    style MULTI2 fill:#f3e5f5
```

#### LowMid

**LowMid** – Source 0 / Feature: Freq. Range 120–350 Hz

Modifiers:
1. **Smooth**: `0.15`
2. **Expression**: `min(max(x * Multi * 2.0, 0), 1)`

**Purpose**: Body of drums and low synth tones.

#### Highs

**Highs** – Source 0 / Feature: Freq. Range 2000–6000 Hz

Modifiers:
1. **Smooth**: `0.15`
2. **Expression**: `min(max(x * Multi * 2.0, 0), 1)`

**Purpose**: Brightness, hi-hats, cymbals, detail.

**Optional Additional Bands**:
- **VoiceMid** (350–2000 Hz) – Vocals and lead synth presence
- **VeryHigh** (6000–20000 Hz) – Air, sparkle, fine detail

---

### MasterIntensity

**MasterIntensity** – Source: MIDI CC #27 (Strip 8 / Fader)

Modifiers:
1. **Smooth**: `0.3`

**Purpose**: Master control for overall effect intensity.

```mermaid
flowchart TD
    MIDI_FADER["MIDI CC #27<br/>(Strip 8 Fader)"] --> SMOOTH_M["Smooth: 0.3"]
    SMOOTH_M --> MASTER_INT["MasterIntensity<br/>(Range: 0–1)"]
    
    style MIDI_FADER fill:#e3f2fd
    style SMOOTH_M fill:#fff3e0
    style MASTER_INT fill:#e8f5e9
```

---

## Energy and Beat Globals

### Energy Tracking

#### EnergyFast (Instant Intensity)

**EnergyFast** – Source: Expression-only (no audio source)

Modifiers:
1. **Expression**: `Bass * 0.5 + LowMid * 0.3 + Highs * 0.2`
2. **Smooth**: `0.4`
3. **Expression**: `min(max(x, 0), 1)`

**Purpose**: Real-time "how loud is it right now" indicator.

```mermaid
flowchart TD
    BASS_IN["Bass"] --> EXPR_E1["Expression:<br/>Bass × 0.5 + LowMid × 0.3 + Highs × 0.2"]
    LOWMID_IN["LowMid"] --> EXPR_E1
    HIGHS_IN["Highs"] --> EXPR_E1
    
    EXPR_E1 --> SMOOTH_E1["Smooth: 0.4"]
    SMOOTH_E1 --> EXPR_E2["Expression:<br/>min(max(x, 0), 1)"]
    EXPR_E2 --> ENERGY_FAST["EnergyFast<br/>(Range: 0–1)"]
    
    style BASS_IN fill:#f3e5f5
    style LOWMID_IN fill:#f3e5f5
    style HIGHS_IN fill:#f3e5f5
    style EXPR_E1 fill:#fff9c4
    style SMOOTH_E1 fill:#fff3e0
    style EXPR_E2 fill:#fff9c4
    style ENERGY_FAST fill:#e8f5e9
```

#### EnergySlow (Build-Up Level)

**EnergySlow** – Source: EnergyFast / Feature: Value

Modifiers:
1. **Average**: `4.0` (seconds)
2. **Expression**: `min(max(x, 0), 1)`

**Purpose**: Averaged energy over time for gradual intensity changes.

**Use for**: Layer count, geometry complexity, slowly growing brightness/feedback.

```mermaid
flowchart TD
    ENERGY_FAST_IN["EnergyFast"] --> AVG["Average: 4.0 seconds"]
    AVG --> EXPR_ES["Expression:<br/>min(max(x, 0), 1)"]
    EXPR_ES --> ENERGY_SLOW["EnergySlow<br/>(Range: 0–1)"]
    
    style ENERGY_FAST_IN fill:#f3e5f5
    style AVG fill:#fff3e0
    style EXPR_ES fill:#fff9c4
    style ENERGY_SLOW fill:#e8f5e9
```

---

### Kick Detection

#### KickRaw

**KickRaw** – Source 0 / Feature: Freq. Range 40–120 Hz

Modifiers:
1. **Smooth**: `0.05`
2. **Peak**: `0.5`

**Purpose**: Raw kick transient detection.

#### KickEnv

**KickEnv** – Source: KickRaw / Feature: Value

Modifiers:
1. **Smooth**: `0.35`
2. **Expression**: `min(x * 2.0, 1)`

**Purpose**: Smooth envelope that bumps on each kick and decays between beats.

#### KickPulse

**KickPulse** – Source: KickEnv / Feature: Value

Modifiers:
1. **Threshold**: `0.6` (outputs 0 or 1)
2. **Trigger (Integer)**: Threshold `0.5` (optional for clean pulses)

**Purpose**: Binary kick trigger for one-shot events (flashes, step changes).

```mermaid
flowchart TD
    AUDIO_KICK["Audio Source 0<br/>(40–120 Hz)"] --> SMOOTH_K1["Smooth: 0.05"]
    SMOOTH_K1 --> PEAK_K["Peak: 0.5"]
    PEAK_K --> KICK_RAW["KickRaw"]
    
    KICK_RAW --> SMOOTH_K2["Smooth: 0.35"]
    SMOOTH_K2 --> EXPR_K["Expression:<br/>min(x × 2.0, 1)"]
    EXPR_K --> KICK_ENV["KickEnv"]
    
    KICK_ENV --> THRESH_K["Threshold: 0.6"]
    THRESH_K --> TRIG_K["Trigger (Integer):<br/>Threshold 0.5"]
    TRIG_K --> KICK_PULSE["KickPulse<br/>(0 or 1)"]
    
    style AUDIO_KICK fill:#e3f2fd
    style KICK_RAW fill:#e8f5e9
    style KICK_ENV fill:#e8f5e9
    style KICK_PULSE fill:#e8f5e9
```

---

### Beat Counter

#### Beat4 (4-Beat Counter)

**Beat4** – Source: KickPulse / Feature: Value

Modifiers:
1. **Trigger (Integer)**: Threshold `0.5`
2. **Increase**: Step `1`
3. **Wrap**: `4.0`

**Result**: Cycles through 0 → 1 → 2 → 3 → 0 (repeating) in sync with kicks.

**Typical Usage in Expressions**:
- `Beat4 == 0` → "bar 1" accents
- `Beat4 % 2` → every second beat
- `1 + 0.2 * (Beat4 == 0)` → boost on first beat

```mermaid
flowchart TD
    KICK_PULSE_IN["KickPulse"] --> TRIG_B["Trigger (Integer):<br/>Threshold 0.5"]
    TRIG_B --> INC_B["Increase:<br/>Step 1"]
    INC_B --> WRAP_B["Wrap: 4.0"]
    WRAP_B --> BEAT4["Beat4<br/>(Values: 0, 1, 2, 3)"]
    
    style KICK_PULSE_IN fill:#f3e5f5
    style TRIG_B fill:#fff3e0
    style INC_B fill:#fff3e0
    style WRAP_B fill:#fff3e0
    style BEAT4 fill:#e8f5e9
```

---

## Buildup and Drop Controls

### Buildup

**Buildup** – Source: MIDI CC #25 (Strip 8 / Knob 2)

Modifiers:
1. **Smooth**: `0.5`
2. **Expression**: `min(max(x, 0), 1)`

**Purpose**: Manual control for building tension before a drop.

```mermaid
flowchart TD
    MIDI_BUILD["MIDI CC #25<br/>(Strip 8 Knob 2)"] --> SMOOTH_BUILD["Smooth: 0.5"]
    SMOOTH_BUILD --> EXPR_BUILD["Expression:<br/>min(max(x, 0), 1)"]
    EXPR_BUILD --> BUILDUP["Buildup<br/>(Range: 0–1)"]
    
    style MIDI_BUILD fill:#e3f2fd
    style SMOOTH_BUILD fill:#fff3e0
    style EXPR_BUILD fill:#fff9c4
    style BUILDUP fill:#e8f5e9
```

---

### Drop (Toggle)

**Drop** – Source: MIDI Note 27 (Strip 8 / Button A)

Modifiers:
1. **Trigger (Integer)**: Threshold `0.5`
2. **Wrap**: `2.0`

**Result**: Toggles between 0 and 1 on each button press.

**Purpose**: Activate "drop" mode for heavy visuals.

```mermaid
flowchart TD
    MIDI_DROP["MIDI Note 27<br/>(Strip 8 Button A)"] --> TRIG_DROP["Trigger (Integer):<br/>Threshold 0.5"]
    TRIG_DROP --> WRAP_DROP["Wrap: 2.0"]
    WRAP_DROP --> DROP["Drop<br/>(Values: 0, 1)"]
    
    style MIDI_DROP fill:#e3f2fd
    style TRIG_DROP fill:#fff3e0
    style WRAP_DROP fill:#fff3e0
    style DROP fill:#e8f5e9
```

---

### DropPulse (One-Shot Spike)

**DropPulse** – Source: MIDI Note 27 (same as Drop)

Modifiers:
1. **Threshold**: `0.5`

**Result**: Spike at press (0→1 only while button is pressed).

**Purpose**: Trigger randomization or one-shot effects on drop.

---

### Blackout (Emergency Kill)

**Blackout** – Source: MIDI Note 43 (Strip 8 / Button B)

Modifiers:
1. **Trigger (Integer)**: Threshold `0.5`
2. **Wrap**: `2.0`

**Result**: Toggles between 0 (normal) and 1 (blackout).

**Purpose**: Emergency "kill all visuals" button.

---

## Generator Bank System

The generator bank system provides two independent shader buses (A and B) that are crossfaded based on song energy and manual control.

**Architecture**:
- **GEN_BUS_A**: "Intro/Verse" look (calmer, geometric patterns)
- **GEN_BUS_B**: "Buildup/Drop" look (intense, chaotic patterns)
- Each bus contains N shaders (e.g., 3) with index-based selection
- Crossfade between A and B driven by `GenBankMix`

### GenBankMix (A/B Crossfade)

#### GenBankManual

**GenBankManual** – Source: MIDI CC #16 (Strip 1 / Knob 1)

Modifiers:
1. **Smooth**: `0.3`

**Purpose**: Manual control for A→B crossfade.

#### GenBankMix (Derived)

**GenBankMix** – Source: Expression-only

Modifiers:
1. **Expression**: `min(max(0.5 * Buildup + 0.5 * GenBankManual + Drop * (1 - Buildup), 0), 1)`

**Effect**:
- `Buildup` and `GenBankManual` both push from A→B
- `Drop` forces toward B even if `Buildup` is low
- Range: 0.0 (100% A) → 1.0 (100% B)

```mermaid
flowchart TD
    BUILDUP_IN["Buildup"] --> EXPR_MIX["Expression:<br/>min(max(0.5 × Buildup + 0.5 × GenBankManual<br/>+ Drop × (1 - Buildup), 0), 1)"]
    GENBANKMAN["GenBankManual"] --> EXPR_MIX
    DROP_IN["Drop"] --> EXPR_MIX
    
    EXPR_MIX --> GENBANKMIX["GenBankMix<br/>(0 = A, 1 = B)"]
    
    style BUILDUP_IN fill:#f3e5f5
    style GENBANKMAN fill:#f3e5f5
    style DROP_IN fill:#f3e5f5
    style EXPR_MIX fill:#fff9c4
    style GENBANKMIX fill:#e8f5e9
```

---

### Slot Index and Randomization (Per Bus)

For each generator bus (A and B), we need index selection and randomization.

**Example for GEN_BUS_A** (assuming 3 shaders: slots 0, 1, 2):

#### GenA_Index_Base

**GenA_Index_Base** – Source: MIDI CC #17 (Strip 1 / Knob 2) or Expression

Modifiers:
1. **Expression**: `floor(x * 3)`

**Result**: Manual selection of slots 0, 1, or 2.

#### GenA_Index_Offset

**GenA_Index_Offset** – Source: DropPulse / Feature: Value

Modifiers:
1. **Trigger (Random)**
2. **Expression**: `floor(x * 3)`

**Purpose**: Randomize offset on drop (0, 1, or 2).

#### GenA_Index

**GenA_Index** – Source: Expression-only

Modifiers:
1. **Expression**: `(GenA_Index_Base + GenA_Index_Offset) % 3`

**Result**: Final active slot index (0, 1, or 2).

**Repeat for GEN_BUS_B**:
- `GenB_Index_Base`
- `GenB_Index_Offset`
- `GenB_Index`

```mermaid
flowchart TD
    MIDI_INDEX["MIDI CC #17<br/>(Strip 1 Knob 2)"] --> EXPR_BASE["Expression:<br/>floor(x × 3)"]
    EXPR_BASE --> INDEX_BASE["GenA_Index_Base<br/>(0, 1, or 2)"]
    
    DROP_PULSE_IN["DropPulse"] --> TRIG_RAND["Trigger (Random)"]
    TRIG_RAND --> EXPR_RAND["Expression:<br/>floor(x × 3)"]
    EXPR_RAND --> INDEX_OFFSET["GenA_Index_Offset<br/>(0, 1, or 2)"]
    
    INDEX_BASE --> EXPR_FINAL["Expression:<br/>(GenA_Index_Base + GenA_Index_Offset) % 3"]
    INDEX_OFFSET --> EXPR_FINAL
    EXPR_FINAL --> INDEX["GenA_Index<br/>(Final: 0, 1, or 2)"]
    
    style MIDI_INDEX fill:#e3f2fd
    style DROP_PULSE_IN fill:#f3e5f5
    style INDEX_BASE fill:#e8f5e9
    style INDEX_OFFSET fill:#e8f5e9
    style INDEX fill:#e8f5e9
```

---

### Slot Weights (Hard Switch)

For each slot in a bus, create a weight global:

**For GEN_BUS_A**:

**GenA_Slot0_Weight** – Source: Expression-only
- **Expression**: `GenA_Index == 0`

**GenA_Slot1_Weight** – Source: Expression-only
- **Expression**: `GenA_Index == 1`

**GenA_Slot2_Weight** – Source: Expression-only
- **Expression**: `GenA_Index == 2`

**Result**: Only one weight is 1, others are 0.

**Alternative (Soft Crossfade)**:

For smooth transitions between slots:

```
GenA_Slot0_Weight = max(1 - abs(GenA_Index - 0), 0)
GenA_Slot1_Weight = max(1 - abs(GenA_Index - 1), 0)
GenA_Slot2_Weight = max(1 - abs(GenA_Index - 2), 0)
```

---

### Generator Intensity

#### GenIntensityManual

**GenIntensityManual** – Source: MIDI CC #19 (Strip 1 / Fader)

Modifiers:
1. **Smooth**: `0.3`

#### GenIntensity (Derived)

**GenIntensity** – Source: Expression-only

Modifiers:
1. **Expression**: `min(max(GenIntensityManual * (0.6 + 0.4 * EnergyFast) * (0.6 + 0.4 * Buildup) * (1 + 0.7 * Drop), 0), 2)`

**Effect**: Generator strength reacts to manual control, energy, buildup, and drop.

```mermaid
flowchart TD
    GEN_MAN["GenIntensityManual"] --> EXPR_INT["Expression:<br/>min(max(GenIntensityManual × (0.6 + 0.4 × EnergyFast)<br/>× (0.6 + 0.4 × Buildup) × (1 + 0.7 × Drop), 0), 2)"]
    ENERGY_FAST_IN2["EnergyFast"] --> EXPR_INT
    BUILDUP_IN2["Buildup"] --> EXPR_INT
    DROP_IN2["Drop"] --> EXPR_INT
    
    EXPR_INT --> GEN_INT["GenIntensity<br/>(Range: 0–2)"]
    
    style GEN_MAN fill:#f3e5f5
    style ENERGY_FAST_IN2 fill:#f3e5f5
    style BUILDUP_IN2 fill:#f3e5f5
    style DROP_IN2 fill:#f3e5f5
    style EXPR_INT fill:#fff9c4
    style GEN_INT fill:#e8f5e9
```

---

### Randomization Pattern

For any parameter that should blend manual and random control:

```
ParamFinal = ManualParam * (1 - RandGlobalAmt * GenRandAmt)
           + RandParam * RandGlobalAmt * GenRandAmt
```

Where:
- `ManualParam` = manual control value
- `RandParam` = randomized value (from Trigger (Random))
- `RandGlobalAmt` = global randomization amount (MIDI CC #26)
- `GenRandAmt` = generator-specific randomization amount (MIDI CC #18)

---

## Scene Structures

### GEN_BUS_A Scene

**Purpose**: "Intro/Verse" generator bus with calmer, geometric patterns.

**Structure**:

```mermaid
flowchart TD
    subgraph GEN_A["GEN_BUS_A Scene"]
        SHADER_A0["GLSL_Tunnel<br/>(Shader 0)"] --> MIX_A0["Mix_A0<br/>Opacity: GenA_Slot0_Weight × GenIntensity"]
        SHADER_A1["GLSL_Grid<br/>(Shader 1)"] --> MIX_A1["Mix_A1<br/>Opacity: GenA_Slot1_Weight × GenIntensity"]
        SHADER_A2["GLSL_Noise<br/>(Shader 2)"] --> MIX_A2["Mix_A2<br/>Opacity: GenA_Slot2_Weight × GenIntensity"]
        
        MIX_A0 --> BLEND_A1["Add/Blend"]
        MIX_A1 --> BLEND_A1
        BLEND_A1 --> BLEND_A2["Add/Blend"]
        MIX_A2 --> BLEND_A2
        
        BLEND_A2 --> OUTPUT_A["Scene Output<br/>(GEN_A_OUT)"]
    end
    
    SLOT0_W["GenA_Slot0_Weight"] -.-> MIX_A0
    SLOT1_W["GenA_Slot1_Weight"] -.-> MIX_A1
    SLOT2_W["GenA_Slot2_Weight"] -.-> MIX_A2
    GEN_INT_A["GenIntensity"] -.-> MIX_A0
    GEN_INT_A -.-> MIX_A1
    GEN_INT_A -.-> MIX_A2
    
    style SHADER_A0 fill:#e1f5ff
    style SHADER_A1 fill:#e1f5ff
    style SHADER_A2 fill:#e1f5ff
    style MIX_A0 fill:#fff9c4
    style MIX_A1 fill:#fff9c4
    style MIX_A2 fill:#fff9c4
    style BLEND_A1 fill:#f3e5f5
    style BLEND_A2 fill:#f3e5f5
    style OUTPUT_A fill:#e8f5e9
```

**Implementation**:

1. **Create Scene**: `GEN_BUS_A`

2. **Add 3 GLSLShader modules**:
   - `GLSL_Tunnel`
   - `GLSL_Grid`
   - `GLSL_Noise`

3. **Add Mix modules after each shader**:
   - `Mix_A0`: Input A = `GLSL_Tunnel`, Input B = black
     - Opacity parameter: Link to expression `GenA_Slot0_Weight * GenIntensity`
   - `Mix_A1`: Input A = black, Input B = `GLSL_Grid`
     - Opacity parameter: `GenA_Slot1_Weight * GenIntensity`
   - `Mix_A2`: Input A = black, Input B = `GLSL_Noise`
     - Opacity parameter: `GenA_Slot2_Weight * GenIntensity`

4. **Add Add/Blend modules**:
   - `Blend_A1`: Combine `Mix_A0` + `Mix_A1`
   - `Blend_A2`: Combine `Blend_A1` + `Mix_A2`

5. **Scene Output**: `Blend_A2` output

---

### GEN_BUS_B Scene

**Purpose**: "Buildup/Drop" generator bus with intense, chaotic patterns.

**Structure**: Same as GEN_BUS_A, but with different shaders:
- `GLSL_RadialRings`
- `GLSL_PulseTunnel`
- `GLSL_Fractal`

Use globals:
- `GenB_Slot0_Weight`, `GenB_Slot1_Weight`, `GenB_Slot2_Weight`
- `GenIntensity` (shared with A)

---

### MASK_BUS Scene

**Purpose**: Apply masks and composite karaoke text over generator output.

```mermaid
flowchart TD
    subgraph MASK_SCENE["MASK_BUS Scene"]
        SCENE_IN["SceneInput_MainImage<br/>(from GEN_OUT)"] --> MASK_PROC["Mask Processing<br/>(optional multiply)"]
        
        SYPHON_K["SyphonClient<br/>(Karaoke Text)"] --> LUMA["LumaKey<br/>(optional)"]
        LUMA --> MIX_K["Mix_Karaoke<br/>Opacity: KaraokeOpacity"]
        
        MASK_PROC --> MIX_K
        MIX_K --> MASK_OUT["Scene Output<br/>(MASK_OUT)"]
    end
    
    KAR_OP["KaraokeOpacity"] -.-> MIX_K
    
    style SCENE_IN fill:#e1f5ff
    style SYPHON_K fill:#e1f5ff
    style LUMA fill:#fff3e0
    style MASK_PROC fill:#f3e5f5
    style MIX_K fill:#fff9c4
    style MASK_OUT fill:#e8f5e9
```

**Implementation**:

1. **Create Scene**: `MASK_BUS`

2. **Add SceneInput**:
   - Module: `SceneInput_MainImage`
   - This receives the generator output from main scene

3. **Add SyphonClient**:
   - Module: `SyphonClient`
   - Configure sender/server to your karaoke app

4. **Optional LumaKey**:
   - If karaoke is white text on black background
   - Adjust threshold so black becomes transparent

5. **Add Mask Processing** (optional):
   - Create mask generators (radial vignette, stripes, etc.)
   - Use `Multiply` blend to apply mask to main image
   - Control strength with `MaskAmount` global

6. **Add Mix_Karaoke**:
   - Input A: Masked main image
   - Input B: Karaoke (after LumaKey)
   - Opacity: Link to `KaraokeOpacity` global

7. **Scene Output**: `Mix_Karaoke` output

**Globals for MASK_BUS**:

#### KaraokeOpacityManual

**KaraokeOpacityManual** – Source: MIDI CC #21 (Strip 2 / Knob 2)

Modifiers:
1. **Smooth**: `0.3`

#### KaraokeOpacity (Derived)

**KaraokeOpacity** – Source: Expression-only

Modifiers:
1. **Expression**: `min(max(KaraokeOpacityManual * (0.5 + 0.5 * EnergySlow), 0), 1)`

**Effect**: Karaoke opacity reacts to manual control and song energy.

#### MaskAmountManual

**MaskAmountManual** – Source: MIDI CC #20 (Strip 2 / Knob 1)

Modifiers:
1. **Smooth**: `0.3`

#### MaskAmount (Derived)

**MaskAmount** – Source: Expression-only

Modifiers:
1. **Expression**: `MaskAmountManual * (0.5 + 0.5 * Buildup)`

**Effect**: Mask strength increases with buildup.

---

### FX_BUS Scene

**Purpose**: Global distortion, warp, and color processing.

```mermaid
flowchart TD
    subgraph FX_SCENE["FX_BUS Scene"]
        SCENE_IN_FX["SceneInput_Image<br/>(from MASK_OUT)"] --> WARP["GLSL_Warp<br/>Amount: FXWarp"]
        WARP --> COLOR["ColorCorrect<br/>Hue Shift: FXColorShift"]
        COLOR --> FX_OUT["Scene Output<br/>(FX_OUT)"]
    end
    
    FX_WARP_G["FXWarp"] -.-> WARP
    FX_COLOR_G["FXColorShift"] -.-> COLOR
    
    style SCENE_IN_FX fill:#e1f5ff
    style WARP fill:#fff9c4
    style COLOR fill:#fff9c4
    style FX_OUT fill:#e8f5e9
```

**Implementation**:

1. **Create Scene**: `FX_BUS`

2. **Add SceneInput**:
   - Module: `SceneInput_Image`

3. **Add GLSL_Warp** (distortion effect):
   - Connect `SceneInput_Image` → `GLSL_Warp`
   - Link warp amount parameter to `FXWarp` global

4. **Add ColorCorrect**:
   - Connect `GLSL_Warp` → `ColorCorrect`
   - Link hue/saturation parameters to `FXColorShift` global

5. **Scene Output**: `ColorCorrect` output

**Globals for FX_BUS**:

#### FXAmountManual

**FXAmountManual** – Source: MIDI CC #28 (Strip 3 / Knob 1)

Modifiers:
1. **Smooth**: `0.3`

#### FXAmount (Derived)

**FXAmount** – Source: Expression-only

Modifiers:
1. **Expression**: `FXAmountManual * (0.5 + 0.5 * EnergyFast) * (0.5 + 0.5 * Buildup) * (1 + 0.5 * Drop)`

**Effect**: FX intensity reacts to manual control, energy, buildup, and drop.

```mermaid
flowchart TD
    FX_MAN["FXAmountManual"] --> EXPR_FX["Expression:<br/>FXAmountManual × (0.5 + 0.5 × EnergyFast)<br/>× (0.5 + 0.5 × Buildup) × (1 + 0.5 × Drop)"]
    ENERGY_FX["EnergyFast"] --> EXPR_FX
    BUILDUP_FX["Buildup"] --> EXPR_FX
    DROP_FX["Drop"] --> EXPR_FX
    
    EXPR_FX --> FX_AMT["FXAmount<br/>(Range: 0–~3)"]
    
    style FX_MAN fill:#f3e5f5
    style ENERGY_FX fill:#f3e5f5
    style BUILDUP_FX fill:#f3e5f5
    style DROP_FX fill:#f3e5f5
    style EXPR_FX fill:#fff9c4
    style FX_AMT fill:#e8f5e9
```

#### FXWarpManual

**FXWarpManual** – Source: MIDI CC #29 (Strip 3 / Knob 2)

Modifiers:
1. **Smooth**: `0.3`

#### FXWarp (Derived)

**FXWarp** – Source: Expression-only

Modifiers:
1. **Expression**: `FXWarpManual * FXAmount`

#### FXColorShiftManual

**FXColorShiftManual** – Source: MIDI CC #30 (Strip 3 / Knob 3)

Modifiers:
1. **Smooth**: `0.3`

#### FXColorShift (Derived)

**FXColorShift** – Source: Expression-only

Modifiers:
1. **Expression**: `FXColorShiftManual * (0.5 + 0.5 * EnergySlow)`

---

## Karaoke Integration

The karaoke text overlay is integrated into the `MASK_BUS` scene via Syphon.

### Karaoke App Setup

Use any app that can output text via Syphon, such as:
- VDMX
- Processing sketch with text rendering
- MadMapper with text module
- After Effects with Syphon plugin

**Recommended Format**:
- White text on black background
- Full HD resolution (1920×1080)
- Large, bold font for readability

### MASK_BUS Integration

In the `MASK_BUS` scene:

1. **SyphonClient** receives karaoke feed
2. **LumaKey** (optional) makes black background transparent
3. **Mix** composites karaoke over generator image
4. **KaraokeOpacity** controls visibility

**Key Feature**: Karaoke opacity is audio-reactive:

```
KaraokeOpacity = KaraokeOpacityManual * (0.5 + 0.5 * EnergySlow)
```

**Effect**: Text becomes more visible during high-energy sections.

### Alternative: Karaoke as Mask

To make visuals visible **only inside the text**:

1. Use karaoke feed as a mask texture
2. Apply via `Multiply` blend instead of overlay
3. Result: Generators visible only where text exists

---

## Main Scene Assembly

The main scene connects all buses and applies master controls.

```mermaid
flowchart TD
    subgraph MAIN_SCENE["MAIN Scene"]
        GEN_A_MOD["Scene: GEN_BUS_A"] --> MIX_GEN["Mix_GenBanks<br/>Mix: GenBankMix"]
        GEN_B_MOD["Scene: GEN_BUS_B"] --> MIX_GEN
        MIX_GEN --> GEN_OUT_INT["GEN_OUT"]
        
        GEN_OUT_INT --> MASK_MOD["Scene: MASK_BUS<br/>(SceneInput = GEN_OUT)"]
        MASK_MOD --> MASK_OUT_INT["MASK_OUT"]
        
        MASK_OUT_INT --> FX_MOD["Scene: FX_BUS<br/>(SceneInput = MASK_OUT)"]
        FX_MOD --> FX_OUT_INT["FX_OUT"]
        
        FX_OUT_INT --> MASTER_MIX_MOD["Master_Mix<br/>Opacity: MasterOpacity"]
        MASTER_MIX_MOD --> MAGIC_OUT["Magic Output"]
    end
    
    GENBANKMIX_G["GenBankMix"] -.-> MIX_GEN
    MASTER_OP_G["MasterOpacity"] -.-> MASTER_MIX_MOD
    
    style GEN_A_MOD fill:#e1f5ff
    style GEN_B_MOD fill:#e1f5ff
    style MASK_MOD fill:#e1f5ff
    style FX_MOD fill:#e1f5ff
    style MIX_GEN fill:#fff9c4
    style MASTER_MIX_MOD fill:#fff9c4
    style MAGIC_OUT fill:#e8f5e9
```

**Implementation**:

1. **Add Scene Modules**:
   - `Scene: GEN_BUS_A` → GenA module
   - `Scene: GEN_BUS_B` → GenB module
   - `Scene: MASK_BUS` → MaskBus module
   - `Scene: FX_BUS` → FxBus module

2. **Generator Bank Mix**:
   - Add `Mix` module: `Mix_GenBanks`
   - Input A: GenA output
   - Input B: GenB output
   - Mix parameter: Link to `GenBankMix` global
   - Output: `GEN_OUT`

3. **Connect to Mask Bus**:
   - Connect `GEN_OUT` to `MaskBus.SceneInput_MainImage`
   - MaskBus output: `MASK_OUT`

4. **Connect to FX Bus**:
   - Connect `MASK_OUT` to `FxBus.SceneInput_Image`
   - FxBus output: `FX_OUT`

5. **Master Mix**:
   - Add `Mix` or `Multiply` module: `Master_Mix`
   - Input: `FX_OUT`
   - Opacity parameter: Link to `MasterOpacity` global

6. **Connect to Magic Output**:
   - Connect `Master_Mix` to Magic output module

**MasterOpacity Global**:

**MasterOpacity** – Source: Expression-only

Modifiers:
1. **Expression**: `min(max(MasterIntensity * (1 - Blackout), 0), 1)`

**Effect**:
- When `Blackout = 1`, `MasterOpacity = 0` (screen goes black)
- When `Blackout = 0`, `MasterOpacity = MasterIntensity` (normal operation)

```mermaid
flowchart TD
    MASTER_INT_IN["MasterIntensity"] --> EXPR_MO["Expression:<br/>min(max(MasterIntensity × (1 - Blackout), 0), 1)"]
    BLACKOUT_IN["Blackout"] --> EXPR_MO
    EXPR_MO --> MASTER_OP["MasterOpacity<br/>(Range: 0–1)"]
    
    style MASTER_INT_IN fill:#f3e5f5
    style BLACKOUT_IN fill:#f3e5f5
    style EXPR_MO fill:#fff9c4
    style MASTER_OP fill:#e8f5e9
```

---

## Quick Reference

### Complete Global List

| Global Name | Source | Type | Range | Purpose |
|-------------|--------|------|-------|---------|
| `Multi` | MIDI CC #24 | Derived | 0.3–2.0 | Audio sensitivity |
| `Bass` | Audio 20–120 Hz | Audio | 0–1 | Kick/bass detection |
| `LowMid` | Audio 120–350 Hz | Audio | 0–1 | Drum body |
| `Highs` | Audio 2k–6k Hz | Audio | 0–1 | Hi-hats, brightness |
| `EnergyFast` | Expression | Derived | 0–1 | Instant intensity |
| `EnergySlow` | EnergyFast avg | Derived | 0–1 | Averaged intensity |
| `KickRaw` | Audio 40–120 Hz | Audio | 0–1 | Raw kick transient |
| `KickEnv` | KickRaw | Derived | 0–1 | Kick envelope |
| `KickPulse` | KickEnv | Derived | 0/1 | Binary kick trigger |
| `Beat4` | KickPulse | Derived | 0–3 | 4-beat counter |
| `MasterIntensity` | MIDI CC #27 | Manual | 0–1 | Master intensity |
| `Buildup` | MIDI CC #25 | Manual | 0–1 | Buildup level |
| `Drop` | MIDI Note 27 | Toggle | 0/1 | Drop toggle |
| `DropPulse` | MIDI Note 27 | Pulse | 0/1 | Drop spike |
| `Blackout` | MIDI Note 43 | Toggle | 0/1 | Emergency blackout |
| `GenBankManual` | MIDI CC #16 | Manual | 0–1 | A/B manual mix |
| `GenBankMix` | Expression | Derived | 0–1 | A/B final mix |
| `GenIntensityManual` | MIDI CC #19 | Manual | 0–1 | Gen manual intensity |
| `GenIntensity` | Expression | Derived | 0–2 | Gen final intensity |
| `GenA_Index` | Expression | Derived | 0–2 | Gen A active slot |
| `GenB_Index` | Expression | Derived | 0–2 | Gen B active slot |
| `MaskAmountManual` | MIDI CC #20 | Manual | 0–1 | Mask manual strength |
| `MaskAmount` | Expression | Derived | 0–1 | Mask final strength |
| `KaraokeOpacityManual` | MIDI CC #21 | Manual | 0–1 | Karaoke manual opacity |
| `KaraokeOpacity` | Expression | Derived | 0–1 | Karaoke final opacity |
| `FXAmountManual` | MIDI CC #28 | Manual | 0–1 | FX manual amount |
| `FXAmount` | Expression | Derived | 0–~3 | FX final amount |
| `FXWarpManual` | MIDI CC #29 | Manual | 0–1 | Warp manual amount |
| `FXWarp` | Expression | Derived | 0–~3 | Warp final amount |
| `FXColorShiftManual` | MIDI CC #30 | Manual | 0–1 | Color shift manual |
| `FXColorShift` | Expression | Derived | 0–1 | Color shift final |
| `MasterOpacity` | Expression | Derived | 0–1 | Master output opacity |

---

### Expression Quick Reference

**Audio Bands**:
```
min(max(x * Multi * 2.0, 0), 1)
```

**Energy Fast**:
```
Bass * 0.5 + LowMid * 0.3 + Highs * 0.2
```

**Energy Slow**:
```
Average(EnergyFast, 4.0)
```

**GenBankMix**:
```
min(max(0.5 * Buildup + 0.5 * GenBankManual + Drop * (1 - Buildup), 0), 1)
```

**GenIntensity**:
```
min(max(GenIntensityManual * (0.6 + 0.4 * EnergyFast) * (0.6 + 0.4 * Buildup) * (1 + 0.7 * Drop), 0), 2)
```

**FXAmount**:
```
FXAmountManual * (0.5 + 0.5 * EnergyFast) * (0.5 + 0.5 * Buildup) * (1 + 0.5 * Drop)
```

**MasterOpacity**:
```
min(max(MasterIntensity * (1 - Blackout), 0), 1)
```

---

### Scene Signal Flow

```
GEN_BUS_A ──┐
            ├─→ Mix(GenBankMix) → GEN_OUT
GEN_BUS_B ──┘
                     ↓
              MASK_BUS(GEN_OUT + Karaoke) → MASK_OUT
                     ↓
              FX_BUS(Warp + Color) → FX_OUT
                     ↓
              Master_Mix(MasterOpacity) → Magic Output
```

---

### Tips for Live Performance

1. **Start with defaults**:
   - `GenBankMix = 0` (Bus A)
   - `Buildup = 0`
   - `Drop = 0`
   - `MasterIntensity = 0.7`

2. **During verse**:
   - Keep `Buildup` low (0–0.3)
   - `GenBankMix` stays near A
   - Adjust `GenIntensity` for subtle movement

3. **During buildup**:
   - Gradually increase `Buildup` to 1.0
   - `GenBankMix` automatically crossfades to B
   - `FXAmount` increases naturally

4. **On drop**:
   - Press `Drop` button (toggles to 1)
   - `GenBankMix` forced to B
   - `GenIntensity` and `FXAmount` spike
   - Consider randomizing generators

5. **Emergency controls**:
   - `Blackout` button for instant screen blackout
   - `MasterIntensity` fader for quick dimming

---

## Related Documentation

- [Magic Music Visuals Guide](magic-music-visuals-guide.md) - Core concepts, modules, audio reactivity
- [Live VJ Setup Guide](live-vj-setup-guide.md) - Full rig setup with Syphon, BlackHole, MIDI
- [MIDI Controller Setup](midi-controller-setup.md) - MIDImix and Launchpad configuration

---

## Credits

This pipeline architecture is designed for live VJ performance with Magic Music Visuals, emphasizing:
- Modular bus structure for clean signal flow
- Audio-reactive controls with manual overrides
- Smooth crossfades between song stages (intro, verse, buildup, drop)
- Karaoke/text overlay integration via Syphon
- Emergency controls for live safety

Adapt CC numbers, expressions, and shader choices to your specific setup and musical style.

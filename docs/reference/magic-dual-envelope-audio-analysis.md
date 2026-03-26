# Magic Music Visuals Audio Analysis — Dual Envelope System Design

## Executive Summary

Magic Music Visuals provides a modular audio analysis system consisting of **Audio Features** (Volume, Freq. Range, Best Pitch, Tone), **Modifiers** (Peak, Smooth, and raw pass-through), and **Global Parameters** that can be shared across scenes and output via **OSCSender** modules.

The dual-envelope system uses **Magic Globals as the single source of truth** for all audio analysis. Each envelope (Low and High) is defined by a frequency boundary and produces 3 values (Peak, Average, Raw) — totaling **6 output values**. The frequency boundaries are independent and **can overlap** (e.g., Low boundary at 5kHz, High boundary at 3kHz). All parameters (Gain, frequencies, attack/release/smoothing) are configurable Globals. ISF shaders are **consumers** of these values, not producers.

---

## Table of Contents

1. [Magic Audio Feature System](#1-magic-audio-feature-system)
2. [Modifier System — Peak, Average, Raw](#2-modifier-system--peak-average-raw)
3. [Global Parameters Architecture](#3-global-parameters-architecture)
4. [OSC Output via OSCSender](#4-osc-output-via-oscsender)
5. [ISF Reference — Audio Input Types](#5-isf-reference--audio-input-types)
6. [Complete Wiring Plan](#6-complete-wiring-plan)
7. [Confidence Assessment](#7-confidence-assessment)

---

## 1. Magic Audio Feature System

Magic Music Visuals exposes audio data to modules via **Audio Features**, all scaled to the range **0 to 1**[^1].

### Available Audio Features

| Feature | Description | Output Range |
|---------|-------------|--------------|
| **Volume** | Overall amplitude of the audio signal. Silence = 0, max = 1 | 0–1 |
| **Freq. Range** | Volume of a specific frequency band. 5 presets + Custom Freq. | 0–1 |
| **Best Pitch** | Monophonic pitch detection, 40Hz–2560Hz (6 octaves, log-scaled) | 0–1 |
| **Tone** | High-frequency content / "brightness", 40Hz–20480Hz (9 octaves, log-scaled) | 0–1 |

### Freq. Range Presets[^1]

| Preset | Frequency Range |
|--------|----------------|
| Band 1 | 20–80 Hz |
| Band 2 | 80–320 Hz |
| Band 3 | 320–1.2k Hz |
| Band 4 | 1.2k–5k Hz |
| Band 5 | 5k–20k Hz |
| **Custom Freq.** | Any arbitrary low/high cutoff frequencies |

The **Custom Freq.** option is exactly what the envelopes use — user-defined frequency boundaries for the Low Envelope (~300 Hz) and High Envelope (~7 kHz).

**Important: The two envelopes are independent.** Each has its own frequency boundary. The Low Envelope analyzes frequencies from 20 Hz up to its boundary; the High Envelope analyzes frequencies from its boundary up to 20 kHz. The boundaries **can overlap** — e.g., Low boundary at 5 kHz and High boundary at 3 kHz means both envelopes cover the 3–5 kHz range.

---

## 2. Modifier System — Peak, Average, Raw

Magic's **Modifiers** are chainable math operations applied to any audio feature value[^2]. The three styles in the Audio Settings panel map to:

### Peak Modifier[^2]

> "Simulates the behavior of a VU-meter: if the current input value is greater than the previous input value, it will simply pass through. If the current input value is less than the previous input value, it will be decreased by the smoothing factor specified by the modifier parameter. 1 is maximum smoothing, and 0 is no smoothing."

**Behavior:** Fast attack (instant pass-through on rise), configurable release/decay.

### Smooth Modifier (→ "Average" style)[^2]

> "Averages the input value with previous input values, making the output value less 'jerky'. A modifier parameter of 1 results in maximum smoothing, while a parameter of 0 does no smoothing at all."

**Behavior:** Exponential moving average (EMA). More smoothing = less responsive.

### Raw (No Modifier)

Simply the unprocessed audio feature value — no smoothing, no peak-holding.

### Modifier Math Summary

| Style | Algorithm | Parameters |
|-------|-----------|------------|
| **Peak** | `if (current > prev) output = current; else output = prev * decay` | decay factor (0–1) |
| **Average** | EMA: `output = mix(prev, current, smoothFactor)` | smoothing factor (0–1) |
| **Raw** | `output = current` | none |

---

## 3. Global Parameters — The Single Source of Truth

Global Parameters in Magic are **named values** that can be linked to any audio source + feature + modifiers, then referenced across all scenes and modules[^3].

### Key Properties[^3]

- Created via **Scene > Show/Hide Globals Panel** (Shift+Ctrl+L / Shift+Cmd+L)
- Can be linked to audio sources with features and modifiers, just like module parameters
- Accessible in any module parameter (including ISF shader parameters) by selecting **"Globals"** as the source
- Can be used as variables in **Expression** modifiers (no spaces in names)
- No limit on the number of globals; shared across all scenes
- Names must not be "x" or "y" (reserved)

### Globals are the only values you can actually use as inputs

ISF shaders **cannot feed computed values back** into Magic — they are one-way (parameters in → pixels out). Therefore:
- **Globals do all the analysis** (Audio Source → Custom Freq. → Peak/Smooth modifiers)
- **ISF shaders are consumers** — they receive the 6 computed globals as float inputs and visualize them
- **OSCSender modules are consumers** — they send the 6 globals over the network

### Complete Global Parameter List

**Configuration Globals (you set these manually or via MIDI/OSC):**

| Global Name | Purpose | Default | Range |
|-------------|---------|---------|-------|
| `Gain` | Audio input gain | 1.0 | 0.0–4.0 |
| `LowFreq` | Low envelope frequency boundary | 200 Hz | 20–20000 Hz |
| `HighFreq` | High envelope frequency boundary | 6000 Hz | 20–20000 Hz |
| `LowPeakRelease` | Low Peak decay speed | 0.7 | 0.0–1.0 |
| `LowSmooth` | Low Average smoothing factor | 0.5 | 0.0–1.0 |
| `HighPeakRelease` | High Peak decay speed | 0.7 | 0.0–1.0 |
| `HighSmooth` | High Average smoothing factor | 0.5 | 0.0–1.0 |

### EDM / Dance Music Defaults

| Genre | Low Cutoff | High Cutoff | Rationale |
|-------|-----------|-------------|-----------|
| **Techno** | 150 Hz | 6000 Hz | Tight kick focus, metallic hats |
| **Bass House** | 250 Hz | 5000 Hz | Wider for bass wobbles (~250 Hz) |
| **Melodic Techno** | 200 Hz | 7000 Hz | More bass warmth, airy pads |
| **Hard Techno** | 120 Hz | 8000 Hz | Sub-only kick, aggressive highs |

- **Low at ~200 Hz** is the safest general EDM default — captures kick (40–60 Hz fundamental) + sub-bass without mid-range mud
- **High at ~6000 Hz** catches hi-hats and percussion without vocal/synth bleed
- Lower the Low cutoff (e.g., 100 Hz) for punchier, sub-only kick response
- Raise the High cutoff (e.g., 10 kHz) to isolate only the brightest transients

### MIDI Control of Frequency Cutoffs

The `LowFreq` and `HighFreq` globals can be controlled live via MIDI knobs/faders:

1. **Right-click** the `LowFreq` global's selection tab → **Learn Param** → turn your MIDI knob
2. Magic auto-detects the CC message and assigns it
3. Set **Param Range** via the modifier menu to scale the 0–1 MIDI value to your desired Hz range

**Example MIDI mapping with Expression modifier:**

For `LowFreq`, add an **Expression** modifier with the formula:
```
20 + x * 1980
```
This maps MIDI CC 0–1 → 20–2000 Hz. For `HighFreq`:
```
500 + x * 14500
```
Maps MIDI CC 0–1 → 500–15000 Hz.

Alternatively, use a **Scale** modifier (param = 2000) + **Offset** modifier (param = 20) to achieve `20 + x * 2000`.

**Tip:** Link both cutoffs to the same MIDI controller with inverted ranges for a single-knob "crossover frequency" control — turn right = Low goes up while High comes down.

**Output Globals (computed by Magic from audio, used as inputs everywhere):**

| Global Name | Source | Feature | Modifier | Description |
|-------------|--------|---------|----------|-------------|
| `LowPeak` | Audio | Custom Freq. (20 Hz – `LowFreq`) | **Peak** (param = `LowPeakRelease`) | Low band peak-hold |
| `LowAvg` | Audio | Custom Freq. (20 Hz – `LowFreq`) | **Smooth** (param = `LowSmooth`) | Low band smoothed average |
| `LowRaw` | Audio | Custom Freq. (20 Hz – `LowFreq`) | *(none)* | Low band raw value |
| `HighPeak` | Audio | Custom Freq. (`HighFreq` – 20k Hz) | **Peak** (param = `HighPeakRelease`) | High band peak-hold |
| `HighAvg` | Audio | Custom Freq. (`HighFreq` – 20k Hz) | **Smooth** (param = `HighSmooth`) | High band smoothed average |
| `HighRaw` | Audio | Custom Freq. (`HighFreq` – 20k Hz) | *(none)* | High band raw value |

**Total: 7 configuration globals + 6 output globals = 13 globals.**

Since `LowFreq` and `HighFreq` are independent, you can set `LowFreq` = 5000 and `HighFreq` = 3000 — the bands will overlap and that's fine.

---

## 4. OSC Output via OSCSender

Magic sends values to other applications via the **OSCSender module**[^4]:

| Parameter | Description |
|-----------|-------------|
| **IP Addr.** | Destination IP address (one per project) |
| **Port** | Destination port (one per project) |
| **Message** | OSC address path (e.g., `/audio/low/peak`) |
| **Value** | The value to send — link this to a Global |

### OSC Address Layout

```
/audio/gain         → Global Gain
/audio/low/peak     → Global LowPeak
/audio/low/avg      → Global LowAvg
/audio/low/raw      → Global LowRaw
/audio/high/peak    → Global HighPeak
/audio/high/avg     → Global HighAvg
/audio/high/raw     → Global HighRaw
```

Create **6 OSCSender modules** (or more if you also want to send the config globals). Each module's **Value** parameter is linked to **Globals** source, selecting the corresponding global feature.

---

## 5. ISF Reference — Audio Input Types

ISF provides two audio input types[^5][^6] for shaders that need direct FFT access (e.g., spectrum visualizers). For the dual-envelope system, the ISF shader does **not** need these — it receives pre-computed values from Globals instead.

### `audioFFT` Type (reference only)
- FFT frequency data as a texture
- Width = number of frequency bins, Height = number of channels
- Use `MAX` key to control bin count
- First bin = lowest frequency, last bin = Nyquist frequency

---

## 6. Complete Wiring Plan

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Magic Music Visuals                          │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  AUDIO SOURCE                             │   │
│  │  (External Input / MacBook Mic / Audio File)              │   │
│  │  Gain applied via Audio Gain setting                      │   │
│  └────────┬─────────────────────────────────┬────────────────┘   │
│           │                                 │                    │
│  ┌────────▼──────────────────┐   ┌──────────▼────────────────┐  │
│  │    LOW ENVELOPE           │   │    HIGH ENVELOPE           │  │
│  │  Custom Freq: 20–LowFreq │   │  Custom Freq: HighFreq–20k│  │
│  │                           │   │                            │  │
│  │  ┌─ LowRaw  (no mod)     │   │  ┌─ HighRaw  (no mod)     │  │
│  │  ├─ LowPeak (Peak mod)   │   │  ├─ HighPeak (Peak mod)   │  │
│  │  └─ LowAvg  (Smooth mod) │   │  └─ HighAvg  (Smooth mod) │  │
│  └────────┬──────────────────┘   └──────────┬────────────────┘  │
│           │                                 │                    │
│  ┌────────▼─────────────────────────────────▼────────────────┐  │
│  │              6 OUTPUT GLOBALS (0–1 each)                   │  │
│  │  LowRaw, LowPeak, LowAvg, HighRaw, HighPeak, HighAvg     │  │
│  └──┬───────────────────────────────────────────────────┬────┘  │
│     │                                                   │       │
│  ┌──▼───────────────────────┐   ┌───────────────────────▼────┐  │
│  │  ISF SHADER (consumer)   │   │  OSCSender × 6 (consumer)  │  │
│  │  Receives 6 globals as   │   │  Sends globals over        │  │
│  │  float inputs → draws    │   │  network to other apps     │  │
│  │  visual meter bars       │   │                             │  │
│  └──────────────────────────┘   └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Step-by-Step Setup

#### Step 1: Configure Audio Gain
Right-click your audio source in the Input Sources Window → Show Gain → adjust as needed.

#### Step 2: Create Configuration Globals
Open **Scene > Show/Hide Globals Panel** (Shift+Ctrl+L / Shift+Cmd+L):

| Global | Initial Value | Notes |
|--------|---------------|-------|
| `LowFreq` | 200 | Hz — adjustable, range 20–20000. ~200 Hz = kick + sub for EDM |
| `HighFreq` | 6000 | Hz — adjustable, range 20–20000. ~6 kHz = hats + percussion for EDM |
| `LowPeakRelease` | 0.7 | Peak modifier decay (0=instant, 1=max hold) |
| `LowSmooth` | 0.5 | Smooth modifier factor (0=raw, 1=max smooth) |
| `HighPeakRelease` | 0.7 | Peak modifier decay |
| `HighSmooth` | 0.5 | Smooth modifier factor |

#### Step 3: Create 6 Output Globals

| Global | Source | Feature | Modifier |
|--------|--------|---------|----------|
| `LowRaw` | Audio Source | Custom Freq. (20 – `LowFreq`) | *(none)* |
| `LowPeak` | Audio Source | Custom Freq. (20 – `LowFreq`) | Peak (param = 0.7) |
| `LowAvg` | Audio Source | Custom Freq. (20 – `LowFreq`) | Smooth (param = 0.5) |
| `HighRaw` | Audio Source | Custom Freq. (`HighFreq` – 20000) | *(none)* |
| `HighPeak` | Audio Source | Custom Freq. (`HighFreq` – 20000) | Peak (param = 0.7) |
| `HighAvg` | Audio Source | Custom Freq. (`HighFreq` – 20000) | Smooth (param = 0.5) |

#### Step 4: Find Good Cutoff Values with the Spectrum Shader

Load **`magic/DualEnvelopeSpectrum.fs`** via ISFShader module. Play your music and drag the `lowFreq` / `highFreq` sliders while watching the spectrum:

- **Blue region** = frequencies the Low Envelope captures (20 Hz → cutoff)
- **Orange region** = frequencies the High Envelope captures (cutoff → 20 kHz)
- **Grey region** = frequencies neither envelope captures
- **Purple blend** = overlap zone when Low boundary > High boundary
- **Vertical lines** = the cutoff positions
- **Tick marks** at bottom = 100 Hz, 1 kHz, 10 kHz reference points

Once you've found values that isolate kicks/bass vs. hats/cymbals for your tracks, apply those values to the `LowFreq` and `HighFreq` Globals.

**Tip:** Link the ISF shader's `lowFreq`/`highFreq` parameters to the same Globals so the spectrum view always matches the actual analysis cutoffs.

#### Step 5: Monitor Envelope Values with the Meters Shader

Load **`magic/DualEnvelopeMeters.fs`** via ISFShader module. Link each of its 6 float inputs to the corresponding output Global:

| ISF Input | → Global |
|-----------|----------|
| `lowRaw` | `LowRaw` |
| `lowAvg` | `LowAvg` |
| `lowPeak` | `LowPeak` |
| `highRaw` | `HighRaw` |
| `highAvg` | `HighAvg` |
| `highPeak` | `HighPeak` |

This shows the **actual computed Global values** as 6 horizontal bars (3 blue = Low, 3 orange = High).

#### Step 6: Add OSCSender Modules

#### Step 6: Add OSCSender Modules

Create 6 OSCSender modules. Set IP/Port, then for each:
- **Message** = `/audio/low/peak` (etc.)
- **Value** = link to Globals → `LowPeak` (etc.)

### ISF Shader Files

| File | Purpose | Inputs |
|------|---------|--------|
| `magic/DualEnvelopeSpectrum.fs` | FFT spectrum with cutoff lines — for finding good frequency values | `audioFFT` + `lowFreq` + `highFreq` |
| `magic/DualEnvelopeMeters.fs` | 6 bar meters — for monitoring actual Global values | 6 floats linked to output Globals |

---

## 7. Confidence Assessment

### High Confidence ✅
- Magic Audio Features (Volume, Freq. Range, Best Pitch, Tone) — documented in official User Guide[^1]
- Modifier system (Peak, Smooth, Average) — documented in official User Guide[^2]
- Global Parameters architecture — documented in official User Guide[^3]
- OSCSender module behavior — documented in official User Guide[^4]
- ISF `audio` and `audioFFT` input types — documented in ISF specification[^5][^6]
- Persistent buffer pattern for temporal smoothing — verified in existing shaders in this repo[^7]

### Medium Confidence ⚠️
- The exact Audio Settings panel UI shown in the image may be from a newer/beta version of Magic not covered in the current public User Guide (the guide doesn't mention "Low Envelope"/"High Envelope" as a built-in feature)
- The Nyquist frequency assumption of 22050 Hz (standard for 44100 Hz sample rate) — actual value depends on Magic's audio engine configuration
- Attack/Release coefficient formula `1 - exp(-dt/tau)` is standard DSP but the exact implementation in Magic may differ

### Inferred 🔍
- The ISF shader cannot feed computed values back into Magic globals — this is a limitation of the ISF specification (shaders are one-way: parameters in, pixels out)
- The image appears to show a newer Magic feature (Audio Settings with envelopes) that may handle the analysis natively, reducing the need for an ISF-based solution

---

## Footnotes

[^1]: Magic Music Visuals User Guide — Audio Features section. Source: `https://magicmusicvisuals.com/downloads/Magic_UsersGuide.html#AudioFeatures` (accessed via Playwright browser)

[^2]: Magic Music Visuals User Guide — Modifiers section, specifically the Peak and Smooth modifier descriptions. Source: `https://magicmusicvisuals.com/downloads/Magic_UsersGuide.html#AudioModifiers`

[^3]: Magic Music Visuals User Guide — Global Parameters section. Source: `https://magicmusicvisuals.com/downloads/Magic_UsersGuide.html#GlobalParameters`

[^4]: Magic Music Visuals User Guide — OSCSender module section. Source: `https://magicmusicvisuals.com/downloads/Magic_UsersGuide.html#OSCSender`

[^5]: ISF Documentation — Audio Visualizers in ISF. Source: `https://docs.isf.video/primer_chapter_8.html`

[^6]: ISF JSON Reference — audio and audioFFT input types. Source: `https://docs.isf.video/ref_json`

[^7]: Existing audio-reactive ISF shader in this repository using persistent buffers and audioFFT input. Source: `magic/ISF-bareimage/Release.4/IM-YONIM-TunnelFix-multipath-audioreactive-FINAL.fs` (lines 79-117 for JSON, lines 250-267 for audio buffer pattern)

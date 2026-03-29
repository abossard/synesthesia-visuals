# Quickstart: Magic Music Visuals Audio → OSC → QLC+ Dimmer Control

## Overview

Magic Music Visuals analyzes live audio input, computes envelope values (peak, average, raw) for configurable frequency bands, exposes them as Globals, and sends those values via OSC to QLC+ on localhost. QLC+ receives the OSC messages and maps them to DMX channels, letting you control dimmers (or any DMX fixture) in real time from music.

## Prerequisites

- **Magic Music Visuals** (Performer edition — required for OSC output)
- **QLC+ v4 or v5** installed ([qlcplus.org](https://www.qlcplus.org/))
- **Audio input** — mic, BlackHole loopback, or an audio file
- *(Optional)* **Enttec USB Pro** or similar USB-DMX interface (you can test with QLC+'s virtual console without hardware)

---

## Step 1: Magic Audio Setup

1. Open the **Input Sources Window**: `Shift+Ctrl+I` (Windows) / `Shift+Cmd+I` (macOS)
2. Select your audio device (mic, BlackHole, etc.)
3. If the signal is too quiet or too hot, right-click the source → **Show Gain** and adjust

---

## Step 2: Create Globals for Audio Analysis

Open the Globals panel: **Scene → Show/Hide Globals Panel** (`Shift+Ctrl+L` / `Shift+Cmd+L`)

### Configuration globals

| Global     | Value | Notes                                      |
|------------|-------|----------------------------------------------|
| `LowFreq`  | 200   | Hz, adjustable. Kick+sub boundary for EDM   |
| `HighFreq` | 6000  | Hz, adjustable. Hi-hat boundary for EDM     |

### Output globals

Link each to **Audio Source → Custom Freq.** with the ranges and modifiers shown:

| Global     | Source       | Feature                         | Modifier     |
|------------|--------------|----------------------------------|--------------|
| `LowRaw`   | Audio Source | Custom Freq. (20–200 Hz)        | *(none)*     |
| `LowPeak`  | Audio Source | Custom Freq. (20–200 Hz)        | Peak (0.7)   |
| `LowAvg`   | Audio Source | Custom Freq. (20–200 Hz)        | Smooth (0.5) |
| `HighRaw`  | Audio Source | Custom Freq. (6000–20000 Hz)    | *(none)*     |
| `HighPeak` | Audio Source | Custom Freq. (6000–20000 Hz)    | Peak (0.7)   |
| `HighAvg`  | Audio Source | Custom Freq. (6000–20000 Hz)    | Smooth (0.5) |

> **Tip:** Load `magic/DualEnvelopeSpectrum.fs` via an ISFShader module to visually find the best cutoff values for your music. Blue = low region, orange = high region. Drag the sliders while music plays. Use `magic/AudioFeaturesMeters.fs` to visualize the extended audio features (energy, tone, mid, kick).

---

## Step 3: Add OSCSender Modules

### Quick test — one channel

Create a single **OSCSender** module:

| Setting | Value                    |
|---------|--------------------------|
| IP      | `127.0.0.1`             |
| Port    | `7700`                   |
| Message | `/audio/low/peak`        |
| Value   | Link to Globals → `LowPeak` |

This sends the Low Peak value to QLC+ via OSC. QLC+ accepts any OSC path as input and maps it internally via a 16-bit hash — you'll map this to a channel using the Input Profile Editor wizard (see Step 5).

### Full setup — six channels

Create six OSCSender modules:

| Module | Message            | Global     |
|--------|-------------------|------------|
| 1      | `/audio/low/peak`  | `LowPeak`  |
| 2      | `/audio/low/avg`   | `LowAvg`   |
| 3      | `/audio/low/raw`   | `LowRaw`   |
| 4      | `/audio/high/peak` | `HighPeak`  |
| 5      | `/audio/high/avg`  | `HighAvg`   |
| 6      | `/audio/high/raw`  | `HighRaw`   |

### Extended setup — 15 channels (full audio feature set)

For richer lighting control, add 9 more OSCSender modules covering energy, tone, mid-band, and kick detection:

| Module | Message               | Global         |
|--------|-----------------------|----------------|
| 7      | `/audio/energy/raw`   | `EnergyRaw`    |
| 8      | `/audio/energy/smooth` | `EnergySmooth` |
| 9      | `/audio/energy/peak`  | `EnergyPeak`   |
| 10     | `/audio/tone/raw`     | `ToneRaw`      |
| 11     | `/audio/tone/smooth`  | `ToneSmooth`   |
| 12     | `/audio/mid/raw`      | `MidRaw`       |
| 13     | `/audio/mid/smooth`   | `MidSmooth`    |
| 14     | `/audio/mid/peak`     | `MidPeak`      |
| 15     | `/audio/kick/onset`   | `KickOnset`    |

> **Note:** QLC+ OSC input accepts **any** OSC path — it does not require the `/universe/dmx/channel` format (that format is only used for QLC+ OSC *output*). Use descriptive paths like `/audio/low/peak` so your OSC traffic is self-documenting.

---

## Step 4: QLC+ OSC Input

1. Open **QLC+**
2. Go to the **Inputs/Outputs** tab (bottom of the window)
3. For **Universe 1**, check the **Input** box next to `OSC 127.0.0.1`
4. The default input port is **7700** — this matches what Magic is sending to

> **How QLC+ OSC input works:** QLC+ accepts *any* OSC path as input (e.g., `/audio/low/peak`). Each path is internally hashed to a 16-bit channel number. The `/universe/dmx/channel` format is only used for QLC+ OSC *output*, not input.

---

## Step 5: Create an Input Profile (auto-detect)

1. Go to the **Input/Output Manager** → click the **Input Profiles** tab
2. Click **Add** → create a new profile (type: **OSC**)
3. Click the **Wizard** button (auto-detect mode)
4. Play music in Magic so it sends OSC messages on port 7700
5. QLC+ auto-detects the 6 incoming OSC paths (`/audio/low/peak`, `/audio/low/avg`, etc.)
6. Each detected path gets assigned to an internal channel number
7. Click **OK** to save the profile

> **Alternative:** Use the **Channel Calculator** in the OSC plugin configuration to manually compute the internal channel number for a given OSC path.

---

## Step 6: Virtual Console Test

1. Switch to the **Virtual Console** tab
2. Add a **Slider** widget
3. Right-click the slider → **Properties** → set it to control your dimmer channel
4. In the **Input** tab of the slider properties, select the input profile channel that corresponds to `/audio/low/peak`
5. Play music — the slider should follow the kick drum envelope

---

## Step 7: Play Music and Watch the Dimmer! 🎉

- Play music through your audio source
- The `LowPeak` global responds to kick drums
- QLC+ receives the value via OSC
- The dimmer goes up on every kick!

---

## Tuning Tips

- **Dimmer too jumpy?** Use `LowAvg` instead of `LowPeak` (smoother response).
- **Not reactive enough?** Lower the Low cutoff frequency (e.g., 100 Hz = sub-only).
- **Want hi-hat control too?** Use `HighPeak` on a second channel.
- **MIDI control of cutoffs:** Right-click a Global → **Learn Param** → turn a MIDI knob. Use an Expression modifier `20 + x * 1980` to map a 0–1 CC value to the 20–2000 Hz range.

---

## Reference

- [Magic User Guide](https://magicmusicvisuals.com/downloads/Magic_UsersGuide.html)
- [QLC+ OSC Plugin Docs (v4)](https://docs.qlcplus.org/v4/plugins/osc) · [v5](https://docs.qlcplus.org/v5/plugins/osc)
- [QLC+ v4 I/O Basics (video)](https://www.youtube.com/watch?v=I9bccwcYQpM) · [v5 (video)](https://www.youtube.com/watch?v=nkPnY70_CEs)
- [Dual Envelope Audio Analysis](../reference/magic-dual-envelope-audio-analysis.md)
- Spectrum analyzer shader: `magic/DualEnvelopeSpectrum.fs`
- Envelope meters shader: `magic/DualEnvelopeMeters.fs`
- Audio features meters shader: `magic/AudioFeaturesMeters.fs`

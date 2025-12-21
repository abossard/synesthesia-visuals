# VJ / Live-Performance Stack: VJUniverse + Synesthesia + Magic (with Python OSC Hub)

This is the current (2025) “single Processing app” live rig for macOS.

## Overview (what runs)

- **Processing**: only **VJUniverse** (multiple panels/tiles + multiple Syphon outputs)
- **Synesthesia**: audio-reactive scenes + Syphon output + OSC output (audio variables + optional control values)
- **Python VJ Console**: runs an always-on OSC hub that **receives** Synesthesia OSC and **forwards** it to:
  - **VJUniverse** (OSC :10000)
  - **Magic Music Visuals** (OSC :11111)
- **Magic Music Visuals**: Syphon mixer + (optional) OSC-driven modulation

Core principle: **Synesthesia → Python Hub → (VJUniverse + Magic)** for OSC, and **Syphon** for video.

---

## Repo cross-references (source of truth)

- VJUniverse main sketch: [processing-vj/src/VJUniverse/VJUniverse.pde](processing-vj/src/VJUniverse/VJUniverse.pde)
  - OSC port: `OSC_PORT = 10000`
  - Syphon servers: `VJUniverse`, and tile outputs `VJUniverse/Shader`, `VJUniverse/Lyrics`, `VJUniverse/Refrain`, `VJUniverse/SongInfo`, `VJUniverse/VJSims`, `VJUniverse/Image`
- Tile + Syphon architecture: [processing-vj/src/VJUniverse/Tile.pde](processing-vj/src/VJUniverse/Tile.pde)
- Synesthesia OSC → smoothed audio state: [processing-vj/src/VJUniverse/SynesthesiaAudioOSC.pde](processing-vj/src/VJUniverse/SynesthesiaAudioOSC.pde)
  - Expected Synesthesia-style audio addresses: `/audio/level/*`, `/audio/beat/*`, `/audio/bpm/*`, etc.
- Python OSC hub (receive+forward): [python-vj/osc/hub.py](python-vj/osc/hub.py)
  - Receive port: `9999`
  - Forward targets: `10000` (VJUniverse) and `11111` (Magic)
- Python OSC module public API: [python-vj/osc/\_\_init\_\_.py](python-vj/osc/__init__.py)
- Synesthesia OSC “single source of truth” (ports + categorization): [python-vj/launchpad_osc_lib/synesthesia_config.py](python-vj/launchpad_osc_lib/synesthesia_config.py)
- Python UI screen showing OSC routing: [python-vj/ui/panels/osc.py](python-vj/ui/panels/osc.py)

Related docs:

- System OSC overview: [OSC.md](OSC.md) (note: parts may be historical; code above is authoritative)

External docs:

- [Synesthesia OSC manual](https://app.synesthesia.live/docs/manual/osc.html)
- [Synesthesia SSF audio uniforms](https://app.synesthesia.live/docs/ssf/audio_uniforms.html) (what “audio variables” mean)

## Ports & routing (authoritative defaults)

| Port | Who listens | Purpose |
| ---- | ----------- | ------- |
| `7777` | Synesthesia | OSC input (control Synesthesia) |
| `9999` | Python OSC hub | OSC receive (Synesthesia outputs here) |
| `10000` | VJUniverse | OSC receive (hub forwards here) |
| `11111` | Magic Music Visuals | OSC receive (hub forwards here) |

Code references:

- Hub receive/forward: [python-vj/osc/hub.py](python-vj/osc/hub.py)
- VJUniverse OSC: [processing-vj/src/VJUniverse/VJUniverse.pde](processing-vj/src/VJUniverse/VJUniverse.pde)

If you change ports, change them at the source:

- Synesthesia output port in Synesthesia settings
- Forward targets in [python-vj/osc/hub.py](python-vj/osc/hub.py)
- VJUniverse listen port in [processing-vj/src/VJUniverse/VJUniverse.pde](processing-vj/src/VJUniverse/VJUniverse.pde)

---

## Core components

### Processing (4.x, Intel build under Rosetta)

- **Language/IDE**: Processing 4 (Java)
- **Apple Silicon Note**: Syphon's native library (`libJSyphon.jnilib`) is x86_64 only. Run Processing as Intel under Rosetta to avoid `UnsatisfiedLinkError` (have 'x86_64', need 'arm64')

**Key Points**:

- Install the **macOS x64 version** of Processing 4 (not the ARM build)
- Syphon requires OpenGL renderers → use `P2D` or `P3D`

**Download**: [Processing 4.x](https://processing.org/download)

---

### Syphon for Processing

[Syphon](http://syphon.info/) is an open source macOS technology that allows applications to share frames in realtime with zero latency and zero copy. It supports arbitrary resolutions (up to GPU limits, typically 16k x 16k), alpha channels, and works with both OpenGL and Metal backends.

**Key Features**:

- Hardware accelerated GPU surface sharing
- Zero latency, zero copy frame transfer
- Compatible with macOS 10.6 (Snow Leopard) or later
- Interoperable between OpenGL and Metal renderers

**Installation**:

1. In Processing: **Sketch → Import Library… → Manage Libraries…**
2. Search for "Syphon" (by Andres Colubri)
3. Install and restart Processing
4. **Important**: On Apple Silicon Macs, use the Intel/x64 build of Processing (Syphon library is x86_64 only)

**Official Examples** (from [Syphon/Processing GitHub](https://github.com/Syphon/Processing/tree/master/examples)):

- `SendScreen` - Send the main window output
- `SendFrames` - Send an off-screen PGraphics buffer
- `ReceiveFrames` - Receive frames from another Syphon server
- `MultipleServers` - Create multiple Syphon outputs
- `SelectServer` - Choose from available Syphon sources

**Resources**:

- [Syphon Official Site](http://syphon.info/) - Framework overview and compatible apps
- [GitHub: Syphon/Processing](https://github.com/Syphon/Processing) - Processing library (version 4.0)
- [Processing Libraries: Syphon](https://processing.org/reference/libraries/) - Listed under Video & Vision
- [FH Potsdam Tutorial](https://interface.fh-potsdam.de/processing/using-syphon.html)

---

### Synesthesia

Live music visualizer/VJ app with audio-reactive scenes, shaders, MIDI mapping, and Syphon/NDI integration.

- **Free base version** available
- **Pro edition** adds NDI/Syphon Pro features
- On macOS, supports Syphon input/output

**Resources**:

- [Synesthesia Official Site](https://synesthesia.live/)
- [Video / Syphon Output Docs](https://docs.synesthesia.live/)
- [Audio Input Guide](https://docs.synesthesia.live/)

---

### Magic Music Visuals (Performer)

Modular visual synth / VJ environment.

- **Performer edition** exposes the `SyphonClient` module to receive Syphon sources
- Demo version also supports SyphonClient

**Resources**:

- [Magic Music Visuals](https://magicmusicvisuals.com/)
- [User's Guide](https://magicmusicvisuals.com/guide)

---

### BlackHole (Audio Loopback)

Modern macOS virtual audio loopback driver to route audio between apps with near-zero latency.

Synesthesia's docs explicitly recommend loopback tools like BlackHole on macOS for routing system audio.

**Resources**:

- [BlackHole GitHub](https://github.com/ExistentialAudio/BlackHole)

---

### MIDI Devices (optional)

| Device | Role | Typical use |
| ------------------------- | ---------------- | ----------- |
| **Novation Launchpad Mini Mk3** | Controller | Synesthesia control (OSC/MIDI) and/or Python console control (project-specific) |
| **Akai MIDImix** | Mixer controller | Magic parameters (opacity, FX amounts, scene switching) |

---

## Processing: VJUniverse (the only Processing app)

### What VJUniverse provides

- A single Processing sketch with a **preview window** that shows multiple tiles/panels.
- Multiple Syphon servers (one per “output stream”).

Syphon output names are created in [processing-vj/src/VJUniverse/VJUniverse.pde](processing-vj/src/VJUniverse/VJUniverse.pde) (see `initTextlerSystem()`) and [processing-vj/src/VJUniverse/Tile.pde](processing-vj/src/VJUniverse/Tile.pde):

- `VJUniverse` (legacy “whole window” Syphon server)
- `VJUniverse/Shader`
- `VJUniverse/Lyrics`
- `VJUniverse/Refrain`
- `VJUniverse/SongInfo`
- `VJUniverse/VJSims`
- `VJUniverse/Image`

### How to run

1. Install Processing 4.x (Intel/x64 build on Apple Silicon).
2. Open the sketch: [processing-vj/src/VJUniverse/VJUniverse.pde](processing-vj/src/VJUniverse/VJUniverse.pde)
3. Run.

Expected console output includes:

- `OSC listening on port: 10000`
- `Syphon outputs: Shader, Lyrics, Refrain, SongInfo, VJSims, Image`


### OSC input that VJUniverse expects

VJUniverse consumes:

- **Audio**: Synesthesia-style `/audio/*` messages (parsed and smoothed in [processing-vj/src/VJUniverse/SynesthesiaAudioOSC.pde](processing-vj/src/VJUniverse/SynesthesiaAudioOSC.pde))
- **Shader selection** from Python:
  - `/shader/load [name, energy, valence]` (see [processing-vj/src/VJUniverse/VJUniverse.pde](processing-vj/src/VJUniverse/VJUniverse.pde))
- **Textler** text overlays:
  - `/textler/track`, `/textler/lyrics/*`, `/textler/refrain/*`, `/textler/slot`, etc. (see [processing-vj/src/VJUniverse/Tile.pde](processing-vj/src/VJUniverse/Tile.pde) and [processing-vj/src/VJUniverse/TextlerState.pde](processing-vj/src/VJUniverse/TextlerState.pde))
- **Image tile control**:
  - `/image/folder`, `/image/fit`, `/image/beat`, ... (see [processing-vj/src/VJUniverse/ImageTile.pde](processing-vj/src/VJUniverse/ImageTile.pde))

---

## Synesthesia: Syphon + Audio + OSC output

### Syphon Output from Synesthesia

1. Enable **Syphon Output** in Synesthesia Settings
2. Once enabled, Synesthesia appears as a Syphon server (e.g., "Synesthesia Main Output")

### Audio Input via BlackHole

Synesthesia needs an audio input device; playing music to speakers alone isn't enough.

**Configuration**:

1. **Install BlackHole** (2ch or 16ch)

2. **In Audio MIDI Setup**:
   - Create a **Multi-Output Device**
   - Include BlackHole and your speakers/headphones
   - Optionally set master clock and enable drift correction

3. **In System Settings → Sound → Output**:
   - Set output to the Multi-Output Device

4. **In Synesthesia Settings → Audio**:
   - Choose BlackHole (or the aggregate) as audio input

**Result**:

- DAW / Spotify / system audio → Multi-Output (speakers + BlackHole)
- Synesthesia "listens" to BlackHole and becomes audio reactive

### OSC output: send audio variables to the Python hub

Synesthesia OSC setup reference: [Synesthesia OSC manual](https://app.synesthesia.live/docs/manual/osc.html)

In Synesthesia Settings → OSC:

1. Enable **OSC Output**
2. Set **Output Address** to `127.0.0.1` (same machine)
3. Set **Output Port** to `9999` (matches [python-vj/osc/hub.py](python-vj/osc/hub.py) `RECEIVE_PORT`)
4. Enable **Output Audio Variables** (this is what drives `/audio/*`)
5. Optional: enable output for **Controls** if you want Magic to react to scene control changes

Notes:

- If you enable control output, Synesthesia may emit a lot of `/controls/*` messages; the hub currently forwards everything.
- If you want to *control* Synesthesia from Python, ensure Synesthesia OSC Input is enabled and listening on `7777` (see [python-vj/osc/hub.py](python-vj/osc/hub.py) `SYNESTHESIA` channel).

---

## Python VJ Console: OSC hub + forwarding

This is the glue that makes “Synesthesia OSC works in Magic” and “Synesthesia OSC works in VJUniverse” happen.

The hub behavior is implemented in [python-vj/osc/hub.py](python-vj/osc/hub.py):

- Receives OSC on `:9999`
- Forwards *every* message to:
  - `127.0.0.1:10000` (VJUniverse)
  - `127.0.0.1:11111` (Magic)

That forwarding is what exposes Synesthesia’s `/audio/*` messages to Magic without configuring Synesthesia to talk to Magic directly.

If you need to verify routing visually, the Python UI panel is in [python-vj/ui/panels/osc.py](python-vj/ui/panels/osc.py).

---

## Magic Music Visuals: Syphon mixer + OSC modulation

Magic serves as:

- A Syphon mixer / FX host (for VJUniverse and Synesthesia)
- An OSC-reactive modulation host (fed by the Python hub on `:11111`)

### Syphon Input in Magic (Performer or Demo)

Only Performer edition (and demo) support SyphonClient.

**To add VJUniverse Syphon sources**:

1. Add **SyphonClient** modules for each stream you want:

    - `VJUniverse/Shader`
    - `VJUniverse/Lyrics`
    - `VJUniverse/Refrain`
    - `VJUniverse/SongInfo`
    - `VJUniverse/VJSims`
    - `VJUniverse/Image`

1. Add **SyphonClient** for Synesthesia’s output (name depends on Synesthesia settings; commonly `Synesthesia Main Output`).
1. Compose in Magic (blend/mix/crossfade). Recommended: keep lyrics layers with alpha over your main visuals.

**Multiple Syphon Sources (typical)**:

```text
SyphonClient (Synesthesia) ──┐
SyphonClient (VJUniverse/Shader) ─┼─→ Mix/FX ─→ Output
SyphonClient (VJUniverse/Lyrics) ─┘
```

VJUniverse Syphon names are defined in [processing-vj/src/VJUniverse/VJUniverse.pde](processing-vj/src/VJUniverse/VJUniverse.pde) and [processing-vj/src/VJUniverse/Tile.pde](processing-vj/src/VJUniverse/Tile.pde).

### OSC input in Magic (make Synesthesia OSC work in Magic)

Magic OSC docs are not reliably fetchable from this workspace (site blocks automated fetch), but the workflow is:

1. In Magic, add an **OSC input source** on port `11111`.
2. Verify you are receiving messages (Magic should show activity for that input source).
3. Use Magic’s **Learn** / MIDI-OSC mapping UI to bind OSC addresses to parameters.

What you’ll see on port `11111`:

- Synesthesia audio variables (forwarded by the Python hub):
  - `/audio/level/bass`, `/audio/level/mid`, `/audio/level/high`, `/audio/level/all`, ...
  - `/audio/beat/onbeat`, `/audio/beat/beattime`, `/audio/beat/randomonbeat`
  - `/audio/bpm/bpmtwitcher`, `/audio/bpm/bpmconfidence`, ...

These are consumed by VJUniverse in [processing-vj/src/VJUniverse/SynesthesiaAudioOSC.pde](processing-vj/src/VJUniverse/SynesthesiaAudioOSC.pde) and should be treated as the canonical list to expect.

Suggested “starter mappings” in Magic:

- Drive a glow/brightness parameter with `/audio/level/all`.
- For smooth movement: `/audio/level/all` → **Scale** (map 0–1 into your target range) → **Ramp** (smooth it) → position/rotation/opacity/etc.
- Drive a flash/trigger with `/audio/beat/onbeat` (treat as pulse).
- Drive a slow LFO rate/phase with `/audio/beat/beattime` or `/audio/bpm/bpmtwitcher`.

If Magic needs different address names, adapt at the hub level (forward/rewrite) in [python-vj/osc/hub.py](python-vj/osc/hub.py).

### Audio input in Magic via BlackHole (optional)

1. Open **Input Sources Window** → "Show Audio Config"
2. Set device to BlackHole or suitable aggregate
3. Use sources (Source 0, Source 1, etc.) in Magic modules for audio reactivity

---

## Live rig architecture

### Visual Flow

**Expanded (current)**:

```text
Audio Player / DAW
     |
     v
   BlackHole / Multi-Output
     |
     +---> Synesthesia (visuals + /audio/* OSC) --Syphon-----------------+
     |                                  |                                 |
     |                                  +--> OSC :9999 (Python hub) --->  |
     |                                                             +------+
     |                                                             |
     |                                                   forwards to|  :11111
     |                                                             v
     +---> Speakers                                   Magic Music Visuals (mixer)
                         ^
                         |
                 Syphon (VJUniverse/*) ---+
                         |
                       VJUniverse (Processing)
                       (OSC :10000)
```

### Control Mapping

| Controller | Connected To | Controls |
| ---------- | ------------ | -------- |
| **Launchpad Mini Mk3** | Synesthesia (recommended) | Scene/preset selection, meta controls (MIDI/OSC) |
| **Akai MIDImix** | Magic Music Visuals | Faders: layer opacity / crossfade; Knobs: post-FX; Buttons: toggles/bypass |

---

## Exporting VJUniverse as a standalone app

For reliability in live performance:

1. In Processing (Intel build), open [processing-vj/src/VJUniverse/VJUniverse.pde](processing-vj/src/VJUniverse/VJUniverse.pde)
2. **File → Export Application…**:
   - Platform: macOS
   - Include JRE: Yes
3. Use the generated `.app` as your live "visual engine":
   - Starts without the IDE
   - Easier to restart if needed
   - Can be launched via Dock, script, or automation

---

## Quick reference

### Signal flow diagram

```text
┌─────────────────────────────────────────────────────────────────┐
│                        AUDIO FLOW                                │
├─────────────────────────────────────────────────────────────────┤
│  Spotify/DAW → Multi-Output Device → BlackHole → Synesthesia   │
│                              ↓                                   │
│                         Speakers                                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        VIDEO FLOW                                │
├─────────────────────────────────────────────────────────────────┤
│  VJUniverse ──Syphon──┐                                         │
│                       ├──→ Magic ──→ Projector                  │
│  Synesthesia ─Syphon──┘                                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        MIDI FLOW                                 │
├─────────────────────────────────────────────────────────────────┤
│  Launchpad ──→ Synesthesia (scene control)                      │
│  MIDImix   ──→ Magic (faders, knobs for mixing)                 │
└─────────────────────────────────────────────────────────────────┘
```

### Checklist: setting up a new live rig

#### Processing Setup

- [ ] Install Processing 4.x (Intel/x64 build for Apple Silicon)
- [ ] Install Syphon library via Library Manager
- [ ] Open and run [processing-vj/src/VJUniverse/VJUniverse.pde](processing-vj/src/VJUniverse/VJUniverse.pde)
- [ ] Confirm Syphon servers exist: `VJUniverse/*`
- [ ] Confirm OSC listening: `:10000`

#### Python Hub / VJ Console

- [ ] Start the Python VJ Console (or at least the OSC hub)
- [ ] Confirm hub receives on `:9999` and forwards to `:10000` and `:11111` (see [python-vj/osc/hub.py](python-vj/osc/hub.py))

#### Audio Routing

- [ ] Install BlackHole 2ch or 16ch
- [ ] Create Multi-Output Device in Audio MIDI Setup
- [ ] Set system output to Multi-Output Device
- [ ] Configure Synesthesia audio input to BlackHole

#### Synesthesia Setup

- [ ] Enable Syphon Output in settings
- [ ] Configure audio input to BlackHole
- [ ] Load desired scenes/shaders
- [ ] Enable OSC Output → Address `127.0.0.1`, Port `9999`
- [ ] Enable “Output Audio Variables” ([Synesthesia OSC manual](https://app.synesthesia.live/docs/manual/osc.html))

#### Mixer Setup (Magic Music Visuals)

- [ ] Add SyphonClient modules for each source
- [ ] Add OSC input source on port `11111`
- [ ] Learn-map `/audio/*` addresses to parameters (optional)
- [ ] Set up layer routing and effects
- [ ] Map MIDI controls from MIDImix

#### MIDI Controllers (optional)

- [ ] Connect MIDImix and map in Magic
- [ ] (Optional) Connect Launchpad and map in Synesthesia

#### Export & Test

- [ ] Export Processing sketch as standalone app
- [ ] Test full signal chain
- [ ] Verify MIDI control works throughout
- [ ] Check audio reactivity in all apps

---

## External Resources

### Syphon links

- [GitHub: Syphon/Processing](https://github.com/Syphon/Processing) - Library + examples
- [Andres Colubri Overview](https://andrescolubri.net/processing-syphon/)
- [FH Potsdam Tutorial](https://interface.fh-potsdam.de/processing/using-syphon.html) - Processing to mapping tools

### Synesthesia links

- [Official Site](https://synesthesia.live/) - Features, Syphon/NDI info
- [Documentation](https://docs.synesthesia.live/) - Video / Syphon Output
- [Audio Input Guide](https://docs.synesthesia.live/) - Loopback on macOS

### Magic links

- [Magic Music Visuals](https://magicmusicvisuals.com/) (site may block automated fetch)
- [Magic forum](https://magicmusicvisuals.com/forum)
- [Magic tutorials](https://magicmusicvisuals.com/tutorials)

### BlackHole links

- [GitHub](https://github.com/ExistentialAudio/BlackHole)
- OBS/University guides for Multi-Output Devices on macOS

### PixelFlow links

- [PixelFlow Documentation](https://diwi.github.io/PixelFlow/) - GPU-accelerated effects
- [PixelFlow GitHub](https://github.com/diwi/PixelFlow) - Source and examples

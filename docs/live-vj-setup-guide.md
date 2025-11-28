# VJ / Live-Performance Stack: Processing + Synesthesia + Magic/VPT

A comprehensive guide for setting up a flexible, low-cost live visual system on macOS.

## Overview

This setup enables:
- Custom games/world simulations using **Processing** (2D/3D, particles, raycast games)
- Frame sharing via **Syphon** for mixing and post-processing
- Music-reactive scenes and shaders with **Synesthesia**
- Layer compositing with **Magic Music Visuals** or **VPT 8** as Syphon mixers
- Audio routing into visual apps via **BlackHole**
- Tactile control using **Launchpad Mini Mk3** and **Akai MIDImix**

All components are either free or affordable (< ~100 USD per tool).

---

## Core Components

### Processing (4.x, Intel build under Rosetta)

- **Language/IDE**: Processing 4 (Java)
- **Apple Silicon Note**: Syphon's native library (`libJSyphon.jnilib`) is x86_64 only. Run Processing as Intel under Rosetta to avoid `UnsatisfiedLinkError` (have 'x86_64', need 'arm64')

**Key Points**:
- Install the **macOS x64 version** of Processing 4 (not the ARM build)
- Syphon requires OpenGL renderers → use `P2D` or `P3D`

**Download**: [Processing 4.x](https://processing.org/download)

---

### Syphon for Processing

Syphon is a macOS framework to share frames between apps in realtime.

**Installation**:
1. In Processing: **Sketch → Import Library… → Add Library…**
2. Search for "Syphon" (by Andres Colubri)
3. Install and restart Processing

**Resources**:
- [GitHub: Syphon/Processing](https://github.com/Syphon/Processing)
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

### VPT 8 (Video Projection Tool)

Free, multipurpose realtime projection/mapping tool by HC Gilje.

**Features**:
- Multiple layers
- Syphon in/out (macOS)
- MIDI, OSC, ArtNet control

**Resources**:
- [VPT 8 Official](https://hcgilje.wordpress.com/vpt/)

---

### BlackHole (Audio Loopback)

Modern macOS virtual audio loopback driver to route audio between apps with near-zero latency.

Synesthesia's docs explicitly recommend loopback tools like BlackHole on macOS for routing system audio.

**Resources**:
- [BlackHole GitHub](https://github.com/ExistentialAudio/BlackHole)

---

### MIDI Devices

| Device | Role | Use Case |
|--------|------|----------|
| **Novation Launchpad Mini Mk3** | Grid controller | Processing games (movement/shooting), LED feedback |
| **Akai MIDImix** | Faders/knobs | Mixer parameters (layer opacity, effects) |

---

## Processing: Game/Visuals + Syphon

### Basic Syphon Pattern

Minimal Syphon server in Processing:

```java
import codeanticode.syphon.*;

SyphonServer server;

void settings() {
  size(1280, 720, P3D);   // P2D or P3D required for Syphon
}

void setup() {
  frameRate(60);
  server = new SyphonServer(this, "ProcessingSyphonDemo");
}

void draw() {
  background(10);
  // draw your visuals...
  server.sendScreen();
}
```

- `SyphonServer(this, "Name")` registers a Syphon server visible in client apps
- `sendScreen()` sends the current framebuffer
- `sendImage(PGraphics)` can send an off-screen buffer

### Off-screen PGraphics + sendImage()

Pattern used for projection-mapping into MadMapper/HeavyM:

```java
PGraphics canvas;
SyphonServer server;

void setup() {
  size(1280, 720, P3D);
  canvas = createGraphics(1280, 720, P3D);
  server = new SyphonServer(this, "ProcessingCanvas");
}

void draw() {
  canvas.beginDraw();
  canvas.background(0);
  // draw all content into canvas
  canvas.endDraw();

  image(canvas, 0, 0, width, height);  // preview
  server.sendImage(canvas);            // Syphon output
}
```

### Wolfenstein-style "Z Hunter" Game with Syphon

A raycast ("Wolfenstein") game example:
- 16×16 grid world with random walls and yellow "Z" enemies
- Player moves/rotates; raycast renderer draws vertical walls per column
- Shooting ray forward removes enemies on collision

**Features**:
- Keyboard controls (arrows + space + R)
- Optional Launchpad control: movement, rotation, fire, reset
- LED feedback & rainbow effect when a Z is killed
- Syphon output: `SyphonServer("WolfensteinSyphon")` with `sendScreen()` in draw()
- Debug overlay: FPS, player position/angle, enemy count, Launchpad presence flag

**Key Design Decision - Graceful Degradation**:

```java
MidiBus midi = null;
boolean hasLaunchpad = false;

void setup() {
  // Scan for Launchpad
  String[] inputs = MidiBus.availableInputs();
  String[] outputs = MidiBus.availableOutputs();
  
  String launchpadIn = null;
  String launchpadOut = null;
  
  for (String dev : inputs) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      launchpadIn = dev;
    }
  }
  for (String dev : outputs) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      launchpadOut = dev;
    }
  }
  
  if (launchpadIn != null || launchpadOut != null) {
    midi = new MidiBus(this, launchpadIn, launchpadOut);
    hasLaunchpad = true;
  }
  // Game works keyboard-only if no Launchpad connected
}

// Guard all MIDI calls
void setPadColor(int x, int y, int col) {
  if (midi == null) return;
  int note = gridBase + y * 8 + x;
  midi.sendNoteOn(0, note, col);
}
```

---

## MIDI in Processing (Launchpad / MIDImix)

### TheMidiBus Library

We use [TheMidiBus](http://www.smallbutdigital.com/projects/themidibus/), a well-known MIDI library for Processing and Java.

**Installation**:
1. In Processing: **Sketch → Import Library… → Manage Libraries**
2. Search for "The MidiBus"
3. Click **Install**

### Typical Pattern

```java
import themidibus.*;

MidiBus midi;

void setup() {
  MidiBus.list(); // prints all devices

  String[] inputs  = MidiBus.availableInputs();
  String[] outputs = MidiBus.availableOutputs();

  // Find Launchpad
  String launchpadIn = null;
  String launchpadOut = null;
  
  for (String dev : inputs) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      launchpadIn = dev;
    }
  }
  for (String dev : outputs) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      launchpadOut = dev;
    }
  }

  if (launchpadIn != null || launchpadOut != null) {
    midi = new MidiBus(this, launchpadIn, launchpadOut);
  } else {
    midi = null; // keyboard-only mode
  }
}
```

### Safe LED Helper

```java
void setPadColor(int x, int y, int col) {
  if (midi == null) return;
  int note = gridBase + y * 8 + x;  // depends on Launchpad mapping
  midi.sendNoteOn(0, note, col);
}
```

### Launchpad Mini Mk3 Mapping

- Treat as 8×8 grid with a base MIDI note (e.g., 36)
- Helper functions: `gridToNote(x, y)` and `noteToGrid(note)`
- Game uses four directional pads + fire + reset on the grid

---

## Synesthesia: Syphon + Audio via BlackHole

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

---

## Magic Music Visuals: SyphonClient + BlackHole Audio

Magic serves as:
- A Syphon mixer / FX host (for Processing and/or Synesthesia)
- An audio-reactive composition environment fed by BlackHole

### Syphon Input in Magic (Performer or Demo)

Only Performer edition (and demo) support SyphonClient.

**To add a Syphon source**:
1. Right-click in Editor → **Add → Special → SyphonClient**
2. In SyphonClient module parameters, set Sender/Server to your Syphon server:
   - `ProcessingSyphonDemo`
   - `WolfensteinSyphon`
   - `Synesthesia Main Output`
3. Connect SyphonClient → [effects / mix] → Magic output module

**Multiple Syphon Sources**:
```
SyphonClient (Processing)  ┐
                           ├→ Mix / Composite → Magic Output
SyphonClient (Synesthesia) ┘
```

### Audio Input in Magic via BlackHole

1. Open **Input Sources Window** → "Show Audio Config"
2. Set device to BlackHole or suitable aggregate
3. Use sources (Source 0, Source 1, etc.) in Magic modules for audio reactivity

---

## VPT 8: Free Syphon + MIDI Mixer

VPT 8 is an alternative or additional free mixer:
- Free realtime projection/mapping and mixing tool
- Supports Syphon sources as inputs on macOS
- Can output via Syphon as well
- MIDI/OSC/ArtNet can control most parameters

### Basic Flow

1. In VPT, load `defaultproject-vpt8` / `projectpath.maxpat` for full UI
2. In the **Sources** list, turn ON a `syph` module
3. Use dropdown to pick the Syphon server (Processing or Synesthesia)
4. In the **Layers** section, assign that syph source to a layer
5. Use Akai MIDImix as VPT's MIDI input and map:
   - Faders → layer opacity / master brightness
   - Knobs → FX parameters / color adjustments

---

## Live Rig Architecture

### Visual Flow

**Minimal Chain**:
```
[Processing Game/World] --Syphon--> [Magic / VPT] --output--> Projector
```

**Expanded with Synesthesia**:
```
Audio Player / DAW
         |
         v
   BlackHole / Multi-Output
         |
         +---> Synesthesia (audio-reactive scenes) --Syphon--+
         |                                                    |
         +---> Magic / VPT (audio-reactive mixing) <----------+
                         ^
                         |
                 Syphon from Processing (games/sims)
                         |
                         v
                     Projector
```

### Control Mapping

| Controller | Connected To | Controls |
|------------|--------------|----------|
| **Launchpad Mini Mk3** | Processing game sketch via TheMidiBus | Movement/shooting in games, LED feedback, rainbow effects |
| **Akai MIDImix** | Magic or VPT | Faders: layer opacity / crossfade; Knobs: post-FX (blur, color, glow); Buttons: scene changes, bypass toggles |

---

## Exporting Processing as Standalone App

For reliability in live performance:

1. In Processing (Intel build), open your Syphon-enabled sketch
2. **File → Export Application…**:
   - Platform: macOS
   - Include JRE: Yes
3. Use the generated `.app` as your live "visual engine":
   - Starts without the IDE
   - Easier to restart if needed
   - Can be launched via Dock, script, or automation

---

## Quick Reference

### Signal Flow Diagram

```
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
│  Processing ──Syphon──┐                                         │
│                       ├──→ Magic/VPT ──→ Projector              │
│  Synesthesia ─Syphon──┘                                         │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                        MIDI FLOW                                 │
├─────────────────────────────────────────────────────────────────┤
│  Launchpad ──→ Processing (games, LED control)                  │
│  MIDImix   ──→ Magic/VPT (faders, knobs for mixing)             │
└─────────────────────────────────────────────────────────────────┘
```

### Checklist: Setting Up a New Live Rig

#### Processing Setup
- [ ] Install Processing 4.x (Intel/x64 build for Apple Silicon)
- [ ] Install Syphon library via Library Manager
- [ ] Install TheMidiBus library via Library Manager
- [ ] Create sketch with `P2D` or `P3D` renderer
- [ ] Add SyphonServer and `sendScreen()` call

#### Audio Routing
- [ ] Install BlackHole 2ch or 16ch
- [ ] Create Multi-Output Device in Audio MIDI Setup
- [ ] Set system output to Multi-Output Device
- [ ] Configure Synesthesia audio input to BlackHole

#### Synesthesia Setup
- [ ] Enable Syphon Output in settings
- [ ] Configure audio input to BlackHole
- [ ] Load desired scenes/shaders

#### Mixer Setup (Magic or VPT)
- [ ] Add SyphonClient modules for each source
- [ ] Configure audio input to BlackHole
- [ ] Set up layer routing and effects
- [ ] Map MIDI controls from MIDImix

#### MIDI Controllers
- [ ] Connect Launchpad Mini Mk3
- [ ] Set Launchpad to Programmer mode
- [ ] Connect Akai MIDImix
- [ ] Map MIDImix faders/knobs in mixer app

#### Export & Test
- [ ] Export Processing sketch as standalone app
- [ ] Test full signal chain
- [ ] Verify MIDI control works throughout
- [ ] Check audio reactivity in all apps

---

## External Resources

### Syphon for Processing
- [GitHub: Syphon/Processing](https://github.com/Syphon/Processing) - Library + examples
- [Andres Colubri Overview](https://andrescolubri.net/processing-syphon/)
- [FH Potsdam Tutorial](https://interface.fh-potsdam.de/processing/using-syphon.html) - Processing to mapping tools

### Synesthesia
- [Official Site](https://synesthesia.live/) - Features, Syphon/NDI info
- [Documentation](https://docs.synesthesia.live/) - Video / Syphon Output
- [Audio Input Guide](https://docs.synesthesia.live/) - Loopback on macOS

### Magic Music Visuals
- [User's Guide](https://magicmusicvisuals.com/guide) - Full reference
- [Forum](https://magicmusicvisuals.com/forum) - SyphonClient, MIDI threads
- [Tutorial Videos](https://magicmusicvisuals.com/tutorials) - Audio-reactive scenes

### VPT 8
- [Official Documentation](https://hcgilje.wordpress.com/vpt/)
- Tutorials for mixing/mapping

### BlackHole
- [GitHub](https://github.com/ExistentialAudio/BlackHole)
- OBS/University guides for Multi-Output Devices on macOS

### PixelFlow
- [PixelFlow Documentation](https://diwi.github.io/PixelFlow/) - GPU-accelerated effects
- [PixelFlow GitHub](https://github.com/diwi/PixelFlow) - Source and examples

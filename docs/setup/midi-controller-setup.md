# MIDI Controller Setup Guide

This guide covers setting up MIDI controllers for VJ work and Processing games, specifically the **Akai MIDImix** and **Launchpad Mini Mk3**.

## Controller Roles

| Controller | Primary Use | Mode |
|------------|-------------|------|
| Akai MIDImix | VJ / lighting control (Synesthesia, Resolume) | Standard MIDI |
| Launchpad Mini Mk3 | Processing games + custom visuals | Programmer mode |

This separation keeps sliders/knobs for VJ work and pads for interactive games.

---

## Akai MIDImix as VJ Controller

### Hardware Overview

The MIDImix provides:
- **8 channel strips**, each with:
  - 1 fader
  - 3 knobs
  - 2 buttons
- **1 master fader**
- All controls are assignable via the MIDImix Editor (CC/Note + MIDI channel)

### Suggested VJ Mapping

Use the MIDImix Editor to create a preset (e.g., `Synesthesia.midimix`):

#### Per Channel Strip (1–8)

| Control | Function | CC Range |
|---------|----------|----------|
| Fader | Layer opacity / brightness | CC 20–27 |
| Knob 1 | Layer effect 1 (distortion, blur, feedback) | CC 28–35 |
| Knob 2 | Layer effect 2 (zoom, rotation) | CC 36–43 |
| Knob 3 | Color parameter (hue shift, saturation) | CC 44–51 |

This gives you 8 independent layers, each with:
- 1 "intensity" fader
- 2 FX parameters
- 1 color parameter

#### Button Rows

| Button Row | Function | Notes |
|------------|----------|-------|
| Top button | Layer ON/OFF | Toggle, sends Note or CC; map to layer enable/mute |
| Bottom button | Special | Per-layer strobe, glitch, "Z-mode", etc. |

#### Master Section

| Control | Function |
|---------|----------|
| Master fader | Global brightness or master video opacity |

Optional extra CCs on a separate MIDI channel:
- Global strobe rate
- Global playback speed
- Scene/preset next/previous

### Software Configuration

In your VJ software:
1. Use MIDI learn where possible
2. If a parameter expects a particular CC number (e.g., CC 74 filter cutoff), set the corresponding control to that CC in the MIDImix Editor

**Tip**: Create multiple presets (e.g., `Resolume.midimix`, `Synesthesia.midimix`) and swap between them as needed.

---

## Launchpad Mini Mk3 for Processing Games

### Available Modes

The Mini Mk3 has only two device states:

| Mode | Description |
|------|-------------|
| **Live mode** | Session / Drum / Keys / User custom modes work normally |
| **Programmer mode** | Blank MIDI grid; all pads + buttons send fixed MIDI messages; LEDs controlled entirely by messages you send back |

For Processing games, use **Programmer mode**.

### Switching Modes

#### Enter Settings Menu
1. Press and hold **Session** briefly
2. Top 4 rows show settings options

#### Choose Mode
- Press **green Scene Launch button** → Live mode
- Press **orange Scene Launch button** → Programmer mode

#### Exit Settings
Release **Session** button.

**Notes**:
- The Launchpad always powers on in Live mode
- In Programmer mode the whole surface is initially dark (expected)

### LED Feedback Settings

In the settings menu, you can configure:

| Setting | Recommendation |
|---------|----------------|
| LED feedback (internal) | Whether pads auto-light when pressed in Custom modes |
| LED feedback (external) | Keep **ON** so Processing code can light pads |

For games, leave external feedback ON so your Processing code controls the lights without DAW-style auto LEDs.

### MIDI Note Layout

The exact note layout for Programmer mode is documented in the **Launchpad Mini Mk3 Programmer's Reference Guide** (download from Novation's website).

Instead of hard-coding, let the Launchpad tell you the layout by building a map in Processing:

```java
// Map from MIDI note -> grid coordinate
HashMap<Integer, PVector> noteToGrid = new HashMap<Integer, PVector>();

void noteOn(int channel, int pitch, int velocity) {
  // Build the map dynamically or use the reference guide layout
  // Programmer mode uses notes 11-88 in a specific pattern
}
```

### Programmer Mode Note Grid

The 8x8 pad grid uses notes in this pattern:

```
Row 8: 81 82 83 84 85 86 87 88
Row 7: 71 72 73 74 75 76 77 78
Row 6: 61 62 63 64 65 66 67 68
Row 5: 51 52 53 54 55 56 57 58
Row 4: 41 42 43 44 45 46 47 48
Row 3: 31 32 33 34 35 36 37 38
Row 2: 21 22 23 24 25 26 27 28
Row 1: 11 12 13 14 15 16 17 18
```

Scene launch buttons (right column): 89, 79, 69, 59, 49, 39, 29, 19

### LED Colors

Send MIDI note-on messages with velocity values to set LED colors:

| Velocity | Color |
|----------|-------|
| 0 | Off |
| 1-3 | Dark red shades |
| 4-7 | Red |
| 8-11 | Orange |
| 12-15 | Yellow |
| 16-19 | Green shades |
| ... | See full palette in Programmer's Reference |

**Example** (Processing):
```java
void lightPad(int note, int color) {
  // Send note-on to the Launchpad
  myBus.sendNoteOn(0, note, color);
}

void clearPad(int note) {
  myBus.sendNoteOn(0, note, 0);
}
```

---

## Combining Both Controllers

### Recommended Setup

1. **MIDImix** on MIDI Channel 1 for VJ control
2. **Launchpad** on Channel 1 (default in Programmer mode) for games

Since they're different devices with different note/CC ranges, they won't conflict.

### Processing Multi-Controller Code

```java
import themidibus.*;

MidiBus midimix;
MidiBus launchpad;

void setup() {
  MidiBus.list(); // List available MIDI devices
  
  midimix = new MidiBus(this, "MIDI Mix", "MIDI Mix");
  launchpad = new MidiBus(this, "Launchpad Mini MK3 MIDI 2", "Launchpad Mini MK3 MIDI 2");
}

// Handle MIDImix faders/knobs
void controllerChange(int channel, int number, int value) {
  if (number >= 20 && number <= 27) {
    // Fader moved - adjust layer opacity
    int layer = number - 20;
    float opacity = map(value, 0, 127, 0, 1);
    setLayerOpacity(layer, opacity);
  }
}

// Handle Launchpad pads
void noteOn(int channel, int pitch, int velocity) {
  // Convert note to grid position
  int col = (pitch % 10) - 1;
  int row = (pitch / 10) - 1;
  
  if (col >= 0 && col < 8 && row >= 0 && row < 8) {
    handlePadPress(col, row);
  }
}
```

---

## Troubleshooting

### MIDImix Not Detected
- Ensure USB connection is secure
- Check device manager for driver issues
- Try a different USB port

### Launchpad in Wrong Mode
- Hold Session, press orange button for Programmer mode
- Release Session to exit settings

### No LED Response
- Verify external LED feedback is enabled in settings
- Check MIDI output is going to correct port
- Confirm velocity values are in valid range (0-127)

### MIDI Messages Not Received
- Use a MIDI monitor tool to verify messages are being sent
- Check channel assignments match your code
- Verify the correct MIDI port is selected in Processing

---

## Resources

- [Akai MIDImix Editor](https://www.akaipro.com/midimix) - Download preset editor
- [Launchpad Mini Mk3 Programmer's Reference](https://novationmusic.com/launchpad) - Full MIDI specification
- [The MidiBus for Processing](http://www.smallbutdigital.com/projects/themidibus/) - Processing MIDI library

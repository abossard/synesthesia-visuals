# OSC Visual Mapping Guide

Complete guide for using audio analysis OSC output with VJ software like Magic Music Visuals, Resolume, TouchDesigner, Processing, and Synesthesia.

**Related:** [Audio Analysis Features](../features/audio-analysis.md)

---

## Quick Start

```bash
cd python-vj
python vj_console.py
# Press 'A' to toggle audio analyzer
```

Configure your VJ software to receive OSC on `127.0.0.1:10000`.

---

## Feature Mapping Strategies

### Layer by Frequency

```
Layer 1 (Bottom): Sub-bass → Deep pulses, screen shake
Layer 2 (Middle): Bass/mid → Main rhythm, large shapes
Layer 3 (Top): Highs → Sparkles, particles
Layer 4 (Flash): Beat → Flashes, effects
```

### Smoothing Guidelines

| Response | α Value | Use For |
|----------|---------|---------|
| Fast | 0.1-0.2 | Beats, flashes, percussion |
| Medium | 0.3-0.5 | Bass, main elements |
| Slow | 0.6-0.8 | Background, atmosphere |

---

## Bass-Driven Effects

Bass provides the most powerful VJ control—predictable rhythm and physical impact.

### Size/Scale Pulse
```
/audio/levels[1] (bass) → Object Scale
Min: 1.0, Max: 3.0, Smoothing: 0.3
```

### Color Flash
```
/bass_band → Red Channel
Blend: Add or Screen
```

### Camera Shake
```
/bass_band → Shake Amount (5-20px)
Decay: Fast
```

### Particle Burst
```
/bass_band → Particle Birth Rate
Base: 10/sec, Peak: 500/sec
```

### Sub-Bass vs Bass Separation

```
Sub-bass (20-60 Hz):
  → Deep rumble, screen shake, dark flashes

Bass (60-250 Hz):
  → Main pulse, bright flashes, particle bursts
```

---

## Beat Flash Effect

```
Trigger: /audio/beat[0] == 1
Flash color: White
Peak opacity: 0.3-0.5 (don't blind audience!)
Decay: Exponential, 200-300ms

Timeline:
  Beat → 0.5 opacity
  50ms  → 0.25
  100ms → 0.1
  200ms → 0.0
```

---

## Build-up & Drop Responses

### Build-up Visual Sequence

**Early phase (2+ seconds before drop):**
- Increase effect intensity +20%
- Start filter sweep (200 Hz → 8 kHz)
- Gradually increase brightness

**Peak phase (last 1-2 seconds):**
- Enable strobe at BPM/4 rate
- Camera zoom to 110%
- Particles accumulate
- Colors desaturate to white

### Drop Explosion

```
0.00s - White flash (0.7 opacity)
0.05s - Particle explosion (1000 particles)
0.10s - Camera shake peak
0.20s - Flash fades
0.50s - Full intensity visuals
```

### Detection Refinement

Avoid false positives with multiple conditions:

```python
# Good build-up
if buildup == 1 AND energy_trend > 0.3 AND duration > 2s:
    trigger_buildup()

# Good drop
if drop == 1 AND bass > 0.7 AND prev_energy < 0.4:
    trigger_drop()
```

---

## Scene Switching Strategies

### Method 1: Beat-Triggered
```
Every 16 or 32 beats → Fade to next scene
Transition: 1-2 beat crossfade
```

### Method 2: Build-up/Drop Triggered
```
Build-up detected → Start transition animation
Drop detected → Complete with explosive effect
```

### Method 3: Energy-Based
```
High (>0.7)    → Intense, chaotic visuals
Medium (0.3-0.7) → Normal visuals
Low (<0.3)     → Minimal, ambient visuals
```

### Method 4: Brightness-Based
```
Bright (>0.6) → Sharp, geometric visuals
Dark (<0.4)   → Soft, organic visuals
```

---

## Genre-Specific Mappings

### EDM / Big Room House
```
Bass → Main visual pulse (large shapes, shake)
Beat → Flash effects, layer switching
Build-up → Filter sweep, intensity ramp
Drop → Explosive transition
Highs → Sparkle particles
Scene switching: Every 16-32 beats
```

### Techno / Minimal
```
Bass → Subtle pulse (1.0-1.2x scale)
Beat → Minimal flash or geometry changes
Centroid → Slow pattern morphing
Scene switching: Every 64-128 beats, morph transitions
```

### Dubstep / Bass Music
```
Sub-bass → Deep rumble, screen distortion
Bass → Main wobble effects
Drop → Massive explosions, glitch effects
Build-up → Tension (grain, noise)
Scene switching: Drop-triggered only, aggressive
```

### Ambient / Downtempo
```
Overall RMS → Gentle brightness modulation
Centroid → Color palette shifts
Pitch → Harmonic visualization
Scene switching: Very slow or manual only, long crossfades
```

---

## Software Setup

### Resolume Arena

```
Preferences → OSC → Input → Port 9000
Right-click parameter → OSC Input → Play music to auto-map
```

**Best practices:**
- Layer Opacity ← overall energy
- Clip parameters ← specific bands
- Composition parameters ← global effects

### TouchDesigner

```
oscin1 → oscinDAT1 → parseOSC → CHOP channels
```

```python
def onReceiveOSC(dat, address, value):
    if address == '/audio/beat' and value[0] == 1:
        op('flash').par.opacity = 1.0
```

### Processing

```java
import oscP5.*;

OscP5 osc;

void setup() {
  size(1920, 1080);
  osc = new OscP5(this, 10000);  // VJUniverse port
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/audio/levels")) {
    float bass = msg.get(1).floatValue();
    // Use bass value
  }
  if (msg.checkAddrPattern("/audio/beat")) {
    if (msg.get(0).intValue() == 1) {
      // Trigger flash
    }
  }
}
```

### Magic Music Visuals

```
Settings → OSC → Enable Input → Port 10000
Use "OSC" modulator → Select address → Assign to effect
```

### Synesthesia

Already built to receive audio analysis on port 10000.

Custom shaders access via:
```glsl
uniform float syn_BassLevel;
uniform float syn_BeatTime;
uniform float syn_BPM;
```

---

## Quick Reference Table

| Address | Range | Best For | Response |
|---------|-------|----------|----------|
| `/audio/levels[0]` (sub) | 0-1 | Deep rumble | Fast |
| `/audio/levels[1]` (bass) | 0-1 | Main pulse | Fast |
| `/audio/levels[2-4]` (mids) | 0-1 | Melody, color | Medium |
| `/audio/levels[5-6]` (highs) | 0-1 | Sparkles | Fast |
| `/audio/levels[7]` (overall) | 0-1 | Global intensity | Medium |
| `/audio/beat[0]` (onset) | 0/1 | Triggers | Instant |
| `/audio/beat[1]` (flux) | 0-1 | Onset strength | Fast |
| `/audio/bpm` | 60-180 | Animation sync | Slow |
| `/audio/structure[0]` (buildup) | 0/1 | Build effects | Trigger |
| `/audio/structure[1]` (drop) | 0/1 | Drop effects | Trigger |
| `/audio/structure[2]` (trend) | -1 to +1 | Intensity trends | Slow |

---

## Complete Visual Setup Example

**Goal:** Full reactive system for house music

```
Layer 1 - Background Pulse:
  /audio/levels[1] → Scale (1.0-1.5x)
  Color: Dark blue to cyan

Layer 2 - Mid Frequencies:
  /audio/levels[3] → Particle count (50-300)
  Color: Yellow/orange

Layer 3 - High Sparkles:
  /audio/levels[6] → Emission (0-500/sec)
  Color: White/cyan, Life: 0.5s

Layer 4 - Beat Flash:
  /audio/beat[0] → Full-screen white overlay
  Opacity: 0→0.4→0 (300ms)

Layer 5 - Scene Control:
  /audio/structure[1] → Switch scene
  Transition: 1-beat crossfade

Build-up Mode:
  - All layers +30% intensity
  - Add motion blur
  - Camera zoom in

Drop Mode:
  - White flash (0.7 opacity)
  - 1000 particle explosion
  - Camera shake (30px, 1s)
```

---

## Pro Tips

1. **Avoid visual fatigue** — flash for 16 beats, rest for 16, repeat
2. **Create dynamics** — don't run maximum intensity constantly
3. **Test with different music** — EDM, minimal techno, ambient
4. **Have a safe default** — gentle animation if OSC connection lost

---

## Troubleshooting

| Issue | Check |
|-------|-------|
| No OSC received | Analyzer running? Port 10000? Firewall? |
| Not reactive enough | Increase range, reduce smoothing, use exponential |
| Too chaotic | Increase smoothing, add threshold (ignore < 0.2) |
| Build-up not detecting | Music has clear build-ups? Try EDM tracks first |

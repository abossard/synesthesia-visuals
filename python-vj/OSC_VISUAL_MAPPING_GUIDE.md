# OSC Visual Mapping Guide for VJ Software

Complete guide on how to use the audio analysis OSC output for creative visual control in VJ applications like Magic Music Visuals, Resolume, TouchDesigner, Processing, and Synesthesia.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [OSC Address Reference](#osc-address-reference)
3. [Bass-Driven Visual Effects](#bass-driven-visual-effects)
4. [When to Switch Visuals](#when-to-switch-visuals)
5. [Build-up and Drop Detection](#build-up-and-drop-detection)
6. [Feature Mapping Examples](#feature-mapping-examples)
7. [Genre-Specific Mappings](#genre-specific-mappings)
8. [Software-Specific Setup](#software-specific-setup)

---

## Quick Start

### Basic Setup (5 minutes)

1. **Start the Audio Analyzer:**
   ```bash
   cd python-vj
   python vj_console.py
   # Press 'A' to toggle audio analyzer on
   ```

2. **Configure Your VJ Software:**
   - Set OSC input to receive on `127.0.0.1:9000` (default)
   - Map incoming OSC addresses to visual parameters
   - Start with `/audio/beat` → flash/strobe effect

3. **Verify It Works:**
   - Play music with strong beats
   - Watch your flash effect trigger on each beat
   - Press '5' in VJ Console to see live analysis

---

## OSC Address Reference

### `/audio/levels` - Frequency Bands (8 values)

**Format:** `[sub_bass, bass, low_mid, mid, high_mid, presence, air, overall_rms]`

**Value Range:** 0.0 - 1.0 (compressed with tanh for smooth visualization)

**Update Rate:** ~60 Hz

**Frequency Ranges:**
- `sub_bass` (20-60 Hz) - Very deep bass, felt more than heard
- `bass` (60-250 Hz) - Kick drum, bass guitar, main rhythm
- `low_mid` (250-500 Hz) - Body of instruments, warmth
- `mid` (500-2000 Hz) - Vocals, melody instruments
- `high_mid` (2000-4000 Hz) - Clarity, presence of vocals
- `presence` (4000-6000 Hz) - Definition, articulation
- `air` (6000-20000 Hz) - Sparkle, cymbals, hi-hats
- `overall_rms` - Overall loudness/energy

**Best Used For:**
- Individual frequency-reactive elements
- Color mapping (bass=red, mids=green, highs=blue)
- Size/scale modulation
- Layer mixing/crossfading

---

### `/audio/spectrum` - Full Spectrum (32 values)

**Format:** `[bin0, bin1, ..., bin31]` (32 frequency bins)

**Value Range:** 0.0 - 1.0 (normalized)

**Update Rate:** ~60 Hz

**Best Used For:**
- Spectrum visualizers (bars, circular, waveform)
- Audio-reactive grids
- Particle system density
- Detailed frequency visualization

---

### `/audio/beat` - Beat Detection (2 values)

**Format:** `[is_onset, spectral_flux]`

**Values:**
- `is_onset` - Integer: 1 when beat detected, 0 otherwise
- `spectral_flux` - Float 0.0-1.0: Strength of the onset/novelty

**Update Rate:** ~60 Hz

**Best Used For:**
- Flash/strobe effects
- Scene transitions
- Particle bursts
- Camera shake/zoom
- Layer switching

**⚡ CRITICAL FOR VJ:** This is your #1 trigger for synchronized visuals!

---

### `/audio/bpm` - Tempo (2 values)

**Format:** `[bpm, confidence]`

**Values:**
- `bpm` - Float 60-180: Estimated beats per minute
- `confidence` - Float 0.0-1.0: Reliability of BPM estimate

**Update Rate:** ~60 Hz (smoothed internally)

**Best Used For:**
- Animation speed synchronization
- LFO rate modulation
- Effect timing (delay, echo)
- Visual metronome

---

### `/audio/pitch` - Pitch Detection (2 values)

**Format:** `[frequency_hz, confidence]`

**Values:**
- `frequency_hz` - Float: Fundamental frequency in Hz (0 if no pitch)
- `confidence` - Float 0.0-1.0: Reliability of pitch detection

**Update Rate:** ~60 Hz

**Best Used For:**
- Color mapping (pitch → hue)
- Position mapping (pitch → Y position)
- Harmony-based effects
- Melodic visualization

**Note:** Works best with monophonic sources (single melody, bassline)

---

### `/audio/structure` - Build-up/Drop Detection (4 values)

**Format:** `[is_buildup, is_drop, energy_trend, brightness_trend]`

**Values:**
- `is_buildup` - Integer: 1 during energy ramps, 0 otherwise
- `is_drop` - Integer: 1 during energy jumps after low period, 0 otherwise
- `energy_trend` - Float -1.0 to +1.0: Energy slope (positive = building)
- `brightness_trend` - Float 0.0-1.0: Spectral centroid (higher = brighter)

**Update Rate:** ~60 Hz (analyzed over 2-second window)

**Best Used For:**
- Automatic scene transitions
- Filter sweeps during build-ups
- Explosive effects on drops
- Intensity modulation

**🔥 ESSENTIAL FOR EDM:** Detects build-ups and drops automatically!

---

## Bass-Driven Visual Effects

### Strategy: Use Bass Band to Drive Core Elements

**Why Bass?**
- Most energy in EDM/Techno/House tracks
- Provides steady, predictable rhythm
- Felt physically by the audience
- Creates powerful visual impact

### Technique 1: Bass → Size/Scale

```
Map: /audio/levels[1] (bass) → Object Scale

Settings:
- Min scale: 1.0
- Max scale: 3.0
- Smoothing: Medium (0.3)
- Response: Linear or Exponential

Result: Objects pulse with kick drum
```

**What to Pulse:**
- Large geometric shapes (circles, squares)
- Background elements
- Entire scene scale
- Camera zoom

---

### Technique 2: Bass → Color Intensity

```
Map: /audio/levels[1] (bass) → Red Channel

Settings:
- Base color: Dark red/orange
- Intensity range: 0.0 - 1.0
- Blend mode: Add or Screen

Result: Scene flashes red on kick
```

**Color Schemes:**
- **Techno:** Red/Orange bass, Blue highs
- **House:** Warm yellows/oranges
- **Dubstep:** Purple/cyan bass flashes

---

### Technique 3: Bass → Camera Effects

```
Map: /audio/levels[1] (bass) → Camera Shake

Settings:
- Shake amount: 5-20 pixels
- Decay: Fast (returns to center quickly)
- Direction: Random or radial

Result: Screen shakes on kick
```

**Other Camera Effects:**
- Zoom in/out
- Rotation wobble
- Position offset
- Depth of field

---

### Technique 4: Bass → Particle Emission

```
Map: /audio/levels[1] (bass) → Particle Birth Rate

Settings:
- Base rate: 10 particles/sec
- Peak rate: 500 particles/sec
- Particle life: 0.5-2.0 seconds

Result: Burst of particles on kick
```

---

### Advanced: Sub-Bass vs Bass Separation

Use both sub-bass and bass for layered effects:

```
Sub-bass (20-60 Hz) → Deep rumble effects
- Screen shake
- Dark color flashes
- Low-frequency geometric patterns

Bass (60-250 Hz) → Main rhythm effects
- Object scaling
- Bright flashes
- Particle bursts
```

---

## When to Switch Visuals

### Automatic Scene Switching Based on Audio

**Method 1: Beat-Triggered Transitions**

```
Trigger: /audio/beat[0] == 1
Condition: Every 16 or 32 beats
Action: Fade to next scene

Implementation:
- Count beats internally
- Switch every 16 beats (4 bars at 4/4)
- Use crossfade transition (1-2 beats duration)
```

**Best For:** Maintaining visual variety without manual control

---

**Method 2: Build-up Triggered Transitions**

```
Trigger: /audio/structure[0] == 1 (is_buildup)
Condition: Build-up detected
Action: Start transition animation

Then:
Trigger: /audio/structure[1] == 1 (is_drop)
Action: Complete transition with explosive effect
```

**Timeline Example:**
```
00:00 - Normal visuals (Scene A)
00:05 - Build-up detected → start filter sweep, increase brightness
00:10 - Drop detected → explosive transition to Scene B
00:11 - Continue with Scene B
```

**Best For:** EDM/Techno/House where build-ups/drops are prominent

---

**Method 3: Energy-Based Switching**

```
Trigger: /audio/levels[7] (overall_rms)
Conditions:
- High energy (>0.7) → Intense, chaotic visuals
- Medium energy (0.3-0.7) → Normal visuals
- Low energy (<0.3) → Minimal, ambient visuals

Action: Fade between scene banks
```

**Best For:** Progressive house, ambient sections, dynamic sets

---

**Method 4: Brightness-Based Switching**

```
Trigger: /audio/structure[3] (brightness_trend)
Conditions:
- Bright (>0.6) → Sharp, geometric visuals
- Dark (<0.4) → Soft, organic visuals

Action: Morph between visual styles
```

**Best For:** Tonal shifts, harmonic changes

---

### Manual Override Strategy

Always keep manual scene switching available:

```
- Auto-switch: Active by default
- Manual trigger: Overrides auto for 32 beats
- Then: Resume auto-switching
```

---

## Build-up and Drop Detection

### Understanding Build-up Detection

**What It Detects:**
- Sustained energy increase over 2-4 seconds
- Rising spectral content (brightness)
- Reduction in bass (common before drops)

**OSC Signal:**
```
/audio/structure[0] == 1  → Build-up active
/audio/structure[2] > 0.3 → Positive energy trend
```

---

### Build-up Visual Responses

**Phase 1: Early Build-up (First 2 seconds)**

```
Visual Changes:
- Increase effect intensity by 20%
- Add motion blur
- Start filter sweep (low-pass → high-pass)
- Gradually increase brightness
```

**Example Mapping:**
```
/audio/structure[2] (energy_trend) → Filter Cutoff
Range: 200 Hz → 8000 Hz
Duration: Build-up period
```

---

**Phase 2: Peak Build-up (Last 1-2 seconds)**

```
Visual Changes:
- Strobe/flash effects intensify
- Camera shake increases
- Particles accumulate
- Colors desaturate to white
- Add anticipation (pause, zoom in)
```

**Example:**
```
When /audio/structure[2] > 0.5:
  - Enable strobe at BPM/4 rate
  - Scale multiplier: 1.5x
  - Zoom: 110%
```

---

### Drop Visual Responses

**What Drop Detection Captures:**
- Sudden energy jump after low period
- Return of bass frequencies
- Spectral brightness spike

**OSC Signal:**
```
/audio/structure[1] == 1  → Drop active (for ~1 second)
```

---

**Drop Moment (0-500ms after drop)**

```
EXPLOSIVE EFFECTS:
✨ Screen flash (white/bright color)
💥 Particle explosion (500-1000 particles)
📹 Camera zoom out + shake
🎨 Scene transition completion
🌈 Color burst
🔊 Enable all effects at maximum
```

**Example Timeline:**
```
Drop at 0:00.00:
  0.00s - White flash (100% opacity)
  0.05s - Particle burst
  0.10s - Camera shake peak
  0.20s - Flash fades to 0%
  0.50s - Effects stabilize
```

---

**Post-Drop (1-8 seconds after)**

```
Visual Changes:
- Full intensity visuals
- All layers active
- Maximum effect density
- Strong bass-reactive elements
```

---

### Build-up/Drop Pattern Recognition

**Typical EDM Structure:**

```
Intro (0-32 beats)
  └─ Energy: 0.3-0.5
  └─ Visuals: Ambient, building

Build-up (8-16 beats)
  └─ Energy: Rising 0.5 → 0.8
  └─ Visuals: Intensifying, filter sweep
  └─ OSC: /audio/structure[0] = 1

Drop (Instant)
  └─ Energy: Spike to 1.0
  └─ Visuals: Explosive transition
  └─ OSC: /audio/structure[1] = 1

Main Section (32-64 beats)
  └─ Energy: Sustained 0.7-0.9
  └─ Visuals: Full intensity

Break (16-32 beats)
  └─ Energy: Drop to 0.3-0.5
  └─ Visuals: Calm, ambient

[Repeat build-up/drop]
```

---

### Detecting False Positives

**Problem:** Not every energy increase is a build-up

**Solution:** Use multiple conditions

```python
# Good build-up detection
if build_up == 1 AND energy_trend > 0.3 AND duration > 2 seconds:
    trigger_buildup_visuals()

# Good drop detection  
if drop == 1 AND bass_level > 0.7 AND prev_energy < 0.4:
    trigger_drop_visuals()
```

---

## Feature Mapping Examples

### Example 1: Bass Kick → Circle Pulse

**Goal:** Large circle pulses with kick drum

```
Software: Processing/TouchDesigner/Resolume

Map:
  /audio/levels[1] (bass) → Circle Radius

Settings:
  Base radius: 100 pixels
  Peak radius: 400 pixels
  Smoothing: 0.2 (fast response)
  Color: Reactive to bass (red/orange)

Code Example (Processing):
  float bass = osc.get("/audio/levels", 1);
  float radius = map(bass, 0, 1, 100, 400);
  fill(255, bass * 255, 0);  // Red to yellow
  circle(width/2, height/2, radius);
```

---

### Example 2: Highs → Particle Sparkles

**Goal:** Sparkly particles on hi-hats and cymbals

```
Map:
  /audio/levels[6] (air) → Particle Emission Rate

Settings:
  Base rate: 5 particles/sec
  Peak rate: 200 particles/sec
  Particle size: Small (2-5 pixels)
  Color: White/cyan
  Life: 0.3-0.8 seconds

Behavior:
  When air > 0.3:
    - Emit particles from random positions
    - Upward drift with sparkle effect
    - Fast fade-out
```

---

### Example 3: Beat → Scene Flash

**Goal:** White flash on every beat

```
Map:
  /audio/beat[0] (is_onset) → Flash Opacity

Settings:
  Trigger: When is_onset == 1
  Flash color: White (255, 255, 255)
  Peak opacity: 0.3-0.5 (don't blind audience!)
  Decay: Exponential, 200-300ms

Timing:
  Beat detected → Opacity = 0.5
  50ms later → Opacity = 0.25
  100ms later → Opacity = 0.1
  200ms later → Opacity = 0.0
```

---

### Example 4: Build-up → Filter Sweep

**Goal:** Filter sweep during build-up

```
Map:
  /audio/structure[2] (energy_trend) → Low-Pass Filter Cutoff

Settings:
  When energy_trend > 0.2 (build-up):
    - Start cutoff: 200 Hz
    - End cutoff: 20000 Hz
    - Ramp duration: Match build-up length (~4-8 seconds)
  
  Transition: Linear or exponential curve

Visual Effect:
  - Sound becomes brighter as build progresses
  - Creates anticipation
  - Perfect lead-in to drop
```

---

### Example 5: Drop → Camera Shake + Particle Explosion

**Goal:** Explosive effect on drop

```
Map (Multiple):
  /audio/structure[1] (is_drop) → Trigger
  /audio/levels[1] (bass) → Shake intensity

When drop detected:
  1. Camera shake:
     - Amount: 50 pixels
     - Duration: 1 second
     - Decay: Exponential
  
  2. Particle explosion:
     - Count: 1000 particles
     - Direction: Radial outward
     - Speed: Fast (500-800 pixels/sec)
     - Life: 0.5-1.5 seconds
  
  3. Screen flash:
     - Color: White
     - Opacity: 0.7
     - Decay: 300ms

  4. Scene transition:
     - Fade to next scene
     - Duration: 1 beat
```

---

## Genre-Specific Mappings

### EDM / Big Room House

**Characteristics:**
- Strong kicks (4-on-the-floor)
- Prominent build-ups and drops
- High energy

**Recommended Mappings:**
```
Bass (60-250 Hz) → Main visual pulse (large shapes, screen shake)
Beat → Flash effects, layer switching
Build-up → Filter sweep, intensity ramp, particle accumulation
Drop → Explosive transition, all effects maximum
Highs → Sparkle particles, color accents
```

**Scene Switching:**
- Auto-switch every 16-32 beats
- Manual override on build-ups/drops

---

### Techno / Minimal

**Characteristics:**
- Consistent 4/4 rhythm
- Subtle changes
- Hypnotic patterns

**Recommended Mappings:**
```
Bass → Subtle pulse (1.0-1.2x scale)
Beat → Minimal flash or geometry changes
Mid frequencies → Color shifts
Spectral centroid → Slow pattern morphing
```

**Scene Switching:**
- Very slow (every 64-128 beats)
- Morphing transitions (no hard cuts)

---

### Dubstep / Bass Music

**Characteristics:**
- Heavy sub-bass
- Dramatic drops
- Complex rhythms

**Recommended Mappings:**
```
Sub-bass (20-60 Hz) → Deep rumble, screen distortion
Bass → Main wobble effects
Beat → Erratic flashes matching complex rhythms
Drop → Massive explosions, glitch effects
Build-up → Tension builders (grain, noise)
```

**Scene Switching:**
- Drop-triggered only
- Aggressive transitions

---

### Ambient / Downtempo

**Characteristics:**
- Subtle dynamics
- Atmospheric
- Slow changes

**Recommended Mappings:**
```
Overall RMS → Gentle brightness modulation
Spectral centroid → Color palette shifts
Pitch → Harmonic visualization
Energy trend → Slow scene morphing
```

**Scene Switching:**
- Very slow or manual only
- Long crossfades (8-16 beats)

---

## Software-Specific Setup

### Resolume Arena/Avenue

**OSC Setup:**
1. Preferences → OSC → Input
2. Enable OSC Input
3. Port: 9000
4. Click "Auto-learn" or manually map

**Mapping Example:**
```
1. Right-click effect parameter (e.g., "Scale")
2. Select "OSC Input"
3. Play music to trigger OSC
4. Parameter auto-maps to incoming address
5. Adjust min/max ranges as needed
```

**Best Practices:**
- Use Layer Opacity for overall energy
- Use Clip parameters for specific bands
- Use Composition parameters for global effects

---

### TouchDesigner

**OSC Setup:**
```
1. Add "OSC In DAT"
2. Set port: 9000
3. Parse incoming messages
4. Use CHOP channels for control

Example Network:
  oscin1 → oscinDAT1 → parseOSC → channels
  channels → audio/levels/0 (bass)
  bass → multiply → scale parameter
```

**Mapping Script:**
```python
# In Execute DAT
def onReceiveOSC(dat, address, value):
    if address == '/audio/beat':
        if value[0] == 1:  # Beat detected
            op('flash').par.opacity = 1.0
```

---

### Processing

**OSC Setup:**
```java
import oscP5.*;

OscP5 osc;

void setup() {
  size(1920, 1080);
  osc = new OscP5(this, 9000);
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/audio/levels")) {
    float bass = msg.get(1).floatValue();
    // Use bass value
  }
  
  if (msg.checkAddrPattern("/audio/beat")) {
    int beat = msg.get(0).intValue();
    if (beat == 1) {
      // Trigger flash
    }
  }
}
```

---

### Magic Music Visuals

**OSC Setup:**
1. Settings → OSC
2. Enable OSC Input
3. Port: 9000
4. Map in modulators

**Mapping:**
- Use "OSC" modulator type
- Select address from dropdown
- Assign to effect parameters

---

### Synesthesia

**OSC Setup:**
1. Already built to receive audio analysis
2. Default port: 9000
3. Automatic mapping to built-in effects

**Custom Shaders:**
```glsl
// Access OSC in shaders
uniform float syn_BassLevel;  // From /audio/levels
uniform float syn_BeatTime;   // From /audio/beat
uniform float syn_BPM;        // From /audio/bpm
```

---

## Pro Tips

### 1. Layer Your Visuals by Frequency

```
Layer 1 (Bottom): Sub-bass driven (dark, deep)
Layer 2 (Middle): Bass/mid driven (main visuals)
Layer 3 (Top): Highs driven (sparkles, details)
Layer 4 (Flash): Beat triggered (flashes, effects)
```

### 2. Use Smoothing Wisely

```
Fast response (0.1-0.2): Beats, flashes, percussion
Medium response (0.3-0.5): Bass, main elements
Slow response (0.6-0.8): Background, atmosphere
```

### 3. Avoid Visual Fatigue

```
❌ Don't: Flash on every beat for 5 minutes
✅ Do: Flash for 16 beats, rest for 16 beats, repeat

❌ Don't: Maximum intensity all the time
✅ Do: Build and release, create dynamics
```

### 4. Test with Different Music

```
Test your mappings with:
- High energy EDM (stress test)
- Minimal techno (subtle changes)
- Ambient (gentle response)
- Live mixing (transitions)
```

### 5. Have a "Safe" Default

```
If OSC connection lost:
- Fall back to gentle animation
- Don't freeze on last value
- Auto-reconnect when available
```

---

## Troubleshooting

### No OSC Data Received

1. Check audio analyzer is running: `Press '5'` in VJ Console
2. Verify OSC port matches (default 9000)
3. Check firewall settings
4. Test with OSC monitor tool

### Visuals Not Reacting Enough

1. Increase output range (0-2x instead of 0-1x)
2. Reduce smoothing factor
3. Use exponential scaling instead of linear
4. Check if audio is actually playing (levels moving?)

### Visuals Too Chaotic

1. Increase smoothing factor
2. Add threshold (ignore values below 0.2)
3. Limit update rate (skip some frames)
4. Use build-up/drop detection for transitions only

### Build-up/Drop Not Detecting

1. Verify music has clear build-ups (not all music does)
2. Adjust detection thresholds in code
3. Use manual triggers as backup
4. Test with known EDM tracks first

---

## Quick Reference Chart

| OSC Address | Value Range | Update Rate | Best For | Response Speed |
|-------------|-------------|-------------|----------|----------------|
| `/audio/levels[0]` (sub-bass) | 0-1 | 60 Hz | Deep rumble, shake | Fast (0.1-0.2) |
| `/audio/levels[1]` (bass) | 0-1 | 60 Hz | Main pulse, rhythm | Fast (0.2-0.3) |
| `/audio/levels[2-4]` (mids) | 0-1 | 60 Hz | Melody, color | Medium (0.3-0.5) |
| `/audio/levels[5-6]` (highs) | 0-1 | 60 Hz | Sparkles, detail | Fast (0.1-0.3) |
| `/audio/levels[7]` (overall) | 0-1 | 60 Hz | Global intensity | Medium (0.4-0.6) |
| `/audio/spectrum` | 0-1 (×32) | 60 Hz | Detailed viz | Fast (0.1-0.2) |
| `/audio/beat[0]` (onset) | 0 or 1 | 60 Hz | Triggers, flash | Instant |
| `/audio/beat[1]` (flux) | 0-1 | 60 Hz | Onset strength | Fast (0.1) |
| `/audio/bpm` | 60-180 | 60 Hz | Animation sync | Slow (0.7-0.9) |
| `/audio/pitch` | Hz + conf | 60 Hz | Melody viz | Medium (0.3-0.5) |
| `/audio/structure[0]` (buildup) | 0 or 1 | 60 Hz | Build effects | N/A (trigger) |
| `/audio/structure[1]` (drop) | 0 or 1 | 60 Hz | Drop effects | N/A (trigger) |
| `/audio/structure[2]` (energy) | -1 to +1 | 60 Hz | Trends | Slow (0.5-0.7) |
| `/audio/structure[3]` (brightness) | 0-1 | 60 Hz | Timbral shifts | Medium (0.4-0.6) |

---

## Example: Complete Visual Setup

**Goal:** Full reactive visual system for house music

**Layer 1 - Background Pulse:**
```
Source: Large geometric shape
Mapping: /audio/levels[1] (bass) → Scale
Range: 1.0 - 1.5x
Smoothing: 0.3
Color: Dark blue to cyan
```

**Layer 2 - Mid Frequencies:**
```
Source: Particles or smaller shapes
Mapping: /audio/levels[3] (mid) → Density/Count
Range: 50 - 300 particles
Color: Warm tones (yellow/orange)
```

**Layer 3 - High Sparkles:**
```
Source: Small particles
Mapping: /audio/levels[6] (air) → Emission
Range: 0 - 500 particles/sec
Color: White/bright cyan
Life: 0.5 seconds
```

**Layer 4 - Beat Flash:**
```
Source: Full-screen overlay
Trigger: /audio/beat[0] == 1
Effect: White flash
Opacity: 0 → 0.4 → 0 (300ms)
```

**Layer 5 - Scene Control:**
```
Trigger: /audio/structure[1] (drop)
Action: Switch to next scene
Transition: 1-beat crossfade
Scene pool: 4-8 scenes, rotate
```

**Global Effects:**
```
Build-up detected:
  - Increase all layer intensity by 30%
  - Add motion blur
  - Camera zoom in slightly

Drop detected:
  - Flash white (0.7 opacity)
  - Particle explosion (1000 particles)
  - Camera shake (30 pixels, 1 second)
  - Scene transition
```

---

## Conclusion

The key to great audio-reactive visuals:

1. **Start Simple:** Bass → pulse, beat → flash
2. **Layer Effects:** Different frequencies drive different elements
3. **Use Structure:** Let build-ups/drops drive major changes
4. **Test and Refine:** Every track is different
5. **Trust the Analysis:** The OSC data is optimized for VJ use

**Happy VJing! 🎵🎨**

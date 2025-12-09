# Synesthesia OSC Messages Guide

## Which Messages Are Relevant for Programming the Launchpad?

The app automatically filters OSC messages into two categories:

### ✅ Controllable Messages (Can be mapped to pads)

These are messages you can **send TO Synesthesia** to control it. Perfect for Launchpad buttons!

#### 1. **Scenes** - `/scenes/[SceneName]`
**What:** Switch to a specific scene in Synesthesia
**Example:** `/scenes/AlienCavern`, `/scenes/NeonCity`
**Use case:** Each pad triggers a different scene
**Pad mode:** `SELECTOR` (radio buttons) or `ONE_SHOT`

```
Launchpad Layout Example:
┌──────┬──────┬──────┬──────┐
│ Alien│ Neon │Ocean │Forest│
│Cavern│ City │Dream │ Rave │
└──────┴──────┴──────┴──────┘
```

#### 2. **Presets** - `/presets/[PresetName]`
**What:** Switch to a specific preset/effect combination
**Example:** `/presets/Preset1`, `/presets/FastStrobe`
**Use case:** Quick preset switching during performance
**Pad mode:** `SELECTOR` or `ONE_SHOT`

#### 3. **Favorite Slots** - `/favslots/[SlotNumber]`
**What:** Trigger saved favorite scenes/states
**Example:** `/favslots/1`, `/favslots/2`
**Use case:** Quick access to your top 8-16 favorite looks
**Pad mode:** `SELECTOR`

#### 4. **Playlist Control** - `/playlist/[Action]`
**What:** Control Synesthesia's playlist
**Example:** `/playlist/next`, `/playlist/previous`, `/playlist/play`
**Use case:** Navigate through your show's sequence
**Pad mode:** `ONE_SHOT`

#### 5. **Meta Controls** - `/controls/meta/[Parameter]`
**What:** Adjust global visual parameters
**Examples:**
- `/controls/meta/hue` - Color shift (0.0-1.0)
- `/controls/meta/saturation` - Color intensity (0.0-1.0)
- `/controls/meta/brightness` - Overall brightness (0.0-1.0)
- `/controls/meta/contrast` - Contrast adjustment (0.0-1.0)
- `/controls/meta/speed` - Animation speed multiplier (0.0-2.0)
- `/controls/meta/strobe` - Strobe effect (0.0-1.0)

**Use case:** Real-time parameter tweaking
**Pad mode:** `TOGGLE` (on/off) or `ONE_SHOT` (set to specific value)

```
Example Meta Control Mapping:
┌─────────┬─────────┬─────────┬─────────┐
│  Hue    │  Sat    │ Bright  │Contrast │
│ Shift   │  Boost  │  Boost  │  High   │
│ (toggle)│(toggle) │(toggle) │(toggle) │
└─────────┴─────────┴─────────┴─────────┘
```

#### 6. **Global Controls** - `/controls/global/[Parameter]`
**What:** System-wide effects and settings
**Examples:**
- `/controls/global/mirror` - Mirror effect
- `/controls/global/kaleidoscope` - Kaleidoscope effect
- `/controls/global/blur` - Blur amount
- `/controls/global/invert` - Color inversion

**Use case:** Global effect toggles
**Pad mode:** `TOGGLE`

---

### ❌ Non-Controllable Messages (Information only)

These are messages Synesthesia **sends TO you**. You can't control Synesthesia with these, but they're useful for feedback and timing:

#### 1. **Audio Beat** - `/audio/beat/onbeat`, `/audio/beat/offbeat`
**What:** Beat pulse synchronization
**Values:** `[1]` when beat occurs, `[0]` when beat ends
**Use case:**
- Sync Launchpad LED pulses to music
- Trigger time-based effects
- Display beat indicator on status panel

**Example:** Flash a pad color on every beat

#### 2. **BPM** - `/audio/bpm`
**What:** Current tempo of the music
**Values:** Float (e.g., `[128.5]` for 128.5 BPM)
**Use case:**
- Display BPM on screen
- Calculate timing for beat-synced effects
- Adjust animation speeds

#### 3. **Audio Levels** - `/audio/level`, `/audio/level/[band]`
**What:** Audio amplitude analysis
**Values:** Float 0.0-1.0
**Examples:**
- `/audio/level` - Overall level
- `/audio/level/bass` - Bass level
- `/audio/level/mid` - Mid-range level
- `/audio/level/high` - Treble level

**Use case:**
- Drive LED brightness based on volume
- Create audio-reactive light shows
- VU meter display

#### 4. **FFT Data** - `/audio/fft/[bin]`
**What:** Frequency spectrum analysis
**Values:** Float array with frequency bin amplitudes
**Use case:** Advanced audio visualization

#### 5. **Timecode** - `/audio/timecode`
**What:** Current playback position
**Values:** Time in seconds
**Use case:** Timeline synchronization

---

## How Learn Mode Uses This

When you press **L** to enter Learn Mode:

1. **Select a pad** - Press any Launchpad pad
2. **Perform action in Synesthesia** - Click a scene, change preset, adjust hue, etc.
3. **App records messages** - Only **controllable** messages are captured
4. **Choose message** - If multiple controllable messages were received, you pick which one
5. **Configure pad** - Choose mode (SELECTOR/TOGGLE/ONE_SHOT), colors, label

**Example workflow:**
```
1. Press L (enter learn mode)
2. Press pad (2,3) on Launchpad
3. Click "Alien Cavern" scene in Synesthesia
4. App captures: "/scenes/AlienCavern"
5. Configure as SELECTOR, green idle, red active
6. Done! Pad (2,3) now controls that scene
```

---

## Typical Launchpad Programming Strategy

### Layout 1: Scene Grid (8x8)
```
┌────┬────┬────┬────┬────┬────┬────┬────┐
│Sc1 │Sc2 │Sc3 │Sc4 │Sc5 │Sc6 │Sc7 │Sc8 │ ← SELECTOR group "scenes"
├────┼────┼────┼────┼────┼────┼────┼────┤
│Sc9 │Sc10│Sc11│Sc12│Sc13│Sc14│Sc15│Sc16│
├────┼────┼────┼────┼────┼────┼────┼────┤
│Pr1 │Pr2 │Pr3 │Pr4 │Pr5 │Pr6 │Pr7 │Pr8 │ ← SELECTOR group "presets"
├────┼────┼────┼────┼────┼────┼────┼────┤
│Hue │Sat │Brt │Cnt │Spd │Str │Mir │Kal │ ← TOGGLE effects
├────┼────┼────┼────┼────┼────┼────┼────┤
│Fav1│Fav2│Fav3│Fav4│Fav5│Fav6│Fav7│Fav8│ ← ONE_SHOT favorites
└────┴────┴────┴────┴────┴────┴────┴────┘
```

### Layout 2: Performance Grid
```
Top Row (ONE_SHOT quick actions):
┌─────┬─────┬─────┬─────┬─────┬─────┬─────┬─────┐
│Next │Prev │Play │Stop │Blur+│Blur-│Rst  │Blk  │
└─────┴─────┴─────┴─────┴─────┴─────┴─────┴─────┘

Main Grid:
┌────────────────┬────────────────┐
│                │                │
│  Main Scenes   │  Effects       │
│  (SELECTOR)    │  (TOGGLE)      │
│                │                │
│                │                │
│  16 scenes     │  Hue, Sat,     │
│  4x4 grid      │  Brightness,   │
│                │  Strobe, etc.  │
│                │                │
└────────────────┴────────────────┘

Right Column (Global toggles):
┌────┐
│Mir │ ← Mirror toggle
├────┤
│Kal │ ← Kaleidoscope toggle
├────┤
│Inv │ ← Invert colors toggle
├────┤
│... │
└────┘
```

---

## Message Frequency Guide

Understanding how often messages arrive helps with programming:

| Message Type | Frequency | Should Map? |
|--------------|-----------|-------------|
| `/scenes/*` | Only when scene changes (~0.1-1/sec) | ✅ Yes - Main control |
| `/presets/*` | Only when preset changes (~0.1-1/sec) | ✅ Yes - Main control |
| `/controls/meta/*` | When adjusting parameters (~1-10/sec) | ✅ Yes - Real-time control |
| `/controls/global/*` | When toggling effects (~0.1-1/sec) | ✅ Yes - Effect control |
| `/audio/beat/onbeat` | On every beat (~2-4/sec at 120-240 BPM) | ❌ No - Feedback only |
| `/audio/bpm` | When tempo changes (~0.01-0.1/sec) | ❌ No - Display only |
| `/audio/level` | Continuous (~30-100/sec) | ❌ No - Too frequent |
| `/audio/fft/*` | Continuous (~30-100/sec) | ❌ No - Too frequent |

---

## OSC Monitor Panel Legend

When you run the app, the OSC Monitor panel shows:

```
Total: 1523  Unique: 12 (✓=controllable ·=other)
✓ /scenes/AlienCavern [] ×1          ← Green ✓ = Can map to pad
· /audio/beat/onbeat [1] ×450        ← Cyan · = Info only
✓ /controls/meta/hue [0.75] ×3       ← Green ✓ = Can map to pad
· /audio/bpm [128.5] ×1              ← Cyan · = Info only
✓ /presets/Preset1 [] ×1             ← Green ✓ = Can map to pad
```

**Look for Green ✓ messages** when learning - those are the ones you want!

---

## Common Synesthesia OSC Patterns

### Scene Messages
```
/scenes/AlienCavern []
/scenes/NeonCity []
/scenes/OceanDream []
/scenes/ForestRave []
```

### Preset Messages
```
/presets/Preset1 []
/presets/Preset2 []
/presets/FastStrobe []
/presets/SlowFade []
```

### Meta Control Messages
```
/controls/meta/hue [0.5]           # 0.0 = red, 0.33 = green, 0.66 = blue
/controls/meta/saturation [0.8]    # 0.0 = grayscale, 1.0 = full color
/controls/meta/brightness [1.0]    # 0.0 = black, 1.0 = normal
/controls/meta/strobe [0.5]        # 0.0 = off, 1.0 = max strobe
/controls/meta/speed [1.5]         # 0.5 = slow, 1.0 = normal, 2.0 = fast
```

### Beat Messages (informational)
```
/audio/beat/onbeat [1]     # Beat just hit
/audio/beat/onbeat [0]     # Beat ended
/audio/beat/offbeat [1]    # Offbeat hit
/audio/bpm [128.5]         # Current BPM
```

---

## Tips for Effective Programming

### 1. **Start with Scenes**
Map your most-used scenes first. Use SELECTOR mode so only one scene is active at a time.

### 2. **Add Effects as Toggles**
Meta controls work great as toggles:
- Idle state: Normal value (e.g., hue=0.0)
- Active state: Modified value (e.g., hue=0.5)

### 3. **Use Color Coding**
- **Scenes:** Unique colors for each (helps identify visually)
- **Effects:** Yellow/Orange when active
- **Presets:** Blue/Purple family
- **Favorites:** Green family

### 4. **Group Related Functions**
Keep scenes together, effects together, presets together. Makes it easier to remember during live performance.

### 5. **Test with OSC Monitor**
Before learning, click around in Synesthesia and watch the OSC Monitor panel. This shows you exactly what messages are available.

---

## Summary

**Map these to pads (Controllable ✅):**
- `/scenes/*` - Scene selection
- `/presets/*` - Preset selection
- `/favslots/*` - Favorite slots
- `/playlist/*` - Playlist control
- `/controls/meta/*` - Meta parameters
- `/controls/global/*` - Global effects

**Don't map these (Informational ❌):**
- `/audio/beat/*` - Beat sync (too frequent, feedback only)
- `/audio/bpm` - BPM display (info only)
- `/audio/level*` - Audio levels (too frequent)
- `/audio/fft/*` - FFT data (too frequent)
- `/audio/timecode` - Timecode (info only)

**The OSC Monitor panel makes this easy:**
- Green ✓ = Controllable, map to pads
- Cyan · = Informational, don't map

Happy programming! 🎛️

# Audio-Reactive Visualization Algorithms

Six algorithms that transform raw audio into expressive visual parameters,
plus a layered architecture for combining them. Together they cover micro
(per-hit), meso (per-bar), and macro (per-section) musical structure.

---

## Algorithm 1: Perceptual Energy Band Decomposition

### Problem
Raw FFT bins are linear but human hearing is logarithmic. The bottom 5% of
bins contain everything from sub-bass to mid-range while the top 80% is
ultrasonic garbage. Mel bands help but aren't granular enough for EDM where
producers carefully separate kick, snare, lead, and hats by frequency.

### Algorithm

Split the spectrum into **7 perceptually meaningful bands** tuned for EDM:

| Band | Hz Range | Musical Content | Visual Role |
|------|----------|----------------|-------------|
| **sub_bass** | 20–60 | 808 rumble, sub drops | Screen shake, deep pulse |
| **kick** | 60–250 | Kick drum body | Heavy impact, scale pulse |
| **snare_body** | 250–500 | Snare body, bass guitar | Mid-range texture |
| **mid** | 500–2000 | Vocals, melodic content | Shape complexity |
| **presence** | 2000–4000 | Attack transients, presence | Edge sharpness |
| **high** | 4000–12000 | Hi-hats, cymbals, air | Sparkle, fine detail |
| **air** | 12000–20000 | Brilliance, shimmer | Subtle shimmer |

For each band, compute RMS energy from the relevant FFT bins. Then apply
**asymmetric smoothing** — the key insight that makes visualizers satisfying:

```
if new_value > smoothed:
    smoothed += (new_value - smoothed) * attack_alpha   # fast: 0.6–0.8
else:
    smoothed += (new_value - smoothed) * release_alpha  # slow: 0.05–0.15
```

This mimics analog VU meters: snap up on transients, glide down gracefully.

### Implementation

```python
BAND_EDGES_HZ = [20, 60, 250, 500, 2000, 4000, 12000, 20000]

def hz_to_fft_bin(hz, sample_rate, win_size):
    return int(hz * win_size / sample_rate)

# Convert Hz edges to FFT bin indices
edges = [hz_to_fft_bin(hz, 44100, 1024) for hz in BAND_EDGES_HZ]

# For each frame, compute per-band RMS from FFT magnitudes
for i in range(7):
    lo, hi = edges[i], edges[i + 1]
    band_mags = fft_magnitudes[lo:hi]
    band_energy[i] = np.sqrt(np.mean(band_mags ** 2))
```

### Why it works for EDM
EDM producers spend enormous effort on frequency separation. The kick lives
in sub-bass/kick bands, snare in snare_body, lead synth in mid, hats in high.
Each visual element driven by a band naturally responds to the "right"
instrument without any beat detection or source separation needed.

---

## Algorithm 2: Onset-Classified Beat Pulse

### Problem
A single onset detector treats kicks, snares, and hi-hats identically.
But kicks should create heavy visual impacts that linger, snares should
create medium accents, and hi-hats should create fast little flickers.

### Algorithm

Run **three parallel onset detectors** with different frequency pre-filters:

| Detector | Pre-filter | Method | Catches |
|----------|-----------|--------|---------|
| **kick** | Low-pass < 150 Hz | Energy | Kick drums only |
| **snare** | Band-pass 200–1000 Hz | Complex | Snares, claps |
| **hat** | High-pass > 3000 Hz | HFC | Hi-hats, cymbals |

For each detected onset, generate a **pulse envelope** — jumps to 1.0
instantly, then decays exponentially with instrument-specific rates:

```python
# Decay rates (per frame at 30fps):
KICK_DECAY  = 0.88   # Slow — heavy visual punch, lingers
SNARE_DECAY = 0.92   # Medium — accent, moderate linger
HAT_DECAY   = 0.96   # Fast — sharp flicker, quick fade

# On each frame:
if kick_onset:  kick_pulse = 1.0
if snare_onset: snare_pulse = 1.0
if hat_onset:   hat_pulse = 1.0

kick_pulse  *= KICK_DECAY
snare_pulse *= SNARE_DECAY
hat_pulse   *= HAT_DECAY
```

### Beat Phase Accumulator

Combine with BPM tracking to create a **beat phase** — a value cycling
0.0 → 1.0 every beat:

```python
beat_phase += bpm / (60.0 * fps)   # Free-running accumulator
beat_phase %= 1.0

# On detected beat, apply soft correction (don't snap):
if beat_detected:
    phase_error = 0.0 - beat_phase  # We expect phase ≈ 0 on beat
    if abs(phase_error) > 0.5:
        phase_error -= np.sign(phase_error)  # Wrap around
    beat_phase += phase_error * 0.3  # Gentle correction
```

The phase **free-runs** between detections so visuals maintain rhythm during
breakdowns. Only small corrections on beat detection keep it in sync.

### Visual mapping
- `kick_pulse` → screen shake, scale burst, bass glow
- `snare_pulse` → flash, color accent, particle burst
- `hat_pulse` → sparkle, edge highlight, shimmer
- `beat_phase` → master clock for all periodic motion (rotation, oscillation)

---

## Algorithm 3: Spectral Centroid Chaser

### Problem
Individual frequency bands give detail but miss the overall character.
During a bass-heavy drop the centroid plummets; during a hi-hat build-up
it rises; during a full chorus it sits in the middle. One number captures
the "mood" of the moment.

### Algorithm

The spectral centroid is the "center of mass" of the frequency spectrum:

```python
freqs = np.arange(len(fft_magnitudes)) * sample_rate / win_size
centroid_hz = np.sum(freqs * fft_magnitudes) / (np.sum(fft_magnitudes) + 1e-10)
centroid_norm = centroid_hz / (sample_rate / 2)  # Normalize to 0–1
```

Track it with asymmetric smoothing (fast attack, slow release). Then also
compute its **velocity** — the rate of change:

```python
centroid_velocity = centroid_norm - prev_centroid_norm
# Positive = brightening (filter opening, treble entering)
# Negative = darkening (filter closing, bass drop)
```

### Visual mapping

| Centroid Value | Musical Moment | Visual Effect |
|---------------|---------------|---------------|
| Low (< 0.3) | Bass drop, sub-heavy | Warm colors, center-concentrated, sharp |
| Mid (0.3–0.6) | Full mix, chorus | Balanced, medium spread |
| High (> 0.6) | Build-up, hi-hat driven | Cool colors, edge-spread, diffuse |

| Centroid Velocity | Musical Moment | Visual Effect |
|------------------|---------------|---------------|
| Rising fast | Filter sweep up, build | Expanding, brightening, accelerating |
| Falling fast | Drop, filter close | Contracting, darkening, impact |
| Stable | Sustained section | Smooth motion, no surprises |

The centroid provides **macro mood** while individual bands provide
**micro detail**. Together they create layered responsiveness.

---

## Algorithm 4: Spectral Flux Beat Anticipation

### Problem
Energy and flux are different. A sustained chord has high energy but low flux.
A single drum hit has massive flux. Frame-by-frame flux is useful but misses
the narrative arc of tension → release that defines EDM structure.

### Algorithm

**Step 1: Spectral Flux (per-frame novelty)**

Compute the sum of *positive* differences between consecutive FFT frames
(positive only — we care about energy arriving, not leaving):

```python
flux = np.sum(np.maximum(current_fft - previous_fft, 0))
flux_normalized = flux / (running_average_flux + 1e-10)
```

This gives a **novelty score**: high when something new happens, low during
sustained or repetitive sections.

**Step 2: Split by frequency**

Compute flux separately for low and high frequency ranges:

```python
low_flux  = sum(max(curr[:n_low] - prev[:n_low], 0))   # Bottom 20% bins
high_flux = sum(max(curr[n_low:] - prev[n_low:], 0))    # Top 80% bins
```

- `low_flux` spikes on kick re-entry after breakdown → heavy visual impact
- `high_flux` spikes on cymbal crashes, filter sweeps → sparkly visual events

**Step 3: Flux Accumulator (tension/release)**

Build a value that slowly fills during low-flux periods and discharges on
high-flux moments:

```python
# Accumulate tension during calm periods
if flux_normalized < 1.0:
    tension += (1.0 - flux_normalized) * charge_rate

# Discharge on events
if flux_normalized > threshold:
    release_energy = tension * flux_normalized
    tension *= 0.3  # Dump most of the stored energy

# Natural decay prevents infinite buildup
tension *= 0.995
tension = min(tension, 1.0)
```

During an EDM build-up (repetitive hi-hats, rising filter), flux is moderate,
so the accumulator fills. When the drop hits, flux spikes and dumps all stored
energy. This creates **anticipation → payoff** that mirrors the music's
narrative.

### Visual mapping
- `flux_normalized` → animation speed, complexity, turbulence
- `low_flux` → screen shake, heavy impacts, bass burst
- `high_flux` → particle scatter, color shift, shimmer burst
- `tension` → visual compression, desaturation, slow buildup effects
- `release_energy` → explosion, color inversion, scale burst, camera shake

---

## Algorithm 5: MFCC Timbral Space Navigator

### Problem
MFCCs (Mel-Frequency Cepstral Coefficients) capture *timbre* — the quality
that distinguishes a violin from a trumpet playing the same note. They're
computed every frame but almost never used for visualization.

### Algorithm

**Step 1: Compute 13 MFCCs per frame** (aubio does this already).

Discard coefficient 0 (overall loudness — redundant with RMS).
The remaining 12 coefficients form a point in 12-dimensional timbral space.

**Step 2: Track timbral distance**

Compare the current MFCC vector against a running average:

```python
# Running average of MFCC vectors
mfcc_avg = mfcc_avg * 0.99 + current_mfcc * 0.01

# Euclidean distance from average
mfcc_distance = np.sqrt(np.sum((current_mfcc[1:] - mfcc_avg[1:]) ** 2))
```

- **Low distance** → stable timbre (sustained loop, repetitive section)
- **High distance** → timbre change (new instrument, section change, drop)

**Step 3: Direct timbral mapping**

Take MFCCs 2, 3, 4 and map directly to visual parameters:

| MFCC Coefficient | Timbral Meaning | Visual Mapping |
|-----------------|----------------|----------------|
| MFCC[1] | Spectral balance (bright vs dark) | Hue rotation speed |
| MFCC[2] | Spectral shape (broad vs narrow) | Particle size / scale |
| MFCC[3] | Fine spectral detail | Background brightness |

This creates an **implicit mapping** where different timbral textures
automatically produce different visual textures. A pad section looks
different from a lead section without any manual programming — the
mapping emerges from the music's own structure.

### Visual mapping
- `mfcc_distance` → scene energy, variation, complexity
- `mfcc[1]` → hue rotation speed (bright timbre = fast color cycle)
- `mfcc[2]` → element scale (broad timbre = large elements)
- `mfcc[3]` → background brightness (detailed timbre = brighter bg)
- Distance spike → scene transition, palette change, structure shift

---

## Algorithm 6: Phase-Locked Oscillator Bank

### Problem
EDM is fundamentally repetitive and rhythmic. Individual beat triggers are
binary (on/off) — they can't express the continuous, hypnotic pulse that
makes professional LED walls at festivals feel so unified. You need oscillators
that breathe with the music at multiple timescales simultaneously.

### Algorithm

Use the BPM to create a **bank of harmonically related oscillators** — sine
waves at musically meaningful frequencies:

| Oscillator | Frequency | Musical Feel | Visual Role |
|-----------|-----------|-------------|-------------|
| **half** | BPM/120 Hz | Half-time sway | Slow camera drift, color cycle |
| **beat** | BPM/60 Hz | Quarter note | Global scale pulse, breathing |
| **double** | BPM/30 Hz | Eighth note | Rapid flicker, particle rate |
| **triplet** | BPM/40 Hz | Triplet feel | Polyrhythmic drift |
| **sixteenth** | BPM/15 Hz | Sixteenth note | Texture scroll, noise modulation |

Each oscillator is a phase accumulator:

```python
class OscillatorBank:
    def __init__(self):
        self.phases = np.zeros(5)          # 0.0–1.0 for each oscillator
        self.multipliers = [0.5, 1.0, 2.0, 1.5, 4.0]  # Relative to beat
        self.corrections = [0.1, 0.3, 0.08, 0.05, 0.03]  # Lock tightness

    def update(self, bpm, beat_detected, dt):
        beat_freq = bpm / 60.0
        for i, mult in enumerate(self.multipliers):
            self.phases[i] += beat_freq * mult * dt
            self.phases[i] %= 1.0

        # On beat, nudge toward ideal phase
        if beat_detected:
            for i in range(len(self.phases)):
                # Ideal phase is 0.0 on beat (for beat-multiple oscillators)
                ideal = 0.0
                error = ideal - self.phases[i]
                # Wrap error to [-0.5, 0.5]
                if error > 0.5: error -= 1.0
                if error < -0.5: error += 1.0
                self.phases[i] += error * self.corrections[i]
                self.phases[i] %= 1.0

    def get_values(self):
        """Return sine wave values for each oscillator, range [-1, 1]."""
        return np.sin(self.phases * 2 * np.pi)
```

### The magic

Because the oscillators are harmonically related and phase-locked to the
music, everything moves in sync but at **different scales of time**:

- The beat oscillator makes everything breathe on every kick
- The half-time oscillator creates slow, sweeping color changes
- The sixteenth oscillator creates high-frequency texture vibration
- The triplet oscillator introduces just enough polyrhythmic tension

When the DJ changes BPM, all oscillators smoothly adjust together. During
breakdowns, the free-running phases maintain rhythm so nothing stutters.
The tight lock on the beat oscillator keeps the visual pulse anchored,
while the loose lock on higher harmonics lets them drift musically.

### Visual mapping
- `osc_half` → slow color cycle, camera sway, background morph
- `osc_beat` → global scale pulse (everything breathes), brightness pump
- `osc_double` → rapid particle emission, flicker rate
- `osc_triplet` → rotation speed modulation, polyrhythmic accents
- `osc_sixteenth` → texture scrolling, noise seed, fine-grain animation

---

## Layered Architecture: Putting It All Together

The proven architecture used by MilkDrop, Resolume, and Synesthesia.
Four layers with strict separation of concerns.

### Layer 1: Analysis

Runs all six algorithms in parallel every frame, producing **control
signals** — smoothed band energies, classified onset triggers, centroid,
flux accumulator, MFCC distance, oscillator phases.

Think of these as a mixer console where every fader is being ridden
automatically by the music.

```
Raw Audio (512 samples @ 44.1kHz)
    │
    ├─► FFT (1024-point)
    │     ├──► Algorithm 1: 7 perceptual energy bands
    │     ├──► Algorithm 3: spectral centroid + velocity
    │     └──► Algorithm 4: spectral flux (full + per-band) + accumulator
    │
    ├─► Aubio Onset Detectors
    │     └──► Algorithm 2: classified pulses (kick/snare/hat) + envelopes
    │
    ├─► Aubio Tempo
    │     ├──► Algorithm 2: beat phase accumulator
    │     └──► Algorithm 6: phase-locked oscillator bank (5 harmonics)
    │
    └─► Aubio MFCC
          └──► Algorithm 5: timbral distance + direct mapping
```

### Layer 2: Mapping

Connects control signals to visual parameters. This is where artistic
decisions live.

**The crucial principle**: never map one signal to one parameter 1:1.
Always **combine multiple signals** with different weights:

```python
# Good: organic, multi-source motion
scale = (0.8 * kick_pulse
       + 0.15 * band_sub_bass
       + 0.05 * osc_beat)

# Bad: mechanical, one-dimensional
scale = kick_pulse
```

Multi-source mapping makes visual motion feel **organic** rather than
mechanical because real musical moments always involve multiple
simultaneous sonic events.

Example mapping table for a single visualization:

| Visual Parameter | Primary Signal (weight) | Secondary (weight) | Accent (weight) |
|-----------------|------------------------|--------------------|--------------------|
| **Global scale** | kick_pulse (0.7) | band_sub_bass (0.2) | osc_beat (0.1) |
| **Color hue** | centroid (0.5) | mfcc[1] (0.3) | osc_half (0.2) |
| **Turbulence** | flux_norm (0.6) | band_high (0.2) | hat_pulse (0.2) |
| **Brightness** | rms (0.4) | tension (0.3) | osc_beat (0.3) |
| **Complexity** | mfcc_distance (0.5) | flux_accum (0.3) | band_mid (0.2) |
| **Sparkle** | hat_pulse (0.6) | high_flux (0.2) | band_air (0.2) |

### Layer 3: Smoothing

Applies fast-attack / slow-decay envelope to **every** mapped parameter
before it reaches the renderer. This is non-negotiable:

```python
def smooth(current, target, attack=0.7, release=0.1):
    alpha = attack if target > current else release
    return current + (target - current) * alpha
```

- **Without smoothing**: everything looks twitchy and amateur
- **With smoothing**: everything breathes and flows

Every parameter gets its own attack/release tuned to its visual role:
- Scale/position: fast attack (0.7), medium release (0.15)
- Color: medium attack (0.4), slow release (0.05)
- Turbulence: fast attack (0.8), fast release (0.3)
- Background: slow attack (0.2), very slow release (0.02)

### Layer 4: Rendering

Takes smoothed parameters and draws the frame. **This layer knows nothing
about audio** — it just receives numbers and makes pixels.

This separation is what makes the system flexible. The same analysis
pipeline feeds every visualization mode. The same oscillator bank drives
plasma, particles, and fractals. Swap the renderer without touching
analysis. Swap the mapping without touching rendering.

```python
def render_visualization(fb, params, frame, lut, state):
    """Pure rendering — no audio objects, just float parameters."""
    scale = params['scale']       # 0–1, already smoothed
    hue = params['hue']           # 0–1
    turbulence = params['turb']   # 0–1
    brightness = params['bright'] # 0–1
    sparkle = params['sparkle']   # 0–1
    # ... draw pixels using only these abstract parameters
```

### Feature hierarchy

| Timescale | Algorithm | What it drives |
|-----------|-----------|---------------|
| **Per-hit** (ms) | 2: Onset pulses | Flashes, spawns, impacts |
| **Per-beat** (~500ms) | 2: Beat phase, 6: Oscillators | Rotation, pulse, periodic motion |
| **Per-bar** (2–4s) | 1: Band energy, 6: Half-time osc | Continuous size, brightness, color |
| **Per-phrase** (8–16s) | 4: Flux accumulator | Tension/release, scene energy |
| **Per-section** (30–60s) | 5: MFCC distance | Scene transitions, palette morphs |
| **Continuous** | 3: Centroid + velocity | Global mood, warmth vs brightness |

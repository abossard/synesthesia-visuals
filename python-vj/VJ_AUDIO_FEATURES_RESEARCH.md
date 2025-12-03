# VJ Audio Features Research - Essentia Implementation Guide

## Research Summary: Best Audio Features for VJ Applications

Based on comprehensive research into Essentia and real-time VJ applications, here are the most important audio features and why they matter for visual performances.

---

## Essential VJ Metrics (Priority Order)

### 1. **Beat Detection & BPM** ⭐⭐⭐⭐⭐
**Why Critical for VJ:**
- Synchronizes visual transitions, flashes, and animations with music pulse
- Essential for creating rhythmic, danceable visual experiences
- Triggers strobing effects, jump cuts, color changes on each beat
- Core foundation for EDM/Techno/House visual sync

**Essentia Implementation:**
- `RhythmExtractor2013` - Primary algorithm for beat tracking
- `BeatTrackerDegara` - Optimized for real-time/low-latency
- `OnsetDetection` - For percussive hit detection

**OSC Output:**
```
/audio/beat [is_onset, confidence]
/audio/bpm [tempo, confidence]
```

---

### 2. **Energy (Overall Intensity)** ⭐⭐⭐⭐⭐
**Why Critical for VJ:**
- Represents musical "intensity" - build-ups, drops, breakdowns
- Scales brightness, complexity, chaos of visuals
- Creates dramatic visual responses to energy changes
- Perfect for tracking build-ups and drops in EDM

**Essentia Implementation:**
- RMS energy calculation from time-domain signal
- Sum of frequency band energies
- `LowLevelSpectralExtractor` provides energy metrics

**OSC Output:**
```
/audio/levels [sub_bass, bass, mid, high, overall_rms]
/audio/structure [is_buildup, is_drop, energy_trend]
```

---

### 3. **Frequency Bands (Spectral Energy)** ⭐⭐⭐⭐⭐
**Why Critical for VJ:**
- Independent control of bass, mids, treble visual elements
- Bass drives low-freq shapes, treble drives sparkles/particles
- Allows multi-layered visual responses to different instruments
- Essential for frequency-reactive color palettes

**Essentia Implementation:**
- Mel bands, Bark bands, ERB bands
- Custom frequency band extraction from FFT
- Typically 7 bands: sub-bass, bass, low-mid, mid, high-mid, presence, air

**Frequency Ranges (Recommended for VJ):**
```
Sub-bass:  20-60 Hz    → Deep pulses, screen shake
Bass:      60-250 Hz   → Main rhythm, large shapes
Low-mid:   250-500 Hz  → Body, warmth
Mid:       500-2000 Hz → Vocals, melody
High-mid:  2000-4000 Hz→ Brightness, clarity
Presence:  4000-6000 Hz→ Air, definition
Air:       6000-20000Hz→ Sparkles, particles
```

**OSC Output:**
```
/audio/levels [7 bands + overall]
```

---

### 4. **Spectral Centroid (Brightness)** ⭐⭐⭐⭐
**Why Critical for VJ:**
- "Center of mass" of spectrum - measures timbral brightness
- Higher values = brighter, sharper sounds (hi-hats, synths)
- Lower values = darker, warmer sounds (bass, pads)
- Animates color palettes between warm/cool
- Affects visual "sharpness" and morphing

**Essentia Implementation:**
- `Centroid` algorithm in standard/streaming modes
- Normalized to 0-1 range (divide by Nyquist frequency)

**Visual Mappings:**
```
Low centroid  → Warm colors, soft shapes, slow movement
High centroid → Cool colors, sharp edges, fast movement
```

**OSC Output:**
```
/audio/structure [buildup, drop, energy_trend, brightness_trend]
```

---

### 5. **Spectral Flux (Novelty/Onset Strength)** ⭐⭐⭐⭐
**Why Critical for VJ:**
- Measures spectral change - how different this frame is from previous
- Higher values = more "action" happening in the music
- Detects percussive hits, transients, texture changes
- Triggers sudden visual effects, geometric bursts

**Essentia Implementation:**
- `Flux` algorithm
- Used internally by `OnsetDetection`
- Can be calculated manually: sum of positive spectral differences

**Visual Mappings:**
```
High flux → Trigger effects, particle bursts, transitions
Low flux  → Smooth, continuous visuals
```

**OSC Output:**
```
/audio/beat [is_onset, flux_strength]
```

---

### 6. **Loudness (RMS/Peak)** ⭐⭐⭐⭐
**Why Critical for VJ:**
- Simple yet powerful - direct measure of volume
- Modulates overall visual intensity, contrast, scaling
- Useful for crowd response effects
- Complements energy for dynamic range control

**Essentia Implementation:**
- Simple RMS calculation from signal
- `Loudness` algorithm for perceptual loudness
- Peak detection for transients

**OSC Output:**
```
/audio/levels [... overall_rms]
```

---

### 7. **Pitch Detection** ⭐⭐⭐
**Why Important for VJ:**
- Detects melodic content, fundamental frequency
- Maps pitch to color, position, or effect parameters
- Creates harmonic visual responses
- Useful for melody-driven tracks

**Essentia Implementation:**
- `PitchYin` - YIN algorithm (time-domain, accurate)
- `PitchYinFFT` - FFT-based variant (faster)
- `PredominantPitchMelodia` - For complete melodies

**Configuration:**
```python
pitch = es.PitchYin(
    frameSize=2048,
    sampleRate=44100,
    minFrequency=20,
    maxFrequency=2000,
    tolerance=0.15
)
```

**OSC Output:**
```
/audio/pitch [frequency_hz, confidence]
```

---

### 8. **MFCC (Mel-Frequency Cepstral Coefficients)** ⭐⭐
**Why Useful for VJ:**
- Compact timbral representation
- Can distinguish between instrument types
- Useful for advanced classification/matching
- Less intuitive for direct visual mapping

**Essentia Implementation:**
```python
mfcc = es.MFCC(
    sampleRate=44100,
    numberCoefficients=13,
    numberBands=40
)
```

**Note:** Often used for ML classification rather than direct visual control.

---

## Recommended OSC Schema for VJ Applications

Based on research and common VJ workflows:

```
/audio/levels [sub, bass, lmid, mid, hmid, pres, air, rms]
  → 8 floats, 0-1 range, ~60fps
  → Primary visual control

/audio/spectrum [32 bins]
  → 32 floats, normalized magnitude
  → For detailed frequency visualization

/audio/beat [is_onset, flux]
  → int (0/1), float (0-1)
  → Trigger effects on beat

/audio/bpm [tempo, confidence]
  → float (60-180), float (0-1)
  → Tempo sync, clock rate

/audio/pitch [freq_hz, confidence]
  → float (Hz), float (0-1)
  → Melodic mapping

/audio/structure [buildup, drop, energy_trend, brightness]
  → int, int, float (-1 to +1), float (0-1)
  → High-level structure detection
```

---

## Essentia vs Aubio Comparison

| Feature | Essentia | Aubio | Winner |
|---------|----------|-------|--------|
| Beat tracking | RhythmExtractor2013, BeatTrackerDegara | tempo() | **Essentia** (more options) |
| Onset detection | OnsetDetection (multiple methods) | onset() | **Tie** (both excellent) |
| Pitch detection | PitchYin, PitchYinFFT, Melodia | pitch() | **Essentia** (more algorithms) |
| Spectral features | Extensive (centroid, flux, rolloff, etc) | Limited | **Essentia** |
| MFCC | Built-in with full control | Not available | **Essentia** |
| Real-time | Streaming mode optimized | Callback-optimized | **Aubio** (simpler) |
| Documentation | Comprehensive with examples | Good but smaller | **Essentia** |
| Installation | `pip install essentia` | `pip install aubio` | **Tie** |
| Community | Large MIR community | Smaller but active | **Essentia** |

**Conclusion:** Essentia is more feature-rich and better for VJ applications needing diverse audio features.

---

## Implementation Strategy for VJ Console

### Core Features to Implement:

1. **Beat Detection** (BeatTrackerDegara for low latency)
2. **7-Band Energy** (Custom frequency bands from FFT)
3. **BPM Estimation** (RhythmExtractor2013)
4. **Spectral Centroid** (Brightness measure)
5. **Spectral Flux** (Novelty/onset strength)
6. **RMS Energy** (Overall loudness)
7. **Pitch Detection** (PitchYin, optional)

### Essentia Real-Time Pattern:

```python
import essentia.standard as es
import sounddevice as sd
import numpy as np

# Create algorithms once (outside callback)
window = es.Windowing(type='hann')
spectrum = es.Spectrum()
centroid = es.Centroid()
beat_tracker = es.BeatTrackerDegara()

def audio_callback(indata, frames, time, status):
    mono = np.mean(indata, axis=1).astype('float32')
    
    # Process frame
    w = window(mono)
    spec = spectrum(w)
    brightness = centroid(spec)
    
    # Send to OSC...
```

### Performance Targets:

- **Latency:** <30ms end-to-end
- **Frame rate:** 60 fps (one analysis per audio block)
- **Block size:** 512 samples @ 44.1kHz = ~11.6ms
- **CPU usage:** <10% on modern hardware

---

## References

- [Essentia Documentation](https://essentia.upf.edu/)
- [Beat Detection Tutorial](https://essentia.upf.edu/tutorial_rhythm_beatdetection.html)
- [PitchYin Reference](https://essentia.upf.edu/reference/std_PitchYin.html)
- [VJ Audio Reactive Tools](https://vjloops.ai/audio-reactive-vj-tools/)
- [Audio Analysis for Music Visualization](https://audioreactivevisuals.com/audio-analysis.html)

---

## Next Steps for Implementation

1. ✅ Replace aubio imports with Essentia
2. ✅ Implement BeatTrackerDegara for onset detection
3. ✅ Keep custom frequency band extraction (already optimal)
4. ✅ Add Spectral Centroid calculation
5. ✅ Implement pitch detection with PitchYin
6. ✅ Update benchmark to measure Essentia components
7. ✅ Test and validate all features
8. ✅ Update documentation

**Key Advantage:** Essentia provides all features in one library with consistent API and better documentation than mixing multiple libraries.

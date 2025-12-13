# Audio Analysis

Real-time audio analysis engine for VJ applications, processing at ~60 fps with EDM-optimized features sent via OSC.

## Quick Start

```bash
cd python-vj
pip install -r requirements.txt
python vj_console.py   # Press 'A' to toggle analyzer, '5' to view
```

**macOS Audio Setup:**
1. Install BlackHole: `brew install blackhole-2ch`
2. Create Multi-Output Device in Audio MIDI Setup (speakers + BlackHole)
3. Set as system default output
4. VJ Console auto-detects BlackHole for input

---

## OSC Output Reference

All features sent to `127.0.0.1:9000` at ~60 Hz.

### Core Addresses

| Address | Format | Description |
|---------|--------|-------------|
| `/audio/levels` | 8 floats | `[sub_bass, bass, low_mid, mid, high_mid, presence, air, rms]` (0-1) |
| `/audio/spectrum` | 32 floats | Downsampled FFT bins (0-1) |
| `/audio/beat` | int, float | `[is_onset, flux]` - beat trigger + novelty strength |
| `/audio/bpm` | 2 floats | `[bpm, confidence]` (60-180 BPM) |
| `/audio/pitch` | 2 floats | `[frequency_hz, confidence]` |
| `/audio/structure` | 4 values | `[is_buildup, is_drop, energy_trend, brightness]` |
| `/audio/spectral` | 3 floats | `[centroid_norm, rolloff_hz, flux]` |

### EDM-Specific Features (14 total)

| Address | Type | Range | Use Case |
|---------|------|-------|----------|
| `/beat` | float | 0/1 | Flash/strobe triggers |
| `/bpm` | float | 60-180 | Animation sync |
| `/beat_conf` | float | 0-1 | Fade by reliability |
| `/energy` | float | 0+ | Raw intensity |
| `/energy_smooth` | float | 0-1 | EMA-smoothed loudness |
| `/beat_energy` | float | 0-1 | Global beat loudness |
| `/beat_energy_low` | float | 0-1 | Kick drum visual |
| `/beat_energy_high` | float | 0-1 | Hi-hat sparkles |
| `/brightness` | float | 0-1 | Spectral centroid |
| `/noisiness` | float | 0-1 | Tonal vs noise |
| `/bass_band` | float | 0-1 | 60-250 Hz energy |
| `/mid_band` | float | 0-1 | 250-4000 Hz energy |
| `/high_band` | float | 0-1 | 4000-20kHz energy |
| `/dynamic_complexity` | float | 0+ | Loudness variance |

### Frequency Bands

| Band | Range | Typical Content |
|------|-------|-----------------|
| Sub-bass | 20-60 Hz | Deep subs, felt more than heard |
| Bass | 60-250 Hz | Kick, bass - main rhythm |
| Low-mid | 250-500 Hz | Body, warmth |
| Mid | 500-2000 Hz | Vocals, melody |
| High-mid | 2000-4000 Hz | Clarity, presence |
| Presence | 4000-6000 Hz | Definition |
| Air | 6000-20kHz | Sparkle, hi-hats |

---

## VJ Software Mapping

### Magic Music Visuals

```
1. Add OSC modulator
2. Select feature (/beat, /energy_smooth, etc.)
3. Map to parameter, set range 0-1
```

**Recommended mappings:**
- `/beat` → Flash layer opacity
- `/bass_band` → Red channel / object scale
- `/energy_smooth` → Master brightness
- `/brightness` → Color temperature

### Resolume Arena

```
Preferences → OSC → Input → Port 9000
Right-click parameter → OSC Input → play music to auto-map
```

### TouchDesigner

```python
# In Execute DAT
def onReceiveOSC(dat, address, value):
    if address == '/beat' and value[0] == 1.0:
        op('flash').par.opacity = 1.0
    if address == '/bass_band':
        op('bass_layer').par.scale = 1.0 + value[0] * 0.5
```

### Processing

```java
import oscP5.*;

OscP5 osc;
float bassBand, energy;

void setup() {
  osc = new OscP5(this, 9000);
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/bass_band")) {
    bassBand = msg.get(0).floatValue();
  }
}

void draw() {
  float radius = 100 + bassBand * 200;
  ellipse(width/2, height/2, radius, radius);
}
```

---

## Bass-Driven Effects

Bass provides the most powerful VJ control due to predictable rhythm and physical impact.

### Technique 1: Size/Scale
```
/audio/levels[1] (bass) → Object Scale
Min: 1.0, Max: 3.0, Smoothing: 0.3
Result: Objects pulse with kick drum
```

### Technique 2: Color Intensity
```
/bass_band → Red Channel (0.0-1.0)
Blend mode: Add or Screen
Result: Scene flashes red on kick
```

### Technique 3: Camera Shake
```
/bass_band → Camera Shake Amount (5-20px)
Decay: Fast
Result: Screen shakes on kick
```

### Technique 4: Particle Burst
```
/bass_band → Particle Birth Rate
Base: 10/sec, Peak: 500/sec
Result: Burst on kick
```

---

## Build-up & Drop Detection

### Automatic Detection

The analyzer tracks energy over 2-second windows:

```
/audio/structure[0] = 1  → Build-up active
/audio/structure[1] = 1  → Drop detected
/audio/structure[2]      → Energy trend (-1 to +1)
```

### Build-up Response (2-4 seconds)

**Early phase:**
- Increase effect intensity +20%
- Start filter sweep (200 Hz → 8kHz)
- Gradually increase brightness

**Peak phase (last 1-2 seconds):**
- Enable strobe at BPM/4
- Camera zoom to 110%
- Particles accumulate
- Colors desaturate to white

### Drop Response (instant)

```
0.00s - White flash (100%)
0.05s - Particle explosion (500-1000)
0.10s - Camera shake peak
0.20s - Flash fades
0.50s - Effects stabilize, full intensity
```

---

## Scene Switching Strategies

### Method 1: Beat-Triggered
```
Every 16 or 32 beats → Fade to next scene (1-2 beat crossfade)
```

### Method 2: Build-up/Drop Triggered
```
Build-up detected → Start transition animation
Drop detected → Complete with explosive effect
```

### Method 3: Energy-Based
```
High energy (>0.7) → Intense, chaotic visuals
Medium (0.3-0.7) → Normal visuals
Low (<0.3) → Minimal, ambient visuals
```

---

## Implementation Details

### Essentia Integration

Multi-method onset detection for robustness:
- **HFC (50%)** - Best for percussive content
- **Complex (30%)** - General-purpose
- **Flux (20%)** - Spectral novelty

```python
onset_strength = (hfc * 0.5 + complex * 0.3 + flux * 0.2)
```

### EMA Smoothing

All continuous features use exponential moving average:
```python
smooth = (1 - alpha) * prev + alpha * raw
# alpha=0.2 for energy (fast), alpha=0.3 for spectral (medium)
```

### Running Normalization

10-second sliding window for stable normalization:
```python
normalized = np.clip(raw / (max_over_10s + 1e-9), 0, 1)
```

---

## Performance

| Metric | Value |
|--------|-------|
| Latency | 10-30ms |
| Frame rate | 60+ fps |
| OSC throughput | 360 msg/sec |
| CPU usage | 5-10% |
| Memory | ~50 MB |

### Watchdog Auto-Recovery

Health checks every 2 seconds:
- Thread running?
- Audio arriving?
- Error count < threshold?

Auto-restart on failure (max 5 attempts).

---

## Configuration

Device persisted to `~/.vj_audio_config.json`:
```json
{
  "device_index": 1,
  "device_name": "BlackHole 2ch",
  "auto_select_blackhole": true
}
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `5` | Switch to audio screen |
| `A` | Toggle analyzer on/off |
| `B` | Run 10-second benchmark |
| `[` | Previous audio device |
| `]` | Next audio device |

---

## Dependencies

```
sounddevice>=0.4.6  # Low-latency audio I/O
numpy>=1.24.0       # FFT and spectral analysis
essentia            # Beat detection, tempo, pitch
python-osc>=1.8.3   # OSC communication
```

---

## Appendix: Research Notes

### Essentia vs Aubio

| Feature | Essentia | Aubio |
|---------|----------|-------|
| Beat tracking | Multiple algorithms | Single |
| Pitch detection | PitchYin, Melodia | Basic |
| Spectral features | Extensive | Limited |
| Real-time | Streaming mode | Callback |

**Winner: Essentia** - More feature-rich for VJ applications.

### Essential VJ Metrics (Priority)

1. **Beat Detection & BPM** ⭐⭐⭐⭐⭐ - Foundation for EDM sync
2. **Energy/RMS** ⭐⭐⭐⭐⭐ - Overall intensity control
3. **Frequency Bands** ⭐⭐⭐⭐⭐ - Multi-layer visual control
4. **Spectral Centroid** ⭐⭐⭐⭐ - Timbral brightness
5. **Spectral Flux** ⭐⭐⭐⭐ - Onset/novelty detection
6. **Pitch Detection** ⭐⭐⭐ - Melodic mapping

### Future Enhancements

- [ ] GPU-accelerated FFT (cuFFT)
- [ ] Machine learning beat tracking
- [ ] Key/scale detection
- [ ] Harmonic/percussive separation
- [ ] Real-time genre classification

---

**See also:** [osc-visual-mapping.md](../guides/osc-visual-mapping.md) for complete mapping examples

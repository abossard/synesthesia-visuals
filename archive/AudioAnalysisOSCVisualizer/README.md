# AudioAnalysisOSCVisualizer

A Processing sketch that visualizes audio features received via OSC from the Python Essentia audio analyzer.

## Overview

This sketch **does NOT perform audio analysis**. Instead, it receives pre-analyzed audio features via OSC and visualizes them. This separation allows:

1. **Robust analysis** using Python's Essentia library with advanced beat detection and spectral analysis
2. **Beautiful visualization** using Processing's graphics capabilities  
3. **Syphon output** for VJ software integration
4. **Low latency** by offloading heavy computation to Python

## Setup

### 1. Install Processing Libraries

Install these libraries via Processing's Library Manager (Sketch → Import Library → Add Library):

- **oscP5** - OSC communication
- **Syphon** (macOS only) - Frame sharing with VJ software

### 2. Start Python Audio Analyzer

```bash
cd python-vj
pip install -r requirements.txt
python vj_console.py
# Press 'A' to toggle audio analyzer on
```

The Python analyzer will:
- Capture audio from your selected device (default: BlackHole 2ch)
- Perform FFT, beat detection, BPM estimation, pitch detection
- Send audio features via OSC to port 9000

### 3. Run Processing Sketch

1. Open `AudioAnalysisOSCVisualizer.pde` in Processing
2. Click Run
3. The sketch will listen on port 9000 for OSC messages
4. Play music - you should see visualizations update in real-time

## OSC Messages Received

The sketch receives these OSC messages from the Python analyzer:

### `/audio/levels` (8 floats)
Frequency band energies: `[sub_bass, bass, low_mid, mid, high_mid, presence, air, overall_rms]`

### `/audio/spectrum` (32 floats)
Full spectrum downsampled to 32 bins for visualization

### `/audio/beats` (5 values)
Beat detection: `[is_beat, beat_pulse, bass_pulse, mid_pulse, high_pulse]`

### `/audio/bpm` (2 floats)
Tempo: `[bpm, confidence]`

### `/audio/pitch` (2 floats)
Pitch detection: `[frequency_hz, confidence]`

### `/audio/spectral` (3 floats)
Spectral features: `[centroid_norm, rolloff_hz, flux]`

### `/audio/structure` (4 values)
Musical structure: `[is_buildup, is_drop, energy_trend, brightness]`

## Visualization Panels

The sketch displays:

1. **Spectrum Bars** (bottom) - 32-bin frequency spectrum with color gradient
2. **Level Bars** (right) - 8 frequency bands with beat pulse indicators
3. **Beat Panel** (right middle) - BPM display, confidence, and multi-band beat pulses
4. **Spectral Panel** (left top) - Spectral centroid, rolloff, flux, and pitch
5. **Structure Panel** (left middle) - Build-up/drop detection, energy trend

## Testing Without Audio

You can test the visualization without running the full audio analyzer:

```bash
cd python-vj
python test_osc_communication.py stream
```

This sends animated test data to the visualizer for 10 seconds.

## Syphon Output

The sketch outputs frames via Syphon (macOS only) with server name "AudioOSCVisualizer".

To receive in VJ software:
- **Magic Music Visuals**: Add Syphon source, select "AudioOSCVisualizer"
- **MadMapper**: Add Syphon source → AudioOSCVisualizer
- **Resolume**: Use Syphon input plugin

## Keyboard Commands

- **R** - Reset all values to zero

## Troubleshooting

### "Waiting for OSC data..." message

**Cause**: Visualizer not receiving OSC messages

**Solutions**:
1. Check Python analyzer is running: `cd python-vj && python vj_console.py`
2. Press 'A' in VJ Console to start audio analyzer
3. Verify port 9000 is not blocked by firewall
4. Test with: `python test_osc_communication.py stream`

### No Syphon output

**Cause**: Processing not built for Intel (required for Syphon on Apple Silicon)

**Solution**: Download Intel version of Processing 4.x

### Visualization not updating smoothly

**Cause**: OSC messages not arriving at 60Hz

**Solutions**:
1. Check Python analyzer performance (should be 60+ fps)
2. Reduce network latency (use localhost/127.0.0.1)
3. Check CPU usage of Python analyzer

## Differences from AudioAnalysisOSC

| Feature | AudioAnalysisOSC | AudioAnalysisOSCVisualizer |
|---------|------------------|---------------------------|
| Audio input | Yes (Processing FFT) | No |
| Beat detection | Yes (Processing) | No (receives via OSC) |
| BPM estimation | Yes (Processing) | No (receives via OSC) |
| Pitch detection | No | Yes (via OSC) |
| Spectral analysis | Basic (FFT) | Advanced (Essentia) |
| Build-up/drop detection | No | Yes (via OSC) |
| Multi-band beats | Yes | Yes (via OSC) |
| Visualization | Yes | Yes |
| Syphon output | No | Yes |

## Architecture

```
Audio Input (BlackHole/Microphone)
    ↓
Python Audio Analyzer (audio_analyzer.py)
    ├─ sounddevice - Low-latency audio I/O
    ├─ Essentia - Beat detection, tempo, pitch
    ├─ NumPy - FFT, spectral analysis
    └─ python-osc - Send features via OSC
    ↓
OSC Messages (localhost:9000)
    ↓
Processing Visualizer (this sketch)
    ├─ oscP5 - Receive OSC
    ├─ Graphics - Draw visualizations
    └─ Syphon - Output frames
    ↓
VJ Software (Magic, Resolume, MadMapper)
```

## Performance

- **Latency**: ~10-30ms total (audio capture + analysis + OSC + rendering)
- **Frame rate**: 60 fps (visualization)
- **OSC rate**: ~60 Hz (Python analyzer sends at 60 fps)
- **CPU usage**: Low (visualization only, no heavy DSP)

## See Also

- **AudioAnalysisOSC** - Processing sketch that does local audio analysis
- **python-vj/audio_analyzer.py** - Python Essentia-based analyzer
- **OSC_VISUAL_MAPPING_GUIDE.md** - Complete guide to OSC features
- **VJ_AUDIO_FEATURES_RESEARCH.md** - Technical details on audio features

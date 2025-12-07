# Quick Start: Audio Analysis OSC Pipeline

This guide shows how to use the complete Python → OSC → Processing visualization pipeline.

## What You Get

**Python Essentia Audio Analyzer** (robust, advanced)
  ↓ OSC messages
**Processing Visualizer** (beautiful graphics)
  ↓ Syphon frames
**VJ Software** (Magic, Resolume, etc.)

## Setup (5 minutes)

### 1. Install Python Dependencies

```bash
cd python-vj
pip install -r requirements.txt
```

This installs:
- `essentia` - Advanced beat/tempo/pitch detection
- `sounddevice` - Low-latency audio I/O
- `python-osc` - OSC communication
- Other VJ system dependencies

### 2. Install Processing Libraries

Open Processing IDE → Sketch → Import Library → Add Library

Install:
- **oscP5** - OSC communication
- **Syphon** (macOS only) - Frame output to VJ software

### 3. Configure Audio Input

**Option A: BlackHole (recommended for system audio)**
```bash
# Install BlackHole 2ch from https://existential.audio/blackhole/
# Create Multi-Output Device in Audio MIDI Setup:
#   1. Built-in Output + BlackHole 2ch
#   2. Set as system output
#   3. Python analyzer will auto-detect BlackHole
```

**Option B: Microphone**
```bash
# No setup needed - analyzer will use default input
# Or select device manually in vj_console.py
```

## Running the System

### Start Python Audio Analyzer

```bash
cd python-vj
python vj_console.py
```

**In the console:**
1. Press `A` to start audio analyzer
2. Press `5` to view live analysis
3. Verify OSC sending (you should see "Audio analyzer: ON")

### Start Processing Visualizer

1. Open `processing-vj/src/AudioAnalysisOSCVisualizer/AudioAnalysisOSCVisualizer.pde`
2. Click **Run** ▶️
3. You should see "OSC Connected" in green

### Play Music

Play music through your system audio (if using BlackHole) or speak/play into microphone.

**Expected behavior:**
- Python console shows analysis stats updating
- Processing window shows:
  - Spectrum bars animating
  - Level bars pulsing with music
  - BPM display updating
  - Beat pulses flashing

## Testing Without Audio

### Test 1: Send Static Data

```bash
cd python-vj
python test_osc_communication.py send
```

Processing window should update with test values.

### Test 2: Send Animated Stream

```bash
cd python-vj
python test_osc_communication.py stream
```

Processing window should animate for 10 seconds with pulsing visuals.

### Test 3: Verify Message Format

```bash
cd python-vj
python test_analyzer_integration.py
```

Should print:
```
✓ /audio/levels: received 10 times, 8 values
✓ /audio/spectrum: received 10 times, 32 values
✓ /audio/beats: received 10 times, 5 values
✓ All OSC message tests PASSED
```

## Troubleshooting

### Processing shows "Waiting for OSC data..."

**Problem**: Visualizer not receiving OSC

**Solutions**:
1. Check Python analyzer is running: `python vj_console.py`
2. Press `A` in VJ Console to start analyzer
3. Verify port 9000 in both Python and Processing configs
4. Test with: `python test_osc_communication.py stream`

### Python shows "sounddevice not available"

**Problem**: Missing PortAudio library

**Solutions**:
```bash
# macOS
brew install portaudio
pip install sounddevice

# Ubuntu/Debian
sudo apt-get install portaudio19-dev python3-dev
pip install sounddevice

# Windows
pip install sounddevice
# (installs bundled PortAudio)
```

### Python shows "Essentia not available"

**Problem**: Essentia not installed

**Solutions**:
```bash
# Try pip install first
pip install essentia

# If that fails, use conda
conda install -c mtg essentia

# Or build from source (advanced)
# See: https://essentia.upf.edu/installing.html
```

**Note**: Analyzer still works without Essentia (uses NumPy fallback)

### BPM not detecting

**Problem**: Music might not have clear beats

**Solutions**:
1. Test with 4/4 electronic music first (house, techno)
2. Adjust sensitivity in Python analyzer config
3. Check audio levels (should be > 0.3 overall)

### Visualizer runs slow

**Problem**: Processing framerate low

**Solutions**:
1. Check CPU usage of Python analyzer
2. Reduce spectrum bins (32 → 16) in config
3. Disable Syphon if not needed
4. Use Intel build of Processing (for Syphon on Apple Silicon)

## Advanced: Syphon to VJ Software

### Magic Music Visuals

1. Add layer → Syphon Input
2. Select "AudioOSCVisualizer"
3. The visualization appears as a video source
4. Can now apply effects, blend modes, etc.

### Resolume Arena

1. Sources → Syphon → AudioOSCVisualizer
2. Add to clip slot
3. Use as input for effects chains

### MadMapper

1. Add video input → Syphon
2. Select AudioOSCVisualizer
3. Map to surfaces/fixtures

## Configuration

### Python Analyzer (audio_analyzer.py)

```python
config = AudioConfig(
    osc_port=9000,           # OSC send port
    spectrum_bins=32,        # Spectrum resolution
    enable_essentia=True,    # Use Essentia algorithms
    enable_bpm=True,         # BPM estimation
    enable_pitch=True,       # Pitch detection
    enable_structure=True,   # Build-up/drop detection
)
```

### Processing Visualizer (in setup())

```java
int oscPort = 9000;  // OSC receive port (must match Python)
size(960, 540, P3D); // Window size (P3D required for Syphon)
frameRate(60);       // Render framerate
```

## Performance Metrics

**Latency** (audio input → visual output):
- Python analysis: ~10ms
- OSC transmission: <1ms (localhost)
- Processing render: ~16ms (60 fps)
- **Total: ~30ms** ✓

**CPU Usage**:
- Python analyzer: 5-10%
- Processing visualizer: 3-5%
- **Total: ~10-15%** ✓

**Frame Rates**:
- Python analysis: 60+ fps
- OSC messages: 60 Hz
- Processing render: 60 fps
- **All synchronized** ✓

## What's Next?

### 1. Use Original AudioAnalysisOSC

If you want audio analysis directly in Processing (no Python dependency):

```java
// Open: processing-vj/src/AudioAnalysisOSC/AudioAnalysisOSC.pde
// Does FFT, beat detection, BPM all in Processing
// Good for standalone use or when Python not available
```

### 2. Send OSC to Other Software

The Python analyzer can send to **any** OSC-capable software:

**TouchDesigner**:
```python
config = AudioConfig(osc_port=7000)  # TD default port
```

**Max/MSP**:
```python
config = AudioConfig(osc_port=8000)  # Configure UDP receive in Max
```

**SuperCollider**:
```python
config = AudioConfig(osc_port=57120)  # SC default port
```

### 3. Customize Visuals

Edit `AudioAnalysisOSCVisualizer.pde`:
- Modify `drawSpectrumBars()` for different spectrum viz
- Add new panels in `draw()`
- Change colors, sizes, effects
- Add particle systems, 3D graphics, shaders

### 4. Record Analysis Data

Log OSC messages to file:
```bash
cd python-vj
python test_osc_communication.py receive > analysis_log.txt
# Record 10 seconds of OSC data
```

## File Overview

```
processing-vj/src/
├── AudioAnalysisOSC/              # Original: Does analysis in Processing
│   └── AudioAnalysisOSC.pde       # FFT + beat + BPM + OSC sender
└── AudioAnalysisOSCVisualizer/    # New: Visualizes OSC from Python
    ├── AudioAnalysisOSCVisualizer.pde  # OSC receiver + visualization
    └── README.md                       # This sketch's documentation

python-vj/
├── audio_analyzer.py              # Essentia-based analyzer
├── vj_console.py                  # TUI to control analyzer
├── test_osc_communication.py      # OSC testing utilities
├── test_analyzer_integration.py   # Integration tests
├── ESSENTIA_INTEGRATION.md        # Technical details on Essentia
└── requirements.txt               # Python dependencies
```

## Summary

**Use Python analyzer + Processing visualizer when:**
- Need advanced beat/tempo/pitch detection (Essentia)
- Want separation of concerns (analysis vs visuals)
- Running VJ console with multiple Python services
- Need multi-band beat detection

**Use Processing AudioAnalysisOSC when:**
- Want standalone Processing sketch (no Python)
- Simpler deployment (one application)
- Don't need advanced Essentia features
- Prefer Processing's FFT implementation

**Both work great!** Choose based on your needs.

## Support

Issues? Check:
1. **Processing sketch README**: `processing-vj/src/AudioAnalysisOSCVisualizer/README.md`
2. **Python analyzer docs**: `python-vj/ESSENTIA_INTEGRATION.md`
3. **OSC mapping guide**: `python-vj/OSC_VISUAL_MAPPING_GUIDE.md`

Happy VJing! 🎵🎨

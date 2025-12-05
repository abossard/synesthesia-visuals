# Audio Analyzer Screen Implementation

## Overview

This document describes the implementation of the audio analyzer screen in the VJ console, which has been restored to screen 5 with MIDI router moved to screen 6.

## Changes Made

### 1. Screen Layout Updates

**Before:**
- Screen 1: Master Control
- Screen 2: OSC View
- Screen 3: Song AI Debug
- Screen 4: All Logs
- Screen 5: MIDI Router

**After:**
- Screen 1: Master Control
- Screen 2: OSC View
- Screen 3: Song AI Debug
- Screen 4: All Logs
- Screen 5: **Audio Analyzer** ⬅️ NEW
- Screen 6: MIDI Router ⬅️ MOVED

### 2. New UI Components

Three new panel classes were added to `vj_console.py`:

#### AudioAnalyzerStatusPanel
Displays:
- Analyzer running status (● RUNNING / ○ stopped)
- Audio input status (● ACTIVE / ○ no signal)
- Current audio device name
- Processing frame rate (fps)
- Error count
- Instruction: "Use [ ] to change audio device"

#### AudioFeaturesPanel
Real-time audio feature visualization:
- **Beat detection**: Visual beat indicator (◉ when beat detected)
- **BPM estimation**: Current tempo with confidence score
- **Energy levels**: 
  - Bass (sub-bass + bass bands)
  - Mids (low-mid + mid + high-mid)
  - Highs (presence + air bands)
- **Spectral features**: Brightness (spectral centroid)
- **Structure detection**:
  - Build-up detection (▲ BUILD-UP DETECTED)
  - Drop detection (▼ DROP DETECTED)
  - Energy trend display
- **Pitch detection**: Frequency and confidence (when available)

#### AudioDevicesPanel
Lists all available audio input devices with:
- Device name
- Channel count
- Sample rate
- Visual selection indicator (▸) for current device

### 3. Key Bindings

New key bindings added:

| Key | Action | Description |
|-----|--------|-------------|
| `5` | `action_screen_audio` | Switch to audio analyzer screen |
| `6` | `action_screen_midi` | Switch to MIDI router screen (moved from 5) |
| `[` | `action_audio_device_prev` | Switch to previous audio device |
| `]` | `action_audio_device_next` | Switch to next audio device |

### 4. Audio Analyzer Integration

The audio analyzer is automatically initialized and started when the VJ console starts:

```python
def _setup_audio_analyzer(self):
    """Initialize audio analyzer."""
    if not AUDIO_ANALYZER_AVAILABLE:
        return
    
    # Create device manager
    self.audio_device_manager = DeviceManager()
    
    # Create audio config
    audio_config = AudioConfig(
        sample_rate=44100,
        block_size=512,
        enable_logging=True,
    )
    
    # Create OSC callback for karaoke engine integration
    def osc_callback(address: str, args: List):
        if self.karaoke_engine and self.karaoke_engine.osc_sender:
            self.karaoke_engine.osc_sender.send(address, args)
    
    # Create analyzer and watchdog
    self.audio_analyzer = AudioAnalyzer(audio_config, self.audio_device_manager, osc_callback)
    self.audio_watchdog = AudioAnalyzerWatchdog(self.audio_analyzer)
```

### 5. OSC Integration

The audio analyzer sends real-time features via OSC to `/audio/*` addresses:
- `/audio/levels` - Per-band energy levels + overall RMS
- `/audio/spectrum` - Downsampled spectrum (32 bins)
- `/audio/beat` - Beat detection + spectral flux
- `/audio/bpm` - BPM estimate + confidence
- `/audio/pitch` - Pitch frequency + confidence
- `/audio/structure` - Build-up/drop detection + energy trend + brightness

These messages are sent through the karaoke engine's OSC sender, making them available to all VJ components.

### 6. Device Switching

Users can cycle through available audio input devices using square brackets:
- `[` - Previous device
- `]` - Next device

When a device is switched:
1. Device manager updates its configuration
2. Audio stream is stopped
3. New device is selected
4. Audio stream is restarted
5. UI is updated to show the new device

The selected device is persisted to `~/.vj_audio_config.json` for next session.

### 7. Graceful Degradation

The implementation handles missing dependencies gracefully:

- **No numpy**: Audio analyzer completely disabled, warning shown on screen 5
- **No sounddevice**: Audio input disabled, but analysis structure is available (essentia features still work with dummy data)
- **No essentia**: Beat/tempo/pitch detection disabled, basic spectral analysis still works

Status is clearly shown in the AudioAnalyzerStatusPanel.

## Technical Details

### Audio Processing Pipeline

1. **Input**: Audio callback receives frames at ~86 Hz (512 samples @ 44.1kHz)
2. **FFT**: Windowed FFT extracts frequency spectrum
3. **Band Extraction**: 7 frequency bands (sub-bass to air)
4. **Smoothing**: Exponential moving average (EMA) with compression
5. **Features**: Spectral centroid, flux, beat detection, BPM estimation
6. **OSC Output**: Features sent to VJ bus at 30 Hz

### Self-Healing Watchdog

The `AudioAnalyzerWatchdog` monitors the analyzer and automatically restarts it if:
- Thread stops running
- No audio input detected for >1 second
- Error count exceeds threshold (10 errors)

Maximum 5 restart attempts before giving up.

### Performance

- **Processing latency**: ~10-30ms average (measured via LatencyTester)
- **Update rate**: 30 Hz for UI (throttled from ~86 Hz DSP rate)
- **CPU usage**: Low impact due to efficient numpy FFT

## Testing

All tests pass:
- ✓ Module imports successfully
- ✓ All UI components exist
- ✓ All key bindings configured
- ✓ All action methods implemented
- ✓ Graceful degradation when dependencies missing

## Usage

1. Start VJ console: `python3 vj_console.py`
2. Press `5` to switch to audio analyzer screen
3. Verify audio device is correct (shown in left panel)
4. Use `[` or `]` to change device if needed
5. Monitor real-time features in right panel
6. Press `6` for MIDI router (previously screen 5)

## Dependencies

Required (already in requirements.txt):
- `numpy>=1.24.0` - FFT and spectral analysis
- `sounddevice>=0.4.6` - Audio I/O (requires PortAudio system library)
- `essentia` - Beat/tempo/pitch detection

Note: On Linux, sounddevice requires the PortAudio library to be installed at the system level:
```bash
# Ubuntu/Debian
sudo apt-get install portaudio19-dev

# macOS (already included)
# Windows (bundled with sounddevice)
```

## Future Enhancements

Potential improvements:
- [ ] Audio device auto-detection on macOS (BlackHole)
- [ ] Spectrum visualization graph
- [ ] Historical BPM graph
- [ ] Audio routing configuration UI
- [ ] Recording/playback for debugging
- [ ] Custom frequency band configuration

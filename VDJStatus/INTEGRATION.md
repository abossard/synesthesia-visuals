# Integrating VDJStatus Native App with Python VJ Console

## Overview

The VDJStatus native macOS app sends VirtualDJ playback information via OSC to the Python VJ console. This provides high-performance monitoring with ScreenCaptureKit and Vision OCR.

## Architecture

```
┌─────────────────┐           OSC Messages           ┌──────────────────┐
│  VDJStatus.app  │──────────────────────────────────>│  Python VJ       │
│  (macOS Swift)  │  /vdj/deck1, /vdj/deck2, etc.    │  Console         │
│                 │  Port 9001 (configurable)        │  (Python)        │
└─────────────────┘                                   └──────────────────┘
        │
        │ ScreenCaptureKit
        │ Vision OCR
        ▼
┌─────────────────┐
│  VirtualDJ      │
│  Window         │
└─────────────────┘
```

## Setup

### 1. Build VDJStatus App

```bash
cd VDJStatus
xcodebuild -project VDJStatus.xcodeproj -scheme VDJStatus -configuration Release build
```

Or open `VDJStatus.xcodeproj` in Xcode and build (⌘B).

### 2. Grant Permissions

1. System Settings → Privacy & Security → Screen Recording
2. Add VDJStatus.app
3. Restart VDJStatus if already running

### 3. Configure VDJStatus App

1. Launch VDJStatus.app
2. Click "Load" to restore saved calibration (or calibrate first time)
3. Select VirtualDJ window from dropdown
4. Configure OSC settings:
   - Host: `127.0.0.1` (or IP of Python VJ machine)
   - Port: `9001` (default, avoid conflict with Python's OSC output on 9000)
   - Enable: ✓
5. Click "Start Capture"

### 4. Configure Python VJ Console

Edit your VJ console configuration to use the VDJStatus OSC monitor:

```python
from adapters import VDJStatusOSCMonitor

# Create monitor instance
vdj_monitor = VDJStatusOSCMonitor(osc_host="127.0.0.1", osc_port=9001)

# Use in playback coordinator
coordinator = PlaybackCoordinator(
    monitors=[vdj_monitor],
    priority_order=['vdjstatus_osc']
)
```

Or use the registry:

```python
from adapters import PLAYBACK_SOURCES

# List available sources
for key, source in PLAYBACK_SOURCES.items():
    print(f"{key}: {source['label']} - {source['description']}")

# Create VDJStatus OSC monitor
vdj_monitor = PLAYBACK_SOURCES['vdjstatus_osc']['factory']()
```

## OSC Message Format

### Deck Info
```
/vdj/deck1 <artist:string> <title:string> <elapsed:float> <fader:float>
/vdj/deck2 <artist:string> <title:string> <elapsed:float> <fader:float>
```

Example:
```
/vdj/deck1 "Daft Punk" "One More Time" 125.3 0.75
```

### Master Deck
```
/vdj/master <deck_num:int>  # 1 or 2
```

Example:
```
/vdj/master 1
```

### Performance Metrics
```
/vdj/performance <deck1_confidence:float> <deck2_confidence:float>
```

Example:
```
/vdj/performance 0.85 0.90
```

## Performance Comparison

| Method | Latency | Accuracy | Setup Complexity |
|--------|---------|----------|------------------|
| **VDJStatus OSC** | ~500ms | High (Vision OCR) | High (calibration required) |
| VDJ File Polling | ~1000ms | Perfect | Low (file path only) |
| Python OCR | ~800ms | High (Vision OCR) | Medium (no calibration) |
| djay Accessibility | ~50ms | Perfect | Low (API access) |

## Troubleshooting

### No OSC messages received in Python

1. **Check VDJStatus app**:
   - Ensure "Start Capture" is clicked
   - Check OSC settings (host/port)
   - Verify detection results show data

2. **Check Python console**:
   ```python
   monitor = VDJStatusOSCMonitor()
   print(monitor.status)  # Should show 'available' after receiving messages
   ```

3. **Check network**:
   ```bash
   # Test OSC messages
   nc -ul 9001  # Listen on port 9001
   # Should see binary OSC data when VDJStatus is running
   ```

4. **Check firewall**:
   - Allow UDP port 9001 in macOS firewall
   - System Settings → Network → Firewall

### Detection accuracy issues

1. **Recalibrate ROIs**:
   - Enable "Calibrate" in VDJStatus
   - Ensure boxes tightly fit text regions
   - Save calibration

2. **Adjust VDJ UI**:
   - Use default skin (calibration optimized for it)
   - Increase UI scale if text too small
   - Ensure good contrast

3. **Fader detection**:
   - Narrow fader box (width ~20-40px)
   - Adjust gray range in CalibrationModel if needed
   - Default: 90-140 RGB

### High CPU usage

1. **Reduce frame rate**:
   - Edit `CaptureManager.swift`:
     ```swift
     config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 FPS
     ```

2. **Disable overlay**:
   - Uncheck "Show Overlay" in VDJStatus

3. **Use file polling instead**:
   - Switch to `VirtualDJMonitor` (file-based)

## Advanced Configuration

### Custom OSC Port

VDJStatus app UI:
- Change "Port" field to desired value
- Python side:
  ```python
  monitor = VDJStatusOSCMonitor(osc_port=9999)
  ```

### Remote Machine

VDJStatus on Machine A, Python VJ on Machine B:

1. VDJStatus app:
   - Host: `192.168.1.100` (Machine B IP)
   - Port: `9001`

2. Python VJ (Machine B):
   ```python
   monitor = VDJStatusOSCMonitor(osc_host="0.0.0.0", osc_port=9001)
   ```

### Multiple Monitors

Run multiple sources simultaneously:

```python
monitors = [
    VDJStatusOSCMonitor(),  # Native app OSC
    VirtualDJMonitor(),     # File polling backup
]

coordinator = PlaybackCoordinator(
    monitors=monitors,
    priority_order=['vdjstatus_osc', 'virtualdj_file']
)
```

## Development

### Testing OSC Messages

Send test messages to Python console:

```python
from pythonosc import udp_client

client = udp_client.SimpleUDPClient("127.0.0.1", 9001)
client.send_message("/vdj/deck1", ["Artist", "Title", 120.5, 0.8])
client.send_message("/vdj/master", [1])
```

### Debugging

Enable debug logging in Python:

```python
import logging
logging.basicConfig(level=logging.DEBUG)

monitor = VDJStatusOSCMonitor()
# Check logs for OSC server status
```

## See Also

- [VDJStatus README](../VDJStatus/README.md) - Full app documentation
- [OSC Manager](osc_manager.py) - Python OSC sender
- [Adapters](adapters.py) - All playback monitors

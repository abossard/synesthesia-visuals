# VDJStatus - Native macOS VirtualDJ Monitor

A high-performance native macOS application that monitors VirtualDJ using ScreenCaptureKit and Vision OCR, replacing the Python `vdj_status.py` script.

## Features

- **ScreenCaptureKit Window Capture**: High-performance, low-latency window capture (2 FPS configurable)
- **Vision OCR**: Fast text recognition for artist, title, and elapsed time
- **Fader Detection**: Pixel-based gray detection for GAIN fader position analysis
- **Master Deck Detection**: Automatically determines which deck is the master output
- **Calibration UI**: Interactive ROI calibration for 8 text/fader regions
- **Live Overlay**: Optional always-on-top overlay showing calibration boxes and detection results
- **OSC Output**: Sends all detection data via OSC (UDP) for integration with VJ systems
- **Performance Metrics**: Includes confidence scores for fader detection

## Requirements

- macOS 13.0+ (Ventura or later)
- Screen Recording permission (System Settings → Privacy & Security → Screen Recording)
- VirtualDJ running

## Building

### Xcode
1. Open `VDJStatus.xcodeproj` in Xcode
2. Select target: macOS (minimum 13.0)
3. Build & Run (⌘R)
4. Grant Screen Recording permission when prompted

### Command Line
```bash
xcodebuild -project VDJStatus.xcodeproj -scheme VDJStatus -configuration Release build
```

## Usage

### First Time Setup
1. Launch VDJStatus
2. Click "Refresh" to find VirtualDJ window
3. Select VirtualDJ window from dropdown
4. Click "Start Capture"
5. Enable "Calibrate" toggle
6. For each ROI (Region of Interest):
   - Select from dropdown (Deck 1/2: Artist, Title, Elapsed, Fader)
   - Drag on the overlay to draw calibration box
7. Click "Save" to persist calibration

### Normal Operation
1. Start VDJStatus
2. Click "Load" to restore calibration
3. Select VirtualDJ window
4. Click "Start Capture"
5. Detection runs automatically at 2 FPS
6. Results sent via OSC to configured host:port

### Keyboard Shortcuts
- `⌘⇧O` - Toggle overlay visibility
- `⌘⇧C` - Toggle calibration mode

## OSC Output

All messages sent via UDP to configured host:port (default: 127.0.0.1:9000)

### Messages
```
/vdj/deck1 <artist:string> <title:string> <elapsed:float> <fader:float>
/vdj/deck2 <artist:string> <title:string> <elapsed:float> <fader:float>
/vdj/master <deck_num:int>  # 1 or 2
/vdj/performance <deck1_confidence:float> <deck2_confidence:float>
```

### Monitoring OSC Output

Use the provided OSC monitor script:

```bash
python python-vj/scripts/monitor_vdjstatus_osc.py --port 9000
```

This will display all OSC messages received from VDJStatus.app.

## Calibration Tips

- **Artist/Title**: Draw tight boxes around the text regions
- **Elapsed Time**: Box should only contain "M:SS" time display
- **Fader**: Narrow vertical box covering the fader's travel range
- VirtualDJ default skin layout:
  - Deck 1: Left side (x < 0.45)
  - Deck 2: Right side (x > 0.55)
  - Faders: Center region (x ≈ 0.47 and 0.53)

## Fader Detection Algorithm

1. Scan each row in the fader ROI
2. Count pixels matching gray range (R≈G≈B, 90-140)
3. Row with most gray pixels = fader handle position
4. Lower Y = higher on screen = fader UP = louder
5. Confidence = (gray_pixels / roi_width)

## Performance

- Frame capture: ~2ms per frame
- OCR per ROI: ~50-100ms (fast mode)
- Total detection cycle: ~400-500ms
- OSC send: <1ms

## Architecture

- **AppState**: Main app state (Observable)
- **CaptureManager**: ScreenCaptureKit wrapper (Actor)
- **VisionOCR**: Vision framework text recognition
- **Detector**: OCR + fader detection logic
- **CalibrationModel**: ROI data model (Codable, disk-persisted)
- **OverlayController**: NSPanel overlay window management
- **OSCSender**: Minimal OSC encoder (no dependencies)
- **ContentView**: SwiftUI main UI
- **CalibrationCanvas**: Interactive ROI drawing
- **OverlayView**: Live overlay visualization

## Troubleshooting

### "Screen Recording permission required"
1. System Settings → Privacy & Security → Screen Recording
2. Add VDJStatus.app
3. Restart VDJStatus

### "VirtualDJ window not found"
- Ensure VirtualDJ is running and visible
- Click "Refresh" to rescan windows
- Check window list shows VirtualDJ

### OCR not detecting text
- Verify calibration boxes are accurate
- Text must be clearly visible in VDJ window
- Try adjusting VDJ UI scale/zoom
- Use "Calibrate" mode to see live ROI boxes

### Fader detection confidence low
- Adjust `grayLo`/`grayHi` in CalibrationModel for different skins
- Default gray range: 90-140 (works with VDJ default skin)
- Fader box must be narrow (width ~20-40px in capture)

## Development

### Project Structure
```
VDJStatus/
├── VDJStatus.xcodeproj/
│   └── project.pbxproj
└── VDJStatus/
    ├── VDJStatusApp.swift      # App entry
    ├── AppState.swift           # Main state
    ├── CaptureManager.swift     # ScreenCaptureKit
    ├── VisionOCR.swift          # OCR wrapper
    ├── Detector.swift           # Detection logic
    ├── CalibrationModel.swift   # ROI model
    ├── OverlayController.swift  # Overlay window
    ├── OSC.swift                # OSC sender
    ├── ContentView.swift        # Main UI
    ├── CalibrationCanvas.swift  # Calibration UI
    ├── OverlayView.swift        # Overlay UI
    ├── Info.plist
    └── VDJStatus.entitlements
```

### Testing
- Unit tests: Not yet implemented
- Manual testing: Launch VDJStatus, follow usage steps
- CI/CD: GitHub Actions builds on macOS runner

## License

Part of the synesthesia-visuals project.

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

### Xcode (GUI App)
1. Open `VDJStatus.xcodeproj` in Xcode
2. Select target: macOS (minimum 13.0)
3. Build & Run (⌘R)
4. Grant Screen Recording permission when prompted

### Swift Package Manager (CLI)
```bash
cd VDJStatus
swift build -c release
# Binary at .build/release/vdjstatus
```

### Command Line (Xcode Build)
```bash
xcodebuild -project VDJStatus.xcodeproj -scheme VDJStatus -configuration Release build
```

## Usage

### CLI Mode

The `vdjstatus` CLI runs headless with keyboard controls:

```bash
# Default: localhost:9000
.build/release/vdjstatus

# Custom OSC target
vdjstatus --host 192.168.1.100 --port 8000

# Custom poll interval
vdjstatus --interval 0.5

# Start with GUI window
vdjstatus --gui
```

**Keyboard Controls:**
- `d` — Open GUI window (calibration, preview)
- `r` — Refresh window list
- `q` — Quit

**Options:**
```
  -h, --host <host>       OSC target host (default: 127.0.0.1)
  -p, --port <port>       OSC target port (default: 9000)
  --interval <interval>   Detection poll interval in seconds (default: 1.0)
  -g, --gui               Start with GUI window open
```

### GUI Mode (First Time Setup)
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
- **DeckStateMachine**: Pure functional FSM for play state and master detection
- **OverlayController**: NSPanel overlay window management
- **OSCSender**: Minimal OSC encoder (no dependencies)
- **ContentView**: SwiftUI main UI
- **CalibrationCanvas**: Interactive ROI drawing
- **OverlayView**: Live overlay visualization

## Deck State Machine (FSM)

The `DeckStateMachine.swift` implements a pure functional state machine for tracking deck play states and determining which deck is the master output.

### Design Principles

- **Pure functions**: `(State, Event) → State` with no side effects
- **Immutable state**: All state structs use `let` properties
- **Relative timing**: All thresholds derive from a single `pollInterval` parameter
- **Graceful degradation**: Handles missing data without crashing

### State Types

```
┌─────────────────────────────────────────────────────────────────┐
│                     DeckPlayState (per deck)                    │
├─────────────────────────────────────────────────────────────────┤
│  ❓ Unknown   - No elapsed data received yet (initial state)    │
│  ▶️ Playing   - Elapsed time is changing                        │
│  ⏹ Stopped   - Elapsed time unchanged for N readings           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     DeckState (per deck)                        │
├─────────────────────────────────────────────────────────────────┤
│  playState: DeckPlayState     - Current play state              │
│  lastElapsed: Double?         - Last known elapsed time (nil=no data) │
│  faderPosition: Double?       - Fader position 0-1 (nil=no data)│
│  stableCount: Int             - Consecutive unchanged readings  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     MasterState (global)                        │
├─────────────────────────────────────────────────────────────────┤
│  deck1: DeckState             - Deck 1 state                    │
│  deck2: DeckState             - Deck 2 state                    │
│  master: Int?                 - 1, 2, or nil (no master)        │
└─────────────────────────────────────────────────────────────────┘
```

### Deck Play State Transitions

```
                    ┌──────────────────────────────────────┐
                    │              UNKNOWN                 │
                    │     (initial, no elapsed data)       │
                    └──────────────────┬───────────────────┘
                                       │
                         first valid elapsed reading
                                       │
                                       ▼
    ┌──────────────────────────────────────────────────────────────┐
    │                          PLAYING                             │
    │              (elapsed time is changing)                      │
    │                                                              │
    │  Entry: first elapsed reading OR elapsed delta > epsilon     │
    │  Exit:  stableCount >= stableThreshold                       │
    └───────────────────────────┬──────────────────────────────────┘
                                │
          elapsed unchanged for stableThreshold readings
                                │
                                ▼
    ┌──────────────────────────────────────────────────────────────┐
    │                          STOPPED                             │
    │           (elapsed time stable for N readings)               │
    │                                                              │
    │  Entry: stableCount >= stableThreshold                       │
    │  Exit:  elapsed delta > epsilon                              │
    └───────────────────────────┬──────────────────────────────────┘
                                │
                    elapsed changes (delta > epsilon)
                                │
                                ▼
                         back to PLAYING
```

### Master Detection Logic

```
┌─────────────────────────────────────────────────────────────────┐
│                    MASTER DETECTION RULES                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Priority 1: Only one deck playing                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ D1 Playing, D2 Not Playing  →  Master = D1              │   │
│  │ D2 Playing, D1 Not Playing  →  Master = D2              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Priority 2: Both playing → fader comparison                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Both Playing, F1 > F2       →  Master = D1 (higher fader)│   │
│  │ Both Playing, F2 > F1       →  Master = D2 (higher fader)│   │
│  │ Both Playing, F1 ≈ F2       →  Keep current master       │   │
│  │ Both Playing, no fader data →  Keep current master       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Priority 3: Both stopped                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ D1 Stopped, D2 Stopped      →  Master = nil (no master)  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Fallback: Unknown states                                       │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Any Unknown state           →  Keep current master       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### "No Data" Scenarios

The FSM gracefully handles missing data:

| Scenario | playState | lastElapsed | faderPosition | master | Notes |
|----------|-----------|-------------|---------------|--------|-------|
| App just started | `.unknown` | `nil` | `nil` | `nil` | Initial state |
| Never gets elapsed | `.unknown` | `nil` | may have | `nil` | Stays unknown forever |
| Never gets fader | `.playing`/`.stopped` | has value | `nil` | uses fallback | Master determined by play state only |
| Both decks unknown | `.unknown` | `nil` | `nil` | `nil` | No master until data arrives |
| OCR fails mid-track | stays current | stays current | stays current | stays current | `nil` readings don't change state |

### Configuration

```swift
FSMConfig {
    pollInterval: TimeInterval      // Base timing (all others derive from this)
    stopDetectionTime: TimeInterval // Time before deck considered stopped
    faderEqualThreshold: Double     // Fader difference for "equal" (0.02 = 2%)
    
    // Computed:
    elapsedEpsilon = pollInterval           // Time change threshold
    stableThreshold = stopDetectionTime / pollInterval  // Readings to stop
}
```

**Presets:**

| Config | Poll Interval | Stop Detection | Stable Threshold |
|--------|---------------|----------------|------------------|
| `.default` | 1.0s | 2.0s | 2 readings |
| `.fast` | 0.5s | 1.5s | 3 readings |

### Events

```swift
enum DeckEvent {
    case elapsedReading(deck: Int, elapsed: Double?)  // OCR detected time
    case faderReading(deck: Int, position: Double?)   // Fader position 0-1
}
```

### UI Visualization

The FSM state is visualized in the app panel:

```
┌────────────────────────────────────────────────────────────────┐
│                         FSM State                              │
├────────────────┬───────────────────────┬───────────────────────┤
│    DECK 1      │                       │       DECK 2          │
│  ▶️ Playing    │        ★ MASTER       │     ⏹ Stopped         │
│  2:34          │         D1            │     3:45              │
│  ████████░░    │          ↓            │     ██░░░░░░░░        │
│  stable: 0     │                       │     stable: 5         │
└────────────────┴───────────────────────┴───────────────────────┘

Transition Log:
  12:34:56  Master: None → D1
  12:34:55  D1: ❓ Unknown → ▶️ Playing
```

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
├── VDJStatus/
│   ├── VDJStatusApp.swift      # App entry
│   ├── AppState.swift           # Main state
│   ├── CaptureManager.swift     # ScreenCaptureKit
│   ├── VisionOCR.swift          # OCR wrapper
│   ├── Detector.swift           # Detection logic
│   ├── CalibrationModel.swift   # ROI model
│   ├── DeckStateMachine.swift   # FSM for play state & master detection
│   ├── OverlayController.swift  # Overlay window
│   ├── OSC.swift                # OSC sender
│   ├── ContentView.swift        # Main UI + FSM visualization
│   ├── CalibrationCanvas.swift  # Calibration UI
│   ├── OverlayView.swift        # Overlay UI
│   ├── Info.plist
│   └── VDJStatus.entitlements
└── VDJStatusTests/
    └── DeckStateMachineTests.swift  # 23 unit tests for FSM
```

### Testing

- Unit tests: 23 tests in `DeckStateMachineTests.swift` (all FSM transitions)
- Run tests: `xcodebuild test -scheme VDJStatus -destination 'platform=macOS'`
- Manual testing: Launch VDJStatus, follow usage steps
- CI/CD: GitHub Actions builds on macOS runner

## License

Part of the synesthesia-visuals project.

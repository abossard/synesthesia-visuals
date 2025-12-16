# VDJStatus CLI Tool

A console-based command-line tool for monitoring VirtualDJ status using ScreenCaptureKit. Built with Swift Package Manager to run alongside the GUI macOS app.

## Features

- 🖥️ **Terminal-based monitoring** - Runs in any terminal emulator
- 🎵 **Real-time detection** - OCR for track info, elapsed time, and fader positions
- 🎛️ **Master deck detection** - FSM-based intelligent state tracking
- 📡 **OSC output** - UDP OSC messages for VJ system integration
- 🪟 **Full GUI window** - Press 'd' to open the complete application interface (100% same as Xcode GUI)
- ⌨️ **Raw keyboard input** - No Enter key required (d=debug, q=quit)
- 🔄 **Shared codebase** - Reuses all core logic from GUI app via symlinks

## Prerequisites

- **macOS 13.0+** (Ventura or later - required for ScreenCaptureKit)
- **Xcode 14.0+** or **Xcode Command Line Tools**
- **VirtualDJ** running with a calibrated window
- **Screen recording permission** granted to Terminal.app

## Installation

### 1. Clone and Build

```bash
cd /path/to/synesthesia-visuals

# Build in debug mode
swift build

# Or build optimized release
swift build -c release
```

### 2. Install Binary (Optional)

```bash
# Copy to user bin
cp .build/release/vdjstatus-cli ~/bin/

# Or install system-wide
sudo cp .build/release/vdjstatus-cli /usr/local/bin/

# Make executable
chmod +x ~/bin/vdjstatus-cli  # or /usr/local/bin/vdjstatus-cli
```

### 3. Grant Screen Recording Permission

On first run, macOS will prompt for screen recording permission:

1. **System Settings → Privacy & Security → Screen Recording**
2. Enable checkbox for **Terminal.app** (or iTerm2, etc.)
3. Restart terminal and run again

**Note**: When running via `swift run`, the permission is granted to Terminal.app, not the binary itself.

## Usage

### Basic Usage

```bash
# Run with defaults (looks for "VirtualDJ" window, OSC to localhost:9000)
swift run vdjstatus-cli

# Or if installed:
vdjstatus-cli
```

### Command-Line Options

```bash
vdjstatus-cli [OPTIONS]

OPTIONS:
  -w, --window-name NAME    Target window name (default: VirtualDJ)
  -h, --osc-host HOST       OSC destination host (default: 127.0.0.1)
  -p, --osc-port PORT       OSC destination port (default: 9000)
  -i, --log-interval SEC    Status log interval in seconds (default: 2.0)
  -v, --verbose             Enable verbose logging
  --help                    Show help message
  --version                 Show version info
```

### Examples

```bash
# Monitor VirtualDJ with 5-second log intervals
vdjstatus-cli --log-interval 5.0

# Send OSC to remote server
vdjstatus-cli --osc-host 192.168.1.100 --osc-port 9001

# Match different window title
vdjstatus-cli --window-name "VirtualDJ 2024 - Home Edition"

# Verbose logging for debugging
vdjstatus-cli -v

# Combine options (note the -- separator for swift run)
swift run vdjstatus-cli -- -w "VirtualDJ" -h 127.0.0.1 -p 9000 -v
```

### Keyboard Commands (While Running)

| Key | Action |
|-----|--------|
| `d` | Toggle full GUI window (complete application interface with all features) |
| `q` | Quit gracefully |
| `Ctrl+C` | Force quit |

## Output

### Console Output Example

```
🚀 VDJStatus CLI starting...
Target window: VirtualDJ
OSC output: 127.0.0.1:9000
Log interval: 2.0s

Press 'd' to toggle debug window, 'q' to quit

✓ Calibration loaded (8 ROIs)
✓ OSC configured
✓ FSM initialized
⚠️  Requesting screen recording permission...
   (Grant permission in System Settings → Privacy & Security → Screen Recording)
✓ Screen recording permission granted
🔍 Looking for window: VirtualDJ...
✓ Found window: VirtualDJ 2024
  App: VirtualDJ
  Size: 1920×1080
✓ Capture started

═══════════════════════════════════════════════════
Status monitoring active (every 2.0s)
═══════════════════════════════════════════════════

[2024-12-16T17:30:42Z]
  Deck 1: Artist Name - Track Title
          3:45 | Fader: 85%
  Deck 2: Another Artist - Another Track
          1:23 | Fader: 10%
  Master: Deck 1 🎵

[2024-12-16T17:30:44Z]
  Deck 1: Artist Name - Track Title
          3:47 | Fader: 85%
  Deck 2: Another Artist - Another Track
          1:25 | Fader: 10%
  Master: Deck 1 🎵
```

### OSC Messages Sent

```
/vdj/deck1    (artist: string, title: string, elapsed: float, fader: float)
/vdj/deck2    (artist: string, title: string, elapsed: float, fader: float)
/vdj/master   (deck_num: int)
```

## Full GUI Window (Press 'd')

Press `d` while the CLI is running to open the **complete GUI application window** - 100% identical to the Xcode project with all features:

### **Window Features** (Same as GUI App)

**Step 1: Window Selection**
- Dropdown to select VirtualDJ window
- Refresh button to reload window list
- Auto-capture indicator

**Step 2: Capture & Preview**
- Start/Stop capture controls
- Live frame preview with visual overlays:
  - ROI rectangles (cyan for Deck 1, magenta for Deck 2)
  - Detected text boxes (red) with OCR labels
  - Fader position indicators (horizontal red lines)
  - Live detection overlay (artist, title, elapsed time)

**Step 3: Calibration**
- **Interactive ROI calibration mode** - drag to draw boxes on the preview
- ROI selector dropdown (8 regions: D1/D2 Artist/Title/Elapsed/Fader)
- Load/Save calibration buttons
- Language correction toggles for non-English artist names
- Real-time coordinate display

**Step 4: OSC Configuration**
- Host/Port settings
- Enable/Disable toggle

**Detection Results Panel**
- Master deck indicator with large elapsed time display
- Deck 1 & Deck 2 columns showing artist, title, time, fader position
- Performance metrics (OCR time, average, frame latency)

**FSM State Diagram**
- Visual state boxes for both decks
- Play state indicators (Playing/Stopped/Unknown with emojis)
- Fader position bar graphs
- Master deck highlighting
- Transition log with timestamps

### **Key Benefits**

✅ **Calibrate ROIs** while CLI monitors in background
✅ **All settings work** - change OSC host/port, window selection, etc.
✅ **Shared state** - Changes in GUI immediately reflected in CLI logs
✅ **No differences** - Exact same ContentView as Xcode project
✅ **Press 'd' again** to close window and continue CLI monitoring

The window is fully functional with all controls, buttons, and settings. You can perform calibration, change configuration, and monitor state all while the CLI continues logging to the terminal.

## Calibration

You can calibrate ROI regions in two ways:

### **Option 1: From CLI (Recommended)**
1. **Run the CLI tool**: `swift run vdjstatus-cli`
2. **Press 'd'** to open the full GUI window
3. **Toggle "Calibration Mode ON"** in Step 3
4. **Select ROI** from dropdown (e.g., "D1 Artist")
5. **Drag on the preview** to draw a box around the region
6. **Repeat** for all 8 ROIs (D1/D2 Artist, Title, Elapsed, Fader)
7. **Click "Save"** to persist calibration
8. **Press 'd' again** to close GUI and continue CLI monitoring

### **Option 2: From GUI App**
1. **Run the standalone GUI app** (VDJStatus.app)
2. **Open calibration mode** and draw ROI rectangles
3. **Save calibration**
4. **Run CLI tool** - automatically loads saved calibration

**Calibration file location**:
`~/Library/Application Support/VDJStatus/vdj_calibration.json`

**Without calibration**, the CLI will start but detection will fail (no ROIs defined). Press 'd' to open the GUI and calibrate.

## Troubleshooting

### 1. Screen Recording Permission Denied

**Symptom:**
```
❌ Screen recording permission denied
   Enable for Terminal.app in System Settings
```

**Solution:**
1. Open **System Settings → Privacy & Security → Screen Recording**
2. Enable **Terminal.app** (or your terminal emulator)
3. Restart terminal
4. Run again

**Check permission status:**
```bash
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "SELECT client, auth_value FROM access WHERE service='kTCCServiceScreenCapture';"
```

---

### 2. VirtualDJ Window Not Found

**Symptom:**
```
❌ Window not found: VirtualDJ
   Available windows:
   - Safari
   - Terminal
   - Finder
```

**Solutions:**
- **Launch VirtualDJ** before running CLI
- **Check window title** - VirtualDJ window might have different title:
  ```bash
  vdjstatus-cli -w "VirtualDJ 2024"
  ```
- **Try partial match** - CLI searches for windows containing the string

---

### 3. No Calibration File

**Symptom:**
```
⚠️  No calibration data found!
   Run the GUI app (VDJStatus.app) first to calibrate ROIs
```

**Impact**: Detection will fail (no ROIs defined)

**Solution:**
1. Run **VDJStatus.app** (GUI)
2. Open **calibration mode**
3. Draw ROI rectangles for all 8 regions
4. Save calibration
5. Run CLI tool again

---

### 4. Terminal Input Not Working

**Symptom:**
- Pressing 'd' or 'q' has no effect
- Terminal displays typed characters

**Causes:**
- Ctrl+C interrupted before restoring terminal settings
- App crashed without cleanup

**Solution:**
```bash
# Manually restore terminal
reset

# Or type blindly:
stty sane
```

**Prevention**: CLI automatically restores terminal on:
- Normal quit ('q')
- Signal handlers (SIGINT, SIGTERM)
- Cleanup in destructors

---

### 5. Capture Errors

**Symptom:**
```
ERROR: Capture failed: SCStreamError
```

**Common Causes:**
- **Window closed** - VirtualDJ quit during capture
- **Display change** - Screen resolution changed, monitor disconnected
- **System sleep** - Mac woke from sleep

**Handling:**
- CLI has **auto-recovery** with exponential backoff (max 3 attempts)
- **Health check timer** detects frame timeout (5 seconds)
- If persistent:
  1. Restart VirtualDJ
  2. Restart CLI tool
  3. Check Console.app for system-level errors

---

### 6. GUI Window Not Appearing

**Symptom:**
- Press 'd', but no window shows
- Console shows "GUI window opened" but nothing visible

**Causes:**
1. **macOS Focus Assist** - Window opens on different space/desktop
2. **Window minimized** - Check Dock for minimized windows
3. **Window off-screen** - Frame outside visible area

**Solutions:**
1. **Check all desktops/spaces** (Mission Control / Cmd+↑)
2. **Check Dock** - Window may be minimized
3. **Try pressing 'd' twice** - Close and reopen to reset position
4. **Check console output** - Should say "GUI window opened" or "GUI window closed"
5. **Restart CLI** - Window position is centered on first open

---

## Architecture

### Shared Source Code (Symlinked from GUI App)

The CLI tool shares **both core business logic AND the complete SwiftUI GUI** via symbolic links:

```
Sources/VDJStatusCore/
├── DeckStateMachine.swift    → VDJStatus/VDJStatus/DeckStateMachine.swift
├── Detector.swift            → VDJStatus/VDJStatus/Detector.swift
├── CalibrationModel.swift    → VDJStatus/VDJStatus/CalibrationModel.swift
├── OSC.swift                 → VDJStatus/VDJStatus/OSC.swift
├── VisionOCR.swift           → VDJStatus/VDJStatus/VisionOCR.swift
├── CaptureManager.swift      → VDJStatus/VDJStatus/CaptureManager.swift
├── AppState.swift            → VDJStatus/VDJStatus/AppState.swift (NEW)
├── ContentView.swift         → VDJStatus/VDJStatus/ContentView.swift (NEW)
├── CalibrationCanvas.swift   → VDJStatus/VDJStatus/CalibrationCanvas.swift (NEW)
└── MiniPreviewView.swift     → VDJStatus/VDJStatus/MiniPreviewView.swift (NEW)
```

**Benefits:**
- ✅ Single source of truth for **everything** (logic + UI)
- ✅ Edit once, affects both projects
- ✅ No code duplication
- ✅ Shared unit tests
- ✅ **Same GUI in both CLI and Xcode project** (100% identical)

### CLI-Specific Code

```
Sources/VDJStatusCLI/
├── main.swift             # Entry point, argument parsing
├── CLIRunner.swift        # Main orchestrator using AppState
├── TerminalInput.swift    # Raw stdin handler (POSIX termios)
├── DebugWindow.swift      # NSHostingController wrapper for full SwiftUI GUI
└── CLILogger.swift        # Stdout/stderr logger with flush
```

**Key Implementation Details:**
- `CLIRunner` uses shared `AppState` (same as GUI app)
- `DebugWindow` hosts full `ContentView` via `NSHostingController`
- All SwiftUI views rendered natively with AppKit integration
- Console logs flushed immediately (visible even when GUI is open)

### Dependencies (All Native)

- **ScreenCaptureKit** - Window capture (macOS 13+)
- **Vision** - OCR text recognition
- **CoreGraphics** - Image processing
- **AppKit** - Debug window (NSWindow, NSApplication)
- **Network** - UDP OSC output
- **Foundation** - Core Swift functionality

**No external dependencies** - builds with standard Swift toolchain.

---

## Build System Coexistence

The CLI tool and GUI app can be built independently:

### GUI App (Xcode)

```bash
# Build in Xcode GUI
open VDJStatus/VDJStatus.xcodeproj

# Or via command line
xcodebuild -project VDJStatus/VDJStatus.xcodeproj \
           -scheme VDJStatus \
           build
```

### CLI Tool (SwiftPM)

```bash
# Build with Swift Package Manager
swift build

# Run directly
swift run vdjstatus-cli
```

**No conflicts** - separate build directories:
- Xcode: `VDJStatus/DerivedData/`
- SwiftPM: `.build/`

---

## Testing

### Run Unit Tests

```bash
# Run all tests
swift test

# Run specific test
swift test --filter DeckStateMachineTests

# Verbose output
swift test -v
```

### Tests Included

- **DeckStateMachineTests** (23 tests)
  - FSM state transitions
  - Play state detection
  - Master deck determination
  - Edge cases and error handling

---

## Development

### Project Structure

```
synesthesia-visuals/
├── Package.swift                 # SwiftPM manifest
├── Sources/
│   ├── VDJStatusCore/           # Shared library (symlinked)
│   └── VDJStatusCLI/            # CLI executable
├── Tests/
│   └── VDJStatusCoreTests/      # Unit tests (symlinked)
├── VDJStatus/                    # Original Xcode project
│   └── VDJStatus.xcodeproj
├── CLI_IMPLEMENTATION_PLAN.md   # Detailed implementation guide
└── CLI_README.md                # This file
```

### Adding New Features

1. **Core logic** (shared with GUI):
   - Edit files in `VDJStatus/VDJStatus/`
   - Changes automatically affect CLI (via symlinks)

2. **CLI-specific**:
   - Edit files in `Sources/VDJStatusCLI/`
   - Build with `swift build`

### Debugging

```bash
# Build with debug symbols
swift build -c debug

# Run in LLDB
lldb .build/debug/vdjstatus-cli
(lldb) run --verbose

# Or use Xcode for debugging:
# File → Open → synesthesia-visuals (folder)
# Xcode will recognize Package.swift
```

---

## Performance

- **Capture Rate**: 2-4 FPS (configurable via `CaptureManager.minimumFrameInterval`)
- **Detection Latency**: ~50-100ms per frame (Vision OCR + fader detection)
- **CPU Usage**: ~2-5% on M1 Mac (idle between detections)
- **Memory**: ~80-120 MB (includes frame buffers)

---

## Roadmap / Future Enhancements

- [ ] Interactive calibration mode in CLI (no GUI required)
- [ ] JSON output mode for scripting integration
- [ ] Frame preview in debug window (live capture visualization)
- [ ] ROI overlay drawing in debug window
- [ ] Configuration file support (`~/.vdjstatusrc`)
- [ ] Multiple window monitoring (dual VirtualDJ instances)
- [ ] Recording/playback mode for testing
- [ ] Linux support (requires alternative to ScreenCaptureKit)

---

## License

Same as parent project (VDJStatus).

---

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/VDJStatus/issues)
- **Documentation**: See `CLI_IMPLEMENTATION_PLAN.md` for architecture details
- **GUI App**: See main `README.md` in `VDJStatus/` directory

---

## Credits

Built with ❤️ using Swift, ScreenCaptureKit, and Vision framework.

Part of the **synesthesia-visuals** project for VJ system integration.

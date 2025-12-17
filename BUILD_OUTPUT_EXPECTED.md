# Expected Build Output on macOS

This document shows what you should see when building and running the CLI tool on macOS.

## Build Command

```bash
cd /path/to/synesthesia-visuals
swift build
```

## Expected Build Output

```
Building for debugging...
[1/10] Compiling VDJStatusCore DeckStateMachine.swift
[2/10] Compiling VDJStatusCore Detector.swift
[3/10] Compiling VDJStatusCore CalibrationModel.swift
[4/10] Compiling VDJStatusCore OSC.swift
[5/10] Compiling VDJStatusCore VisionOCR.swift
[6/10] Compiling VDJStatusCore CaptureManager.swift
[7/10] Compiling VDJStatusCore AppState.swift
[8/10] Compiling VDJStatusCore ContentView.swift
[9/10] Compiling VDJStatusCore CalibrationCanvas.swift
[10/10] Compiling VDJStatusCore MiniPreviewView.swift
[11/15] Compiling VDJStatusCLI CLILogger.swift
[12/15] Compiling VDJStatusCLI TerminalInput.swift
[13/15] Compiling VDJStatusCLI DebugWindow.swift
[14/15] Compiling VDJStatusCLI CLIRunner.swift
[15/15] Compiling VDJStatusCLI main.swift
[16/16] Linking vdjstatus-cli
Build complete! (XX.XXs)
```

## Run Command

```bash
swift run vdjstatus-cli
```

## Expected Runtime Output (Initial Startup)

```
🚀 VDJStatus CLI starting...
Target window: VirtualDJ
OSC output: 127.0.0.1:9000
Log interval: 2.0s

Press 'd' to toggle full GUI window, 'q' to quit

✓ Calibration loaded (8 ROIs)
✓ OSC configured
✓ FSM initialized
⚠️  Requesting screen recording permission...
   (Grant permission in System Settings → Privacy & Security → Screen Recording)
✓ Screen recording permission granted
🔍 Looking for window: VirtualDJ...
✓ Found window: VirtualDJ 2024 - Home Edition
  App: VirtualDJ
✓ Capture started

═══════════════════════════════════════════════════
Status monitoring active (every 2.0s)
═══════════════════════════════════════════════════

[2024-12-16T18:00:00Z]
  Deck 1: Artist Name - Track Title
          3:45 | Fader: 85%
  Deck 2: Another Artist - Another Track
          1:23 | Fader: 15%
  Master: Deck 1 🎵

[2024-12-16T18:00:02Z]
  Deck 1: Artist Name - Track Title
          3:47 | Fader: 85%
  Deck 2: Another Artist - Another Track
          1:25 | Fader: 15%
  Master: Deck 1 🎵
```

## When User Presses 'd' Key

**Console Output:**
```
GUI window opened
```

**What Happens:**
- Full GUI application window opens (800x900)
- Window appears in Dock
- All SwiftUI views render with live data
- Console logs continue appearing in terminal
- Both terminal and GUI show the same data in real-time

## Window Features (When Opened)

The window shows the complete VDJStatus GUI interface:

```
┌─────────────────────────────────────────────────────┐
│ VDJStatus (CLI Mode)                    [- □ ×]    │
├─────────────────────────────────────────────────────┤
│                                                     │
│ 1. Select VirtualDJ Window                          │
│    [VirtualDJ 2024 - Home Edition ▼]  [Refresh]    │
│    ✓ Capturing automatically started                │
│                                                     │
│ 2. Capture & Preview                                │
│    [Stop Capture]  ● Capturing                     │
│    ┌─────────────────────────────────────────┐     │
│    │  Master: Deck 1                          │     │
│    │  D1: Artist - Title [3:47]              │     │
│    │  D2: Artist - Title [1:25]              │     │
│    │                                          │     │
│    │  ┌──────────┐ ← Cyan ROI (Deck 1)       │     │
│    │  │  Artist  │                            │     │
│    │  └──────────┘                            │     │
│    │  ━━━━━━━━━━━ ← Red fader line           │     │
│    │                                          │     │
│    │  ┌──────────┐ ← Magenta ROI (Deck 2)    │     │
│    │  │  Artist  │                            │     │
│    │  └──────────┘                            │     │
│    └──────────────────────────────────────────┘     │
│                                                     │
│ 3. Calibrate Regions                                │
│    ☐ Enable Calibration Mode                       │
│    [D1 Artist ▼]  [Load]  [Save]                   │
│    x: 0.123, y: 0.456, w: 0.234, h: 0.567          │
│    Language Correction (for non-English names):     │
│    ☐ D1 Artist  ☐ D1 Title                         │
│    ☐ D2 Artist  ☐ D2 Title                         │
│                                                     │
│ 4. OSC Output                                       │
│    Host: [127.0.0.1]  Port: [9000]  ☑ Enabled      │
│                                                     │
│ Detection Results                                   │
│    Master: Deck 1          3:47                     │
│                                                     │
│    Deck 1 ⭐              │  Deck 2                 │
│    Artist: ...            │  Artist: ...            │
│    Title: ...             │  Title: ...             │
│    Time: 3:47             │  Time: 1:25             │
│    Fader: 85%             │  Fader: 15%             │
│                                                     │
│    OCR: 45ms  Avg: 52ms  Frame: 8ms  (1234 frames) │
│                                                     │
│ State Machine                                       │
│    ┌─────────────┐        ┌─────────────┐          │
│    │   Deck 1    │        │   Deck 2    │          │
│    │      ▶️      │   ←    │      ⏹      │          │
│    │  PLAYING    │ MASTER │  STOPPED    │          │
│    │   3:47      │        │   1:25      │          │
│    │   █████     │        │   ██        │          │
│    │    85%      │        │    15%      │          │
│    └─────────────┘        └─────────────┘          │
│                                                     │
│    Transition Log                                   │
│    18:00:02 Deck 1 → PLAYING (elapsed 3:45)         │
│    17:59:58 Deck 2 → STOPPED                        │
│    17:59:45 Master → Deck 1 (fader louder)          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## When User Presses 'd' Again

**Console Output:**
```
GUI window closed
```

**What Happens:**
- Window closes (hidden, not destroyed)
- Terminal logs continue
- CLI monitoring continues uninterrupted
- All state preserved

## When User Presses 'q'

**Console Output:**
```
Quit requested

Shutting down...
✓ Goodbye!
```

**Process exits cleanly**

## Common Build/Run Issues

### Issue 1: Swift Not Found
**Error:** `/bin/bash: swift: command not found`

**Solution:** This is expected on Linux. Build requires macOS with Swift toolchain installed.

### Issue 2: Screen Recording Permission
**Error:** `Screen recording permission denied`

**Solution:**
1. System Settings → Privacy & Security → Screen Recording
2. Enable Terminal.app (or your terminal)
3. Restart terminal
4. Run again

### Issue 3: VirtualDJ Window Not Found
**Error:** `Window not found: VirtualDJ`

**Solution:**
- Ensure VirtualDJ is running
- Window must be visible (not minimized)
- Try partial name: `vdjstatus-cli -w "Virtual"`

## System Requirements

- **macOS 13.0+** (Ventura or later)
- **Swift 5.9+**
- **Xcode Command Line Tools** (`xcode-select --install`)
- **VirtualDJ** running with visible window
- **Screen recording permission** granted

## File Sizes (Approximate)

```
.build/debug/vdjstatus-cli           ~2.5 MB
.build/release/vdjstatus-cli         ~800 KB (optimized)
```

## Performance Metrics

**Debug Build:**
- Compile time: ~15-20 seconds
- Binary size: ~2.5 MB
- Startup time: ~200ms
- OCR latency: 50-100ms per frame

**Release Build:**
- Compile time: ~30-40 seconds (with optimizations)
- Binary size: ~800 KB
- Startup time: ~100ms
- OCR latency: 30-70ms per frame

---

**Note**: This document describes expected behavior. Actual output may vary based on system configuration, VirtualDJ version, and skin customization.

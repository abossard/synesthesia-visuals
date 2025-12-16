# VDJStatus CLI - Quick Start Guide

Get up and running with the VDJStatus CLI tool in 5 minutes.

## Prerequisites Checklist

- [ ] **macOS 13.0+** (Ventura or later)
- [ ] **Xcode Command Line Tools** installed
- [ ] **VirtualDJ** installed and running
- [ ] **GUI app calibration** completed (one-time setup)

## Step 1: Install Xcode Command Line Tools (if needed)

```bash
xcode-select --install
```

## Step 2: Run GUI App for Initial Calibration

**Important**: You must calibrate ROI regions once before using the CLI tool.

1. Open and run **VDJStatus.app** (the GUI version)
2. Click "Calibrate" or open calibration mode
3. Draw 8 ROI rectangles:
   - Deck 1: Artist, Title, Elapsed, Fader
   - Deck 2: Artist, Title, Elapsed, Fader
4. Save calibration (stored automatically)
5. Close GUI app

Calibration file location:
```
~/Library/Application Support/VDJStatus/vdj_calibration.json
```

## Step 3: Grant Screen Recording Permission

On first run, macOS will prompt for permission:

1. **System Settings → Privacy & Security → Screen Recording**
2. Enable **Terminal.app** (or iTerm2, if using)
3. Restart terminal

## Step 4: Build and Run CLI Tool

```bash
# Navigate to project directory
cd /path/to/synesthesia-visuals

# Build the CLI tool
swift build

# Run with defaults
swift run vdjstatus-cli
```

**Expected output:**
```
🚀 VDJStatus CLI starting...
Target window: VirtualDJ
OSC output: 127.0.0.1:9000
Log interval: 2.0s

Press 'd' to toggle debug window, 'q' to quit

✓ Calibration loaded (8 ROIs)
✓ OSC configured
✓ FSM initialized
✓ Screen recording permission granted
✓ Found window: VirtualDJ 2024
✓ Capture started

═══════════════════════════════════════════════════
Status monitoring active (every 2.0s)
═══════════════════════════════════════════════════
```

## Step 5: Try Keyboard Commands

While the CLI is running:

- Press **`d`** → Toggle debug window (shows live data)
- Press **`q`** → Quit gracefully
- Press **`Ctrl+C`** → Force quit

## Step 6: Customize (Optional)

```bash
# Custom OSC destination
swift run vdjstatus-cli -- -h 192.168.1.100 -p 9001

# Different log interval (5 seconds)
swift run vdjstatus-cli -- -i 5.0

# Verbose logging
swift run vdjstatus-cli -- -v

# Show all options
swift run vdjstatus-cli -- --help
```

## Common Issues

### "Window not found: VirtualDJ"

**Solution**: Make sure VirtualDJ is running with a visible window.

```bash
# Try with explicit window name
swift run vdjstatus-cli -- -w "VirtualDJ 2024"
```

---

### "Screen recording permission denied"

**Solution**:
1. Open **System Settings → Privacy & Security → Screen Recording**
2. Enable **Terminal.app**
3. **Restart terminal** (important!)
4. Run again

---

### "No calibration data found"

**Solution**: Run the GUI app (VDJStatus.app) and complete calibration first.

---

### Terminal stuck / keypresses not working

**Solution**: Restore terminal settings
```bash
reset
# or
stty sane
```

---

## What's Next?

- **Read full documentation**: See `CLI_README.md`
- **Check implementation details**: See `CLI_IMPLEMENTATION_PLAN.md`
- **OSC integration**: Configure your VJ software to receive on port 9000
- **Debug window**: Press 'd' while running to see live detection data

---

## OSC Messages Reference

The CLI tool sends these OSC messages:

```
/vdj/deck1    (artist, title, elapsed, fader)
/vdj/deck2    (artist, title, elapsed, fader)
/vdj/master   (deck_number)
```

Example OSC listener (Python):
```python
from pythonosc import dispatcher, osc_server

def deck_handler(unused_addr, *args):
    artist, title, elapsed, fader = args
    print(f"Deck: {artist} - {title} | {elapsed:.1f}s | Fader: {fader:.2f}")

d = dispatcher.Dispatcher()
d.map("/vdj/deck1", deck_handler)
d.map("/vdj/deck2", deck_handler)

server = osc_server.ThreadingOSCUDPServer(("0.0.0.0", 9000), d)
print("Listening for OSC on port 9000...")
server.serve_forever()
```

---

## Support

- **Issues**: Open GitHub issue
- **Full docs**: `CLI_README.md`
- **Architecture**: `CLI_IMPLEMENTATION_PLAN.md`

---

**Enjoy monitoring VirtualDJ from the command line!** 🎵🎛️

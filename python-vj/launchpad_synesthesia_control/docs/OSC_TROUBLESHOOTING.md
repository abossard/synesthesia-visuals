# OSC Troubleshooting Guide

## Quick Diagnosis

The app now shows **ALL** OSC messages in the OSC Monitor panel (magenta border, right side of TUI). This makes it easy to diagnose connection issues.

### What You'll See

```
╔═ OSC Monitor (ALL Messages) ═╗
║ Total: 42 (✓=controllable ·=other) ║
║ ✓ /scenes/AlienCavern []      ║  <- Green = controllable
║ · /audio/beat/onbeat [1]      ║  <- Cyan = not controllable
║ ✓ /presets/Preset1 []         ║
║ · /audio/bpm [128]             ║
╚═══════════════════════════════╝
```

**Legend:**
- `✓` (green) = Controllable message (can be mapped to pads)
- `·` (cyan) = Non-controllable (beat, BPM, audio levels)
- **Total counter** = Shows how many messages received since app started

## Step 1: Test OSC Reception (Independent of Synesthesia)

First, verify the app can receive OSC messages at all:

### 1a. Start the TUI
```bash
cd /Users/abossard/Desktop/projects/synesthesia-visuals/python-vj/launchpad_synesthesia_control
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/python -m launchpad_synesthesia_control
```

### 1b. Send Test Messages

In a **separate terminal**, run:
```bash
cd /Users/abossard/Desktop/projects/synesthesia-visuals/python-vj/launchpad_synesthesia_control
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/python scripts/osc_test_sender.py
```

### 1c. Check Results

**Expected:** OSC Monitor panel shows:
```
Total: 8
✓ /scenes/TestScene1 []
✓ /scenes/TestScene2 []
✓ /presets/TestPreset []
· /audio/beat/onbeat [1]
· /audio/beat/onbeat [0]
✓ /controls/meta/hue [0.5]
✓ /controls/meta/saturation [0.8]
· /audio/bpm [128]
```

**If you see this:** ✅ OSC receiving is working! Problem is with Synesthesia configuration.

**If you see nothing:** ❌ OSC receiving has an issue. Check:
- Firewall blocking UDP port 9999
- Another application using port 9999
- Network issues (unlikely on localhost)

## Step 2: Check Connection Status

Look at the **Status panel** (cyan border, top right):

```
╔═══ CONNECTION STATUS ═══╗
║ Launchpad: ● Connected    ║
║ OSC: ● Connected          ║
║ Listen: :9999 (← Synesthesia) ║  <- App receives here
║ Send: :7777 (→ Synesthesia)   ║  <- App sends here
╠═══ SYNESTHESIA STATE ═══╣
```

**If OSC shows red ○ Disconnected:**
- Check if port 9999 is already in use
- Restart the app
- Check event log (bottom panel) for error messages

## Step 3: Configure Synesthesia

Once test messages work, configure Synesthesia to send to the correct port:

### 3a. Synesthesia OSC Output Settings

In Synesthesia:
1. Go to **Settings → OSC**
2. Enable **"Output Audio Variables"** checkbox
3. Set **IP Address**: `127.0.0.1`
4. Set **Port**: `9999` ⬅️ **CRITICAL!** (Not 9000!)
5. Click **Apply** or **Save**

### 3b. Test Synesthesia Connection

1. Play music in Synesthesia
2. Click different scenes/presets
3. Watch the OSC Monitor panel

**Expected:**
```
Total: 156
✓ /scenes/AlienCavern []
✓ /scenes/NeonCity []
· /audio/beat/onbeat [1]
· /audio/bpm [128.5]
✓ /presets/Preset3 []
```

Counter should increment rapidly, messages should flow continuously.

## Common Issues

### Issue: "No messages in OSC Monitor, counter stays at 0"

**Possible causes:**
1. Synesthesia not configured (see Step 3a above)
2. Synesthesia not running
3. OSC Output disabled in Synesthesia
4. Wrong port in Synesthesia (check it's 9999, NOT 9000!)

**Fix:** Follow Step 3a carefully, restart Synesthesia if needed

### Issue: "Test sender works, but Synesthesia doesn't"

**Cause:** Synesthesia port misconfiguration

**Fix:**
1. Open Synesthesia Settings → OSC
2. **Double-check port is 8000**
3. Make sure "Output Audio Variables" is **checked**
4. Click scenes in Synesthesia to trigger messages

### Issue: "OSC shows red ○ Disconnected in status"

**Possible causes:**
1. Port 9999 already in use by another app
2. python-osc library not installed
3. Firewall blocking

**Fix:**
```bash
# Check if port is in use
lsof -i :9999

# If another app is using it, stop that app first

# Reinstall python-osc if needed
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/pip install python-osc
```

### Issue: "Firewall warning on macOS"

**Cause:** macOS firewall blocking Python network access

**Fix:**
1. System Settings → Security & Privacy → Firewall
2. Click **Firewall Options**
3. Find Python in the list
4. Ensure it's set to **Allow incoming connections**
5. Restart the app

### Issue: "Messages appear but no controllable (✓) messages"

**Cause:** Synesthesia only sending audio/beat data, not scene/preset changes

**Fix:**
1. Click different scenes in Synesthesia
2. Change presets
3. Adjust meta controls (hue, saturation, etc.)

These actions trigger controllable messages that can be mapped to pads.

## Port Configuration Summary

| Direction | Port | Purpose | Configuration |
|-----------|------|---------|---------------|
| **Synesthesia → App** | **9999** | App receives messages | Set in **Synesthesia OSC Output** |
| **App → Synesthesia** | **7777** | App sends commands | Set in Synesthesia OSC Input (if available) |

**Remember:**
- Synesthesia sends **TO** port 9999
- App listens **ON** port 9999
- These must match!

## Verification Checklist

- [ ] Run test sender script → messages appear in OSC Monitor
- [ ] Status panel shows OSC: ● Connected
- [ ] Status panel shows "Listen: :9999 (← Synesthesia)"
- [ ] Synesthesia Settings → OSC Output enabled
- [ ] Synesthesia OSC Output port set to **9999** (not 9000!)
- [ ] Synesthesia is running
- [ ] Click scenes in Synesthesia → messages appear
- [ ] Green ✓ messages appear when clicking scenes/presets
- [ ] Cyan · messages appear when music is playing

## Still Not Working?

If you've followed all steps and still see no messages:

1. **Check Event Log** (bottom panel, blue border):
   - Look for "OSC connected" message
   - Look for any error messages

2. **Check Synesthesia version:**
   - OSC requires **Synesthesia Pro** license
   - Free version does not support OSC output

3. **Try the standalone monitor:**
   ```bash
   python scripts/osc_monitor.py 9999
   ```
   - If this shows messages but TUI doesn't → App issue
   - If this shows nothing → Synesthesia configuration issue

4. **Restart everything:**
   ```bash
   # Stop the app (Ctrl+C)
   # Close Synesthesia
   # Start Synesthesia
   # Configure OSC Output (port 9999)
   # Start the app
   ```

## Success Indicators

You know everything is working when:

✅ OSC Monitor panel shows increasing message counter
✅ Green ✓ messages appear when clicking Synesthesia scenes
✅ Cyan · messages appear when music is playing
✅ Status panel shows OSC: ● Connected
✅ Event log shows "OSC connected: :7777 → :9999"

Once you see these indicators, you can use Learn Mode (press `L`) to configure pads!

# OSC Port Configuration Guide

## The Problem

**You're not receiving OSC messages?** This is usually a port configuration mismatch.

## The Solution

### App Configuration (Fixed in Code)

```
Launchpad Control App:
├─ LISTENS on port 9999  ← Receives FROM Synesthesia
└─ SENDS to port 7777    → Sends TO Synesthesia
```

### Synesthesia Configuration (You Must Set This!)

Open Synesthesia Settings → OSC:

#### OSC Output (Synesthesia → App)
```
✅ Enable "Output Audio Variables"
   IP Address: 127.0.0.1
   Port: 9999          ← MUST match app's receive port!
```

#### OSC Input (App → Synesthesia)
```
✅ Enable "OSC Input" (if available)
   IP Address: 127.0.0.1
   Port: 7777          ← MUST match app's send port!
```

## Verification Steps

### Step 1: Run the OSC Monitor Script

```bash
cd python-vj/launchpad_synesthesia_control

# Listen on port 9999 (where app expects messages)
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/python scripts/osc_monitor.py 9999
```

### Step 2: Test in Synesthesia

1. Make sure Synesthesia is running
2. Verify OSC Output is enabled and set to `127.0.0.1:9999`
3. Play some music
4. Click scenes/presets in Synesthesia
5. Watch the monitor output

**Expected output:**
```
=============================================================
OSC Monitor - Listening on port 9999
=============================================================
Waiting for OSC messages from Synesthesia...

[10:30:45.123] /scenes/AlienCavern []
[10:30:46.456] /presets/Preset1 []
[10:30:47.789] /audio/beat/onbeat [1]
```

**If you see nothing:** OSC output not configured or disabled

### Step 3: Check in the TUI

Once the monitor works, run the app:
```bash
cd python-vj/launchpad_synesthesia_control
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/python -m launchpad_synesthesia_control
```

Watch the **OSC Monitor panel** (right side, magenta border). It should show controllable messages in real-time.

## Common Issues

### Issue 1: "No messages in monitor"

**Cause:** Synesthesia not configured to send OSC

**Fix:**
1. Open Synesthesia
2. Go to Settings (gear icon)
3. Find OSC section
4. Enable "Output Audio Variables"
5. Set IP: `127.0.0.1`
6. Set Port: `9999`
7. Click Apply/Save

### Issue 2: "Wrong port - using 7777"

**Why it's wrong:**
- Port 7777 is where the app **SENDS** to Synesthesia
- The app **LISTENS** on port 9999
- You need to monitor port 9999, not 7777!

**Fix:**
```bash
# WRONG - this is the SEND port
python scripts/osc_monitor.py 7777

# CORRECT - this is the RECEIVE port
python scripts/osc_monitor.py 9999
```

### Issue 3: "Firewall blocking"

**Symptoms:** Monitor shows no messages even though Synesthesia configured

**Fix (macOS):**
```bash
# Check if Python is allowed through firewall
System Preferences → Security & Privacy → Firewall → Firewall Options
```

Look for Python in the list and ensure it's allowed.

### Issue 4: "Synesthesia Pro only"

**Important:** OSC output requires **Synesthesia Pro license**

Free version doesn't support OSC output.

## Port Summary

| Direction | Port | Purpose | Configuration |
|-----------|------|---------|---------------|
| Synesthesia → App | **9999** | App receives messages | Set in Synesthesia OSC Output |
| App → Synesthesia | **7777** | App sends commands | Set in Synesthesia OSC Input |

**Remember:** The app listens where you need Synesthesia to send!

## Testing Checklist

- [ ] Synesthesia is running
- [ ] Synesthesia Pro license active (OSC requires Pro)
- [ ] OSC Output enabled in Synesthesia settings
- [ ] OSC Output IP set to `127.0.0.1`
- [ ] OSC Output Port set to `9999` (NOT 7777!)
- [ ] Music is playing in Synesthesia
- [ ] `osc_monitor.py 9999` shows messages
- [ ] TUI OSC Monitor panel shows messages
- [ ] Firewall allows Python network access

## Quick Test Command

```bash
# This will tell you immediately if OSC is working
cd python-vj/launchpad_synesthesia_control
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/python scripts/osc_monitor.py 9999
```

Then in Synesthesia: **Click a scene**

If you see `/scenes/SceneName []` appear → OSC is working! ✅

If you see nothing after 10 seconds → Check Synesthesia settings above

## Visual Diagram

```
┌─────────────────┐                    ┌──────────────────┐
│   Synesthesia   │                    │  Launchpad App   │
│                 │                    │                  │
│  OSC Output     │  Port 9999        │   UDP Server     │
│  127.0.0.1:9999 ├──────────────────→│ LISTENS on 9999  │
│                 │  Sends messages    │                  │
│                 │                    │                  │
│  OSC Input      │  Port 7777        │   UDP Client     │
│  127.0.0.1:7777 │←──────────────────┤ SENDS to 7777    │
│                 │  Receives commands │                  │
└─────────────────┘                    └──────────────────┘
```

## Next Steps

1. ✅ Configure Synesthesia to send to port **9999**
2. ✅ Run monitor: `python scripts/osc_monitor.py 9999`
3. ✅ Click scenes in Synesthesia
4. ✅ Verify messages appear
5. ✅ Run the app and watch OSC Monitor panel
6. ✅ Start configuring pads in learn mode!

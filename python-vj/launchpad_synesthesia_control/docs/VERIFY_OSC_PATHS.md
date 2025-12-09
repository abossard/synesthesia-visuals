# Verifying Synesthesia OSC Paths

## Problem

The codebase assumes Synesthesia sends beat information via `/audio/beat/onbeat`, but **this should be verified** for your specific Synesthesia version and configuration.

## Quick Verification

### Step 1: Run the OSC Monitor

```bash
cd python-vj/launchpad_synesthesia_control
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/python scripts/osc_monitor.py
```

### Step 2: Start Synesthesia

1. Open Synesthesia
2. Enable OSC Output:
   - Go to Settings → OSC
   - Enable "Output Audio Variables" checkbox
   - Set IP: `127.0.0.1`
   - Set Port: `8000`
3. Play some music with a clear beat

### Step 3: Check the Output

The monitor will show:
- All OSC messages received
- Beat-related messages highlighted with ⭐
- Message counts and formats

Example output:
```
=============================================================
⭐ BEAT-RELATED MESSAGES FOUND:
=============================================================
  /audio/beat/onbeat
    Format: (1,)
    Count: 423

💡 Use the address above for beat synchronization in your config!
```

### Step 4: Update the Code

If Synesthesia uses a **different** path than `/audio/beat/onbeat`, update:

**File: [app/domain/fsm.py](../app/domain/fsm.py:242)**
```python
# Change this line:
if event.address == "/audio/beat/onbeat":

# To whatever path you discovered:
if event.address == "/your/actual/beat/path":
```

## Common Synesthesia OSC Paths

Based on community knowledge, Synesthesia **may** use:

- `/audio/beat/onbeat` - Beat pulse (0 or 1)
- `/audio/beat` - Alternative beat path
- `/audio/bpm` - Current BPM
- `/audio/level` - Audio level
- `/audio/bass` - Bass level
- `/audio/mid` - Mid frequency level
- `/audio/high` - High frequency level

**But these should be verified for your setup!**

## Alternative: Check Synesthesia Documentation

1. Open Synesthesia
2. Click the **OSC button** (top right of control panel)
3. Enable OSC mapping mode
4. Click any audio/beat control to see its OSC address

## Troubleshooting

### No Messages Received?

Check:
- ✅ Synesthesia is running
- ✅ OSC Output is enabled in Synesthesia settings
- ✅ Output IP is set to `127.0.0.1`
- ✅ Output port matches monitor port (default 8000)
- ✅ Firewall isn't blocking UDP port 9999
- ✅ Music is playing (beat messages only sent when audio is active)

### Wrong Port?

Run the monitor on a different port:
```bash
python scripts/osc_monitor.py 9000  # Use port 7777
```

Then check Synesthesia's OSC output port setting.

## Technical Details

### OSC Configuration in Code

The app listens for OSC on port **8000** and sends to port **9000**:

**File: [app/ui/tui.py](../app/ui/tui.py:367-379)**
```python
send_port = 9000      # Synesthesia listens here
receive_port = 8000   # Synesthesia sends here
```

**File: [app/io/osc_synesthesia.py](../app/io/osc_synesthesia.py)**
- UDP client sends commands to port 7777
- UDP server receives messages on port 9999

### Beat Processing

When a beat message is received:

1. FSM updates `state.beat_pulse` (boolean)
2. Blink loop uses pulse to modulate LED brightness
3. Active SELECTOR pads blink in sync with beat

**File: [app/domain/blink.py](../app/domain/blink.py)**
```python
def compute_blink_phase(beat_pulse: bool, beat_phase: float) -> float:
    """Returns 1.0 on beat, 0.3 off beat."""
    return 1.0 if beat_pulse else 0.3
```

## Summary

**Before relying on beat sync:**
1. ✅ Run the OSC monitor
2. ✅ Verify Synesthesia's actual beat OSC path
3. ✅ Update fsm.py if path differs
4. ✅ Test with music playing

This ensures your Launchpad LEDs will **actually** blink in sync with the music! 🎵

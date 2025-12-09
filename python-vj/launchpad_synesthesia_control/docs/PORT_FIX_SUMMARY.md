# Port Configuration Fix Summary

## The Problem

The app was configured with **incorrect ports** based on an assumption about Synesthesia's default OSC configuration.

### OLD (WRONG) Configuration
```
App listens on: 8000
App sends to:   9000
```

### NEW (CORRECT) Configuration
```
App listens on: 9999  ← Synesthesia sends here
App sends to:   7777  ← Synesthesia receives here
```

## What Changed

### 1. Core Application Code

#### [app/ui/tui.py:424-425](../app/ui/tui.py#L424-L425)
```python
# OLD:
send_port = 9000
receive_port = 8000

# NEW:
send_port = 7777  # Synesthesia receives here
receive_port = 9999  # Synesthesia sends here
```

#### [app/ui/tui.py:179-180](../app/ui/tui.py#L179-L180) - Status Panel
```python
# OLD:
"║ Listen: :8000 (← Synesthesia)[/]",
"║ Send: :9000 (→ Synesthesia)[/]",

# NEW:
"║ Listen: :9999 (← Synesthesia)[/]",
"║ Send: :7777 (→ Synesthesia)[/]",
```

#### [app/io/osc_synesthesia.py:37-38](../app/io/osc_synesthesia.py#L37-L38) - Default Config
```python
# OLD:
send_port: int = 9000  # Synesthesia listens here (default)
receive_port: int = 8000  # Synesthesia sends here (default)

# NEW:
send_port: int = 7777  # Synesthesia listens here (default)
receive_port: int = 9999  # Synesthesia sends here (default)
```

### 2. Testing Scripts

#### [scripts/osc_test_sender.py](../scripts/osc_test_sender.py)
```python
# OLD: Sent to port 8000
# NEW: Sends to port 9999
client = udp_client.SimpleUDPClient("127.0.0.1", 9999)
```

#### [scripts/osc_monitor.py](../scripts/osc_monitor.py)
```python
# OLD: Default port 8000
# NEW: Default port 9999
def __init__(self, port=9999):
```

### 3. Documentation Updates

All documentation files updated to reflect correct ports:

- `docs/OSC_PORT_SETUP.md` - Complete port configuration guide
- `docs/OSC_TROUBLESHOOTING.md` - Troubleshooting with correct ports
- `docs/OSC_MONITOR_PANEL.md` - OSC panel documentation
- `docs/VERIFY_OSC_PATHS.md` - OSC path verification guide

## How to Use the Fixed Configuration

### In Synesthesia:

1. Open **Settings → OSC**
2. **OSC Output** (Synesthesia → App):
   - Enable: ✅
   - IP: `127.0.0.1`
   - Port: **9999**
3. **OSC Input** (App → Synesthesia):
   - Enable: ✅ (if available)
   - IP: `127.0.0.1`
   - Port: **7777**

### Testing:

```bash
# Run the app
cd python-vj/launchpad_synesthesia_control
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/python -m launchpad_synesthesia_control

# In another terminal: Send test messages
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/python scripts/osc_test_sender.py

# Or monitor OSC directly
/Users/abossard/Desktop/projects/synesthesia-visuals/.venv/bin/python scripts/osc_monitor.py 9999
```

## Verification

The TUI now clearly shows the correct ports in the Status panel:

```
╔═══ CONNECTION STATUS ═══╗
║ OSC: ● Connected          ║
║ Listen: :9999 (← Synesthesia)
║ Send: :7777 (→ Synesthesia)
╚═══════════════════════════╝
```

And the OSC Monitor panel shows ALL incoming messages (not just controllable ones):

```
╔═ OSC Monitor (ALL Messages) ═╗
║ Total: 42 (✓=controllable ·=other) ║
║ ✓ /scenes/AlienCavern []      ║
║ · /audio/beat/onbeat [1]      ║
║ ✓ /presets/Preset1 []         ║
╚═══════════════════════════════╝
```

## Why This Matters

With the correct ports:
- ✅ OSC Monitor panel will show messages
- ✅ Learn mode will capture OSC events
- ✅ Pad configuration will work
- ✅ Beat sync will function
- ✅ Scene/preset changes will be detected

## Quick Test

1. Start the app
2. In another terminal: `python scripts/osc_test_sender.py`
3. Watch the OSC Monitor panel in the TUI
4. You should see: `Total: 8` and a list of test messages

If you see messages → **Everything is working!**

If you see nothing → Check firewall or Synesthesia configuration.

# MIDI Router - VJ Bus Integration

## Overview

The MIDI Router has been integrated into the VJ Bus architecture as a managed worker with auto-healing capabilities. This allows MIDI controller input to be seamlessly integrated with the rest of the VJ system.

## Architecture

```
Console → Process Manager → MIDI Router Worker
                                   ↓
                              MIDI Router
                                   ↓
                         OSC Broadcasting
```

### Components

**MIDI Router Worker** (`workers/midi_router_worker.py`):
- VJ Bus worker wrapper for MIDI router
- Auto-reconnection to MIDI controllers
- Health monitoring and auto-restart
- OSC telemetry broadcasting

**MIDI Router** (`midi_router.py`):
- Core MIDI processing logic
- Toggle state management
- MIDI device management
- OSC message broadcasting

## Features

### Auto-Start
- MIDI router automatically starts with the console
- No manual configuration required
- Auto-detects available MIDI controllers

### Auto-Healing
- Monitors MIDI router health
- Auto-restarts on failure
- Attempts reconnection to controllers
- Exponential backoff on repeated failures

### OSC Integration
- Broadcasts toggle state changes to `/midi/toggle/{note}`
- Other VJ components can react to MIDI input
- Real-time state synchronization

### Configuration Persistence
- Toggle configurations saved to `midi_router_config.json`
- Controller selection persists across restarts
- Toggle names and mappings preserved

## Usage

### Starting the System

The MIDI router starts automatically with the console:

```bash
cd python-vj
./start_vj.sh
```

The MIDI router worker will:
1. Load or create default configuration
2. Auto-detect available MIDI controllers
3. Start routing MIDI messages
4. Broadcast state changes via OSC

### Monitoring

Check MIDI router status in the console:
- Press `0` for Overview screen
- Look for `midi_router` in workers list
- Check status: `running` or `stopped`

### VJ Bus Commands

Send commands to the MIDI router via VJ Bus:

```python
from vj_bus.client import VJBusClient

client = VJBusClient()

# Get toggle states
response = client.send_command(
    "midi_router",
    "get_toggles",
    {},
    timeout=5.0
)

# Force reconnection
response = client.send_command(
    "midi_router",
    "reconnect",
    {},
    timeout=5.0
)
```

### Telemetry

The MIDI router publishes telemetry via VJ Bus:

**Worker State** (`telemetry.state`):
```json
{
  "status": "running",
  "uptime_sec": 120.5,
  "metrics": {
    "running": true,
    "controller": "MIDI Controller Name",
    "toggle_count": 8
  }
}
```

## Configuration

### MIDI Router Config File

Location: `python-vj/midi_router_config.json`

```json
{
  "input_device": {
    "name": "MIDI Controller",
    "port_id": 0
  },
  "toggles": [
    {
      "note": 36,
      "name": "Toggle 1",
      "state": false
    }
  ]
}
```

### Worker Config

Edit `workers/midi_router_worker.py`:

```python
config={
    "config_file": "midi_router_config.json",
    "auto_reconnect": True,
    "reconnect_interval": 5.0,  # Seconds
}
```

## Process Manager Integration

The MIDI router is managed by the process manager daemon:

**Process Manager** monitors:
- PID checks (is process alive?)
- Heartbeat checks (is worker responsive?)
- Auto-restart on crash

**Configuration**:
```python
# workers/process_manager_daemon.py
WORKER_CONFIGS = [
    # ...
    ("midi_router", "workers/midi_router_worker.py"),
]
```

## Auto-Healing Behavior

### Normal Operation
```
21:30:00 - INFO - MIDI Router Worker starting...
21:30:00 - INFO - ✓ MIDI router started
21:30:00 - INFO - ✓ Connected to MIDI controller: Launchpad Mini MK3
```

### Controller Disconnected
```
21:35:00 - DEBUG - Router not running, attempting restart...
21:35:05 - INFO - ✓ Reconnected to: Launchpad Mini MK3
```

### Worker Crash
```
21:40:00 - WARNING - ⚠️  Worker midi_router crashed (exit code: 1)
21:40:00 - INFO - 🔄 Auto-restarting midi_router in 5s (attempt 1/10)
21:40:05 - INFO - ✓ Worker midi_router restarted (PID: 12345)
```

## Troubleshooting

### MIDI Controller Not Detected

**Check available controllers**:
```bash
python verify_midi_setup.py
```

**Manually set controller**:
Edit `midi_router_config.json` with correct device name.

### Worker Not Starting

**Check logs** (Press `5` in console):
```
- Look for "MIDI Router Worker starting..."
- Check for error messages
```

**Test worker directly**:
```bash
python workers/midi_router_worker.py
```

### OSC Messages Not Broadcasting

**Check OSC manager**:
- Ensure `osc_manager.py` is available
- Check OSC_AVAILABLE flag in worker logs
- Verify OSC target configuration

## Integration with Other Workers

### Spotify Monitor
MIDI toggles can control playback:
```python
# React to MIDI toggle changes
if toggle_state:
    spotify.play()
else:
    spotify.pause()
```

### VirtualDJ Monitor
MIDI controls for VJ effects:
```python
# Map MIDI toggles to VirtualDJ commands
midi_to_vdj_mapping = {
    36: "effect_1",
    37: "effect_2",
}
```

### Audio Analyzer
MIDI triggers for audio features:
```python
# Enable/disable audio features via MIDI
if toggle_state:
    audio_analyzer.enable_pitch_detection()
```

## Advanced Usage

### Custom Toggle Mapping

Create custom toggle configurations:

```python
from midi_domain import ToggleConfig, RouterConfig

config = RouterConfig(
    toggles=[
        ToggleConfig(note=36, name="Bass Boost", state=False),
        ToggleConfig(note=37, name="Treble Boost", state=False),
        ToggleConfig(note=38, name="Reverb", state=True),
    ]
)

config_manager.save(config)
```

### OSC Message Handling

Listen for MIDI toggle changes in other workers:

```python
from osc_manager import osc

@osc.route('/midi/toggle/36')
def handle_toggle(name, state):
    print(f"Toggle {name} changed to {state}")
    # React to toggle change
```

## Future Enhancements

- [ ] MIDI learn mode via VJ Bus commands
- [ ] Toggle state synchronization across workers
- [ ] MIDI CC (continuous controller) support
- [ ] Multiple controller support
- [ ] MIDI output to other applications
- [ ] Visual feedback in console for MIDI events

## Documentation

See also:
- **MIDI_ROUTER.md** - Core MIDI router documentation
- **MIDI_ROUTER_QUICK_REF.md** - Quick reference guide
- **AUTO_HEALING_GUIDE.md** - Auto-healing system details
- **README_STARTUP.md** - Quick start guide

---

**Status**: ✅ Integrated and Tested

The MIDI router is now fully integrated with auto-start and auto-healing!

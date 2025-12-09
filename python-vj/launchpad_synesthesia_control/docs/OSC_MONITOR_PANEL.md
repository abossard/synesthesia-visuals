# OSC Monitor Panel

## Overview

The TUI now includes a **real-time OSC Monitor panel** that shows incoming controllable messages from Synesthesia. This makes it easy to:

- ✅ Verify Synesthesia is sending OSC messages
- ✅ See which commands are being triggered
- ✅ Debug learn mode issues
- ✅ Confirm OSC configuration is correct

## Location in TUI

The OSC Monitor is in the **right column**, between Status and Learn Mode panels:

```
┌──────────────────────┬─────────────┐
│                      │   Status    │
│   Launchpad Grid     │─────────────│
│                      │ OSC Monitor │ <-- HERE
│                      │─────────────│
│                      │ Learn Mode  │
├──────────────────────┴─────────────┤
│          Event Log                 │
└────────────────────────────────────┘
```

## What It Shows

### Controllable Messages Only

The panel **filters** to show only **controllable** OSC messages:
- ✅ `/scenes/*` - Scene changes
- ✅ `/presets/*` - Preset changes
- ✅ `/favslots/*` - Favorite slots
- ✅ `/playlist/*` - Playlist controls
- ✅ `/controls/meta/*` - Meta controls (hue, saturation, etc.)
- ✅ `/controls/global/*` - Global controls

### Filtered Out

These messages are **not** shown (to reduce noise):
- ❌ `/audio/beat/onbeat` - Beat pulse (too frequent)
- ❌ `/audio/bpm` - BPM updates
- ❌ `/audio/level` - Audio levels
- ❌ `/audio/bass`, `/audio/mid`, etc. - Frequency analysis

## Display Format

Messages appear in green with their arguments:

```
╔═ OSC Monitor (Controllable) ═╗
║ /scenes/AlienCavern []        ║
║ /presets/Preset1 []           ║
║ /controls/meta/hue [0.5]      ║
║ /scenes/NeonCity []            ║
║ ...                            ║
╚════════════════════════════════╝
```

### Features
- Shows last **10 messages** (scrolls automatically)
- Stores last **50 messages** in memory
- Updates in **real-time** as messages arrive
- Shows "Waiting for OSC messages..." when empty

## Usage Examples

### Verify Synesthesia Connection

1. Start the TUI
2. Look at OSC Monitor panel
3. In Synesthesia, click a scene
4. You should see: `/scenes/YourScene []` appear in the panel

If nothing appears → OSC not configured correctly!

### Debug Learn Mode

When in learn mode:

1. Press `L` to enter learn mode
2. Click a pad
3. Status shows: "Learn: Recording OSC"
4. Trigger action in Synesthesia
5. **Watch OSC Monitor** - messages should appear!
6. If no messages appear after 5 seconds → No OSC received

### Find the Correct Beat Path

1. Play music in Synesthesia with a clear beat
2. Watch the OSC Monitor panel
3. Look for beat-related messages like:
   - `/audio/beat/onbeat [1]` (on beat)
   - `/audio/beat/onbeat [0]` (off beat)
4. If you see a **different** path → Update `fsm.py` with correct path

## Code Implementation

### New Widget: [app/ui/tui.py:202-235](../app/ui/tui.py#L202-L235)

```python
class OscMonitorPanel(VerticalScroll):
    """Shows recent controllable OSC messages from Synesthesia."""

    def add_osc_message(self, address: str, args: list):
        """Add a controllable OSC message."""
        # Filters using OscCommand.is_controllable()
        # Shows last 10, stores last 50
```

### Integration: [app/ui/tui.py:507-512](../app/ui/tui.py#L507-L512)

```python
async def _handle_osc_event_async(self, event: OscEvent):
    # Update OSC monitor (only controllable messages)
    osc_monitor = self.query_one("#osc_monitor", OscMonitorPanel)
    osc_monitor.add_osc_message(event.address, event.args)
```

### Layout: [app/ui/tui.py:276-318](../app/ui/tui.py#L276-L318)

- Grid: 3 columns × 4 rows
- Launchpad grid: 2 cols × 3 rows (left)
- Status, OSC, Learn: 1 col each (right, stacked)
- Event log: 3 cols × 1 row (bottom)

## Troubleshooting

### Panel Shows "Waiting for OSC messages..."

**Possible causes:**
1. Synesthesia not running
2. OSC output not enabled in Synesthesia
3. Wrong IP/port configuration
4. No actions triggered in Synesthesia

**Solutions:**
- Check Synesthesia Settings → OSC
- Verify output enabled
- Confirm IP: `127.0.0.1`, Port: `8000`
- Click scenes/presets in Synesthesia

### Messages Appear But Learn Mode Doesn't Work

**Possible cause:** Message is not in controllable prefix list

**Solution:**
1. Note the OSC address from the monitor
2. Check if address starts with controllable prefix
3. If not, update `model.py` to add the prefix

### Panel Too Small / Can't See Messages

**Adjust in [app/ui/tui.py](../app/ui/tui.py):**

```python
def update_display(self):
    for msg in self.osc_messages[-10:]:  # Change -10 to -15 for more
        self.mount(Label(msg))
```

Or adjust grid row heights in CSS:
```python
grid-rows: 2fr 1fr 1fr 1fr;  # Make middle row bigger: 2fr
```

## Benefits

### For Users
- ✅ Visual confirmation OSC is working
- ✅ Immediate feedback when triggering Synesthesia
- ✅ Easy debugging of learn mode issues
- ✅ No need for external OSC monitoring tools

### For Developers
- ✅ Real-time protocol inspection
- ✅ Helps identify new controllable paths
- ✅ Validates OSC filtering logic
- ✅ Simplifies troubleshooting

## Related Files

- **Implementation:** [app/ui/tui.py](../app/ui/tui.py)
- **OSC Model:** [app/domain/model.py](../app/domain/model.py) (controllable prefixes)
- **OSC Manager:** [app/io/osc_synesthesia.py](../app/io/osc_synesthesia.py)
- **External Monitor:** [scripts/osc_monitor.py](../scripts/osc_monitor.py) (standalone tool)

## Comparison: Panel vs Script

| Feature | OSC Monitor Panel | `osc_monitor.py` Script |
|---------|-------------------|------------------------|
| **Runs in TUI** | ✅ Yes | ❌ No (standalone) |
| **Shows beat messages** | ❌ Filtered out | ✅ Shows all |
| **Real-time filtering** | ✅ Controllable only | ⚠️ Shows all (noisy) |
| **Summary stats** | ❌ No | ✅ Yes (on exit) |
| **Use case** | Live monitoring during normal use | Deep debugging, finding beat path |

Use the **panel** for everyday monitoring. Use the **script** for detailed analysis.

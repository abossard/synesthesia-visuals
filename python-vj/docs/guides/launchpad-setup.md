# Launchpad Mini MK3 Setup

Complete guide for using the Novation Launchpad Mini MK3 in Programmer Mode with Python VJ tools.

**Source:** Novation "Launchpad Mini [MK3] Programmer's Reference Manual"

---

## Quick Start

```python
import mido

# Find and open MIDI port (use MIDI, not DAW)
output = mido.open_output('LPMiniMK3 MIDI Out')
input_port = mido.open_input('LPMiniMK3 MIDI In')

# Enter Programmer Mode via SysEx
sysex = [0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01]
output.send(mido.Message('sysex', data=sysex))

# Light a pad (row 2, col 3 = note 34, green = 21)
output.send(mido.Message('note_on', note=34, velocity=21))
```

---

## MIDI Interfaces

| Port Name | Purpose | Use From Python |
|-----------|---------|-----------------|
| `LPMiniMK3 MIDI In/Out` | Programmer Mode & Lighting | ✅ Yes |
| `LPMiniMK3 DAW In/Out` | DAW integration (Ableton, Logic) | ❌ No |

**Note:** Device sends Note On with velocity 0 for Note Off.

---

## Entering Programmer Mode

### Manual (Front Panel)

1. **Hold Session** button (~0.5 seconds)
2. Press **orange Scene Launch button** (bottom right area)
3. Release Session

All pads will be dark initially—send MIDI to light them.

### Programmatic (SysEx)

```python
# Enter Programmer Mode
# F0 00 20 29 02 0D 0E 01 F7
sysex = [0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01]
output.send(mido.Message('sysex', data=sysex))

# Exit to Live Mode
sysex = [0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x00]
output.send(mido.Message('sysex', data=sysex))
```

---

## Pad Layout

### Main Grid (8×8 = 64 pads)

Notes arranged in decimal grid pattern:

```
Row 7: 81  82  83  84  85  86  87  88    ← Top
Row 6: 71  72  73  74  75  76  77  78
Row 5: 61  62  63  64  65  66  67  68
Row 4: 51  52  53  54  55  56  57  58
Row 3: 41  42  43  44  45  46  47  48
Row 2: 31  32  33  34  35  36  37  38
Row 1: 21  22  23  24  25  26  27  28
Row 0: 11  12  13  14  15  16  17  18    ← Bottom
       ↑                            ↑
     Col 0                        Col 7
```

**Formula:** `note = (row + 1) * 10 + (col + 1)`

### Top Row (CC Messages)

```
CC 91  CC 92  CC 93  CC 94  CC 95  CC 96  CC 97  CC 98
```

Values: 127 pressed, 0 released

### Right Column (Scene Launch)

```
Note 89  ← Row 7
Note 79
Note 69
Note 59
Note 49
Note 39
Note 29
Note 19  ← Row 0
```

**Formula:** `note = (row + 1) * 10 + 9`

---

## LED Control

### Set Pad Color

```python
# Grid pad: Note On with velocity = color
note = (row + 1) * 10 + (col + 1)
output.send(mido.Message('note_on', note=note, velocity=color))

# Top row: Control Change with value = color
output.send(mido.Message('control_change', control=91+col, value=color))

# Turn off: velocity/value = 0
output.send(mido.Message('note_on', note=note, velocity=0))
```

### Color Palette

| Velocity | Color | Hex |
|----------|-------|-----|
| 0 | Off | #000000 |
| 3 | White | #FFFFFF |
| 5 | Red | #FF0000 |
| 9 | Orange | #FF6600 |
| 13 | Yellow | #FFFF00 |
| 17 | Green (dim) | #006600 |
| 21 | Green | #00FF00 |
| 37 | Cyan | #00FFFF |
| 41 | Blue (dim) | #000066 |
| 45 | Blue | #0066FF |
| 53 | Purple | #9900FF |
| 57 | Pink | #FF00FF |

**Pulse mode:** Add 64 to color value (e.g., pulsing red = 69)

### Python Constants

```python
LP_OFF = 0
LP_RED_DIM = 1
LP_WHITE = 3
LP_RED = 5
LP_ORANGE = 9
LP_YELLOW = 13
LP_GREEN_DIM = 17
LP_GREEN = 21
LP_CYAN = 37
LP_BLUE_DIM = 41
LP_BLUE = 45
LP_PURPLE = 53
LP_PINK = 57
```

---

## Receiving Input

```python
def on_pad_press(msg):
    if msg.type == 'note_on' and msg.velocity > 0:
        row = (msg.note // 10) - 1
        col = (msg.note % 10) - 1
        print(f"Grid ({col}, {row}) pressed")
    
    elif msg.type == 'control_change' and msg.value > 0:
        button = msg.control - 91
        print(f"Top button {button} pressed")

for msg in input_port:
    on_pad_press(msg)
```

### Coordinate Conversion

```python
def note_to_grid(note):
    """Convert MIDI note to (col, row) or None if invalid."""
    row = (note // 10) - 1
    col = (note % 10) - 1
    if 0 <= row <= 7 and 0 <= col <= 7:
        return (col, row)
    if col == 8 and 0 <= row <= 7:
        return (8, row)  # Right column
    return None

def grid_to_note(col, row):
    """Convert (col, row) to MIDI note."""
    return (row + 1) * 10 + (col + 1)
```

---

## VJ Integration

The `launchpad_synesthesia_control` app provides high-level async interface:

```python
from launchpad_synesthesia_control.app.io.midi_launchpad import (
    LaunchpadDevice, LaunchpadConfig, PadId
)

config = LaunchpadConfig(auto_detect=True)
device = LaunchpadDevice(config)

await device.connect()  # Auto-enters Programmer Mode

device.set_led(PadId(x=3, y=2), color=21)  # Green

def on_press(pad_id, velocity):
    print(f"Pad {pad_id.x}, {pad_id.y}")

device.set_pad_callback(on_press)
await device.start_listening()
```

---

## Advanced: RGB LED Control

```python
# SysEx RGB: F0 00 20 29 02 0D 03 03 [pad] [R] [G] [B] F7
pad = 34
r, g, b = 127, 64, 0  # Orange
sysex = [0x00, 0x20, 0x29, 0x02, 0x0D, 0x03, 0x03, pad, r, g, b]
output.send(mido.Message('sysex', data=sysex))
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Not detected | Check USB, verify in `mido.get_input_names()` |
| No MIDI received | Use MIDI port, not DAW port |
| LEDs not responding | Verify Programmer Mode active, test note 11 velocity 5 |
| LEDs stuck on | Clear all before exit: send velocity 0 to all notes |

### Clear All LEDs

```python
for row in range(8):
    for col in range(8):
        note = (row + 1) * 10 + (col + 1)
        output.send(mido.Message('note_on', note=note, velocity=0))
```

---

## Quick Reference

### SysEx Commands

| Command | Bytes |
|---------|-------|
| Enter Programmer Mode | `F0 00 20 29 02 0D 0E 01 F7` |
| Exit to Live Mode | `F0 00 20 29 02 0D 0E 00 F7` |

### Formulas

```python
# Grid note
note = (row + 1) * 10 + (col + 1)

# Top row CC
cc = 91 + col

# Right column
note = (row + 1) * 10 + 9

# Note → Grid
row = (note // 10) - 1
col = (note % 10) - 1
```

---

## See Also

- [Launchpad Synesthesia Control](../../launchpad_synesthesia_control/README.md) — Full app documentation
- [mido documentation](https://mido.readthedocs.io/) — Python MIDI library

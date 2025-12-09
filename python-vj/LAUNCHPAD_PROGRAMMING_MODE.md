# Launchpad Mini [MK3] – Programmer Mode Reference

Complete guide for using the Novation Launchpad Mini MK3 in Programmer Mode with Python VJ tools.

All details are taken from Novation's **"Launchpad Mini [MK3] Programmer's Reference Manual"**.

---

## 1. MIDI Interfaces

The Launchpad Mini MK3 presents two separate MIDI interfaces when connected via USB:

| Interface | Port Name | Purpose | Usage |
|-----------|-----------|---------|-------|
| **DAW Port** | `LPMiniMK3 DAW In/Out` | DAW Session/Fader integration | For use with Ableton Live, Logic, etc. |
| **MIDI Port** | `LPMiniMK3 MIDI In/Out` | Programmer Mode & Lighting Custom Modes | **Use this from Python** |

### MIDI Implementation Notes

- The device sends **Note On with velocity 0** for Note Off events
- It accepts either real Note Off messages OR Note On with velocity 0
- For Python applications, connect to the **MIDI In/Out** port, not the DAW port

---

## 2. Entering / Leaving Programmer Mode

### 2.1 From the Front Panel (Manual Method)

1. **Hold Session** button for about 0.5 seconds to open the setup/LED menu
2. The bottom Scene Launch buttons will show different layout options:
   - **Green button** → Live mode (Session, Drum, Keys, User layouts)
   - **Orange button** → **Programmer Mode**
3. **Press the orange Scene Launch button** to enter Programmer Mode
4. **Release Session** button to exit the settings menu

**Visual Indication:**
- In Programmer Mode, all pads will be dark initially (this is expected)
- You must send MIDI messages to light the LEDs

### 2.2 Via SysEx – Layout Select (Programmatic Method)

#### SysEx Header Format

All Launchpad Mini MK3 SysEx messages start with:

```
F0 00 20 29 02 0D    ; Manufacturer ID + Product ID
```

#### Enter Programmer Mode

```
F0 00 20 29 02 0D 0E 01 F7
```

**Breakdown:**
- `F0` - SysEx start
- `00 20 29` - Novation Manufacturer ID
- `02` - Product type (Launchpad)
- `0D` - Product model (Mini MK3)
- `0E` - Layout selection command
- `01` - Programmer mode
- `F7` - SysEx end

#### Python Implementation

```python
import mido

# Open MIDI port
output = mido.open_output('LPMiniMK3 MIDI Out')

# Enter Programmer mode
programmer_mode = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x0D, 0x0E, 0x01, 0xF7]
output.send(mido.Message('sysex', data=programmer_mode[1:-1]))  # Omit F0 and F7
```

**Note:** The `mido` library automatically adds `F0` and `F7`, so only send the data bytes in between.

#### Exit Programmer Mode (Return to Live Mode)

```
F0 00 20 29 02 0D 0E 00 F7
```

Replace the `01` with `00` to return to the default Live mode.

---

## 3. Pad Layout in Programmer Mode

### 3.1 Grid Coordinates

The Launchpad provides **82 buttons** in Programmer Mode:

| Section | Buttons | Notes/CC | Description |
|---------|---------|----------|-------------|
| Main Grid | 8×8 = 64 pads | Notes 11-88 | Main performance surface |
| Top Row | 8 buttons | CC 91-98 | Function buttons |
| Right Column | 8 buttons | Notes 19, 29, ..., 89 | Scene Launch buttons |

### 3.2 Main Grid (8×8) Note Mapping

Notes are arranged in a **decimal grid pattern**:

```
Row 7: 81  82  83  84  85  86  87  88    (Top row of grid)
Row 6: 71  72  73  74  75  76  77  78
Row 5: 61  62  63  64  65  66  67  68
Row 4: 51  52  53  54  55  56  57  58
Row 3: 41  42  43  44  45  46  47  48
Row 2: 31  32  33  34  35  36  37  38
Row 1: 21  22  23  24  25  26  27  28
Row 0: 11  12  13  14  15  16  17  18    (Bottom row of grid)
       ↑                            ↑
     Col 0                        Col 7
```

**Formula:** `note = (row + 1) * 10 + (col + 1)`

**Example:** Button at column 3, row 5 → `(5+1)*10 + (3+1) = 64`

### 3.3 Top Row (CC Messages)

The top row of 8 buttons send Control Change (CC) messages:

```
CC 91  CC 92  CC 93  CC 94  CC 95  CC 96  CC 97  CC 98
```

- **Controller numbers:** 91-98
- **Values:** 127 when pressed, 0 when released
- Use these for modes, toggles, or navigation

### 3.4 Right Column (Scene Launch Buttons)

The right column of 8 buttons send Note messages:

```
Note 89  ← Top (corresponds to grid row 7)
Note 79
Note 69
Note 59
Note 49
Note 39
Note 29
Note 19  ← Bottom (corresponds to grid row 0)
```

**Formula:** `note = (row + 1) * 10 + 9`

---

## 4. LED Control

### 4.1 Basic LED Commands

#### Setting Grid Pad Color

Send a **Note On** message with the velocity as the color value:

```python
# Light pad at row 2, col 3 with green (velocity 21)
note = (2 + 1) * 10 + (3 + 1)  # = 34
output.send(mido.Message('note_on', note=34, velocity=21))
```

#### Setting Top Row Button Color

Send a **Control Change** message:

```python
# Light top row button 4 with blue (value 45)
output.send(mido.Message('control_change', control=94, value=45))
```

#### Turning Off LEDs

Send velocity/value 0:

```python
output.send(mido.Message('note_on', note=34, velocity=0))
```

### 4.2 Color Palette

The Launchpad Mini MK3 supports **128 colors** indexed by velocity values 0-127.

#### Standard Colors (Most Commonly Used)

| Velocity | Color | Hex Approx | Usage |
|----------|-------|------------|-------|
| 0 | Off | #000000 | Inactive/dark |
| 1 | Red (dim 1) | #330000 | Very dim red |
| 2 | Red (dim 2) | #660000 | Dim red |
| 3 | White | #FFFFFF | Bright white |
| 5 | Red | #FF0000 | Bright red |
| 9 | Orange | #FF6600 | Orange |
| 13 | Yellow | #FFFF00 | Yellow |
| 17 | Green (dim) | #006600 | Dim green |
| 21 | Green | #00FF00 | Bright green |
| 37 | Cyan | #00FFFF | Cyan |
| 41 | Blue (dim) | #000066 | Dim blue |
| 45 | Blue | #0066FF | Bright blue |
| 53 | Purple | #9900FF | Purple |
| 57 | Pink | #FF00FF | Pink/Magenta |

#### Full Palette Structure

The full 128-color palette is organized as follows:

**Colors 0-63:** Static colors
- 0-15: Grayscale and primary colors
- 16-63: Full RGB palette in a grid layout

**Colors 64-127:** Duplicate colors with **pulse/flash modes**

For the complete palette, refer to the **Launchpad Mini MK3 Programmer's Reference Manual** Appendix A.

### 4.3 Python Color Constants

Use these constants in your code (from `midi_launchpad.py`):

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

## 5. Receiving Input Events

### 5.1 Callback Pattern

```python
import mido

def on_pad_press(msg):
    if msg.type == 'note_on' and msg.velocity > 0:
        # Main grid or right column
        print(f"Pad pressed: Note {msg.note}, Velocity {msg.velocity}")
    
    elif msg.type == 'control_change' and msg.value > 0:
        # Top row
        print(f"Top button pressed: CC {msg.control}, Value {msg.value}")

# Open input port
input_port = mido.open_input('LPMiniMK3 MIDI In')

# Listen for events
for msg in input_port:
    on_pad_press(msg)
```

### 5.2 Coordinate Conversion

Convert MIDI notes back to grid coordinates:

```python
def note_to_grid(note):
    """Convert MIDI note to (col, row) coordinates."""
    row = (note // 10) - 1
    col = (note % 10) - 1
    
    # Validate main grid
    if 0 <= row <= 7 and 0 <= col <= 7:
        return (col, row)
    
    # Check for right column
    if col == 8 and 0 <= row <= 7:
        return (8, row)  # Right column
    
    return None  # Invalid note

# Example
col, row = note_to_grid(34)  # Returns (3, 2)
```

---

## 6. Python VJ Integration

### 6.1 Current Implementation

The `launchpad_synesthesia_control` app uses the Launchpad in Programmer Mode for bi-directional control of Synesthesia VJ software.

**Key Features:**
- ✅ Automatic Programmer Mode entry via SysEx
- ✅ Full 82-button grid support
- ✅ LED feedback with beat-synced blinking
- ✅ Learn mode for easy pad mapping
- ✅ Graceful degradation (works without hardware)

**Location:** `python-vj/launchpad_synesthesia_control/`

### 6.2 LaunchpadDevice Class

The `LaunchpadDevice` class in `app/io/midi_launchpad.py` provides a high-level async interface:

```python
from launchpad_synesthesia_control.app.io.midi_launchpad import (
    LaunchpadDevice, LaunchpadConfig, PadId
)

# Create device
config = LaunchpadConfig(auto_detect=True)
device = LaunchpadDevice(config)

# Connect (automatically enters Programmer Mode)
await device.connect()

# Set LED
device.set_led(PadId(x=3, y=2), color=21)  # Green at (3, 2)

# Register callback
def on_pad_press(pad_id, velocity):
    print(f"Pad {pad_id.x}, {pad_id.y} pressed with velocity {velocity}")

device.set_pad_callback(on_pad_press)

# Start listening
await device.start_listening()
```

---

## 7. Troubleshooting

### Launchpad Not Detected

**Symptom:** "Launchpad Mini Mk3 not found" error

**Solutions:**
1. Check USB connection is secure
2. Verify the device appears in your system:
   ```bash
   # macOS/Linux
   python -c "import mido; print(mido.get_input_names())"
   ```
3. Look for ports containing "LPMiniMK3" or "MIDIIN2"
4. Try unplugging and reconnecting the device

### Wrong Port Selected

**Symptom:** No MIDI messages received

**Solution:** Ensure you're using the **MIDI In/Out** port, not the DAW port:
- ✅ Correct: `LPMiniMK3 MIDI In/Out`
- ❌ Wrong: `LPMiniMK3 DAW In/Out`

### LEDs Not Responding

**Symptom:** Pads don't light up when sending MIDI

**Checklist:**
1. Verify Programmer Mode is active (hold Session → orange button)
2. Check you're sending to the MIDI Out port
3. Verify velocity/value is in range 0-127
4. Test with a simple command:
   ```python
   output.send(mido.Message('note_on', note=11, velocity=5))  # Red corner
   ```

### Pads Still Lit After Program Exit

**Symptom:** LEDs remain on after closing your application

**Solution:** Always clear LEDs before exiting:

```python
# Turn off all grid pads
for row in range(8):
    for col in range(8):
        note = (row + 1) * 10 + (col + 1)
        output.send(mido.Message('note_on', note=note, velocity=0))
```

Or use the `clear_all_leds()` method in `LaunchpadDevice`.

---

## 8. Advanced Features

### 8.1 Pulse/Flash Modes

Colors 64-127 enable LED pulse effects:

```python
# Static red
output.send(mido.Message('note_on', note=11, velocity=5))

# Pulsing red (velocity 5 + 64 = 69)
output.send(mido.Message('note_on', note=11, velocity=69))
```

### 8.2 RGB LED Control (Advanced)

For precise RGB control, use SysEx RGB commands:

```
F0 00 20 29 02 0D 03 03 [pad] [R] [G] [B] F7
```

- `[pad]` - Pad number (0-99 in grid notation)
- `[R]` `[G]` `[B]` - RGB values (0-127 each)

**Example (Python):**
```python
# Set pad 34 to custom RGB
pad = 34
r, g, b = 127, 64, 0  # Orange-ish
sysex = [0x00, 0x20, 0x29, 0x02, 0x0D, 0x03, 0x03, pad, r, g, b]
output.send(mido.Message('sysex', data=sysex))
```

---

## 9. Quick Reference

### Essential SysEx Commands

| Command | Bytes | Description |
|---------|-------|-------------|
| Enter Programmer Mode | `F0 00 20 29 02 0D 0E 01 F7` | Switch to Programmer Mode |
| Exit Programmer Mode | `F0 00 20 29 02 0D 0E 00 F7` | Return to Live Mode |
| Clear All LEDs | `F0 00 20 29 02 0D 0E 00 F7` | Turn off all LEDs |

### Grid Note Formulas

```python
# Grid pad (8x8)
note = (row + 1) * 10 + (col + 1)

# Top row CC
cc = 91 + col

# Right column note
note = (row + 1) * 10 + 9

# Reverse: Note to (col, row)
row = (note // 10) - 1
col = (note % 10) - 1
```

### Common Colors

```python
LP_OFF = 0
LP_RED = 5
LP_ORANGE = 9
LP_YELLOW = 13
LP_GREEN = 21
LP_CYAN = 37
LP_BLUE = 45
LP_PURPLE = 53
LP_PINK = 57
LP_WHITE = 3
```

---

## 10. Resources

- **Official Manual:** [Launchpad Mini MK3 Programmer's Reference](https://novationmusic.com/en/launch/launchpad-mini)
- **Python Implementation:** `python-vj/launchpad_synesthesia_control/app/io/midi_launchpad.py`
- **Example App:** `python-vj/launchpad_synesthesia_control/`
- **MIDI Library:** [mido documentation](https://mido.readthedocs.io/)

---

## 11. See Also

- [Launchpad Synesthesia Control README](launchpad_synesthesia_control/README.md) - Full app documentation
- [MIDI Controller Setup Guide](../docs/setup/midi-controller-setup.md) - General MIDI setup
- [Processing Launchpad Integration](../docs/reference/processing-guides/06-interactivity.md) - Using Launchpad with Processing

---

**Last Updated:** December 2024  
**Specification Version:** Launchpad Mini MK3 Programmer's Reference Manual v1.0

# lpminimk3 Library Integration - Migration Guide

## Overview

The `launchpad_osc_lib` now uses the [lpminimk3](https://github.com/obeezzy/lpminimk3) library for all Launchpad Mini MK3 hardware interaction. This reduces code complexity and provides access to a well-maintained, feature-rich library.

## What Changed

### Core API Changes

| Old API | New API |
|---------|---------|
| `from launchpad_osc_lib import PadId` | `from launchpad_osc_lib import ButtonId` |
| `from launchpad_osc_lib import LaunchpadDevice` | `from lpminimk3 import LaunchpadMiniMk3` |
| `find_launchpad_ports()` | `lpminimk3.find_launchpads()` |
| `LaunchpadDevice.connect()` (async) | `lp.open()` (sync) |
| `device.set_led(pad, color)` | `button.led.color = color_shade` |

### ButtonId Replaces PadId

The new `ButtonId` is simpler (just x, y coordinates) and matches lpminimk3's button coordinate system:

```python
# Old
from launchpad_osc_lib import PadId
pad = PadId(3, 4)

# New  
from launchpad_osc_lib import ButtonId
btn = ButtonId(3, 4)

# Both support the same helper methods
btn.is_grid()        # True for 8x8 grid
btn.is_top_row()     # True for top row buttons (y=-1)
btn.is_right_column() # True for scene buttons (x=8)
```

### Color System

**Old way** - Limited color constants:
```python
from launchpad_osc_lib import LP_RED, LP_GREEN, LP_BLUE
device.set_led(pad, LP_RED)
```

**New way** - Rich color palette with 9 shades per color:
```python
from lpminimk3.colors import ColorPalette

# Direct LED control
button.led.color = ColorPalette.Red.SHADE_5
button.led.color = ColorPalette.Green.SHADE_1  # Dim green
button.led.color = ColorPalette.Blue.SHADE_9   # Bright blue

# Or use numeric values (0-127)
button.led.color = 72  # Red
button.led.color = 0   # Off
```

Available colors: Red, Orange, Yellow, Green, Blue, Violet, White (each with SHADE_1 through SHADE_9)

### Device Connection

**Old way** - Async connection:
```python
from launchpad_osc_lib import LaunchpadDevice, LaunchpadConfig

config = LaunchpadConfig(auto_detect=True)
device = LaunchpadDevice(config)
await device.connect()
await device.start_listening()
```

**New way** - Direct sync connection:
```python
import lpminimk3

# Find device
lp = lpminimk3.find_launchpads()[0]

# Open and set mode
lp.open()
lp.mode = lpminimk3.Mode.PROG

# Poll for events
while True:
    event = lp.panel.buttons().poll_for_event()
    if event and event.type == lpminimk3.ButtonEvent.PRESS:
        print(f"Button {event.button.x}, {event.button.y} pressed")
        event.button.led.color = lpminimk3.colors.ColorPalette.Red.SHADE_5
```

### LED Modes

**Old way**:
```python
device.set_led(pad, color, LedMode.PULSE)
device.set_led_flash(pad, color1, color2)
```

**New way**:
```python
button.led.color = ColorPalette.Red.SHADE_5  # Static
button.led.color.mode = lpminimk3.Led.PULSE  # Pulsing
button.led.color.mode = lpminimk3.Led.FLASH  # Flashing
```

## Migration Checklist

- [ ] Replace `PadId` with `ButtonId` throughout your code
- [ ] Replace `LaunchpadDevice` with `lpminimk3.LaunchpadMiniMk3`
- [ ] Update device connection code from async to sync API
- [ ] Replace color constants with `ColorPalette` shades
- [ ] Update LED control to use `button.led.color` directly
- [ ] Remove async/await from launchpad code
- [ ] Update event handling to use `poll_for_event()`
- [ ] Run tests to verify everything works

## Benefits

1. **Less code**: Removed ~500 lines of custom MIDI handling
2. **Better maintained**: Active library with proper documentation
3. **More features**: Text scrolling, graphics rendering, etc.
4. **Cleaner API**: Direct button access with intuitive properties
5. **Richer colors**: 9 shades per color vs limited constants

## Resources

- [lpminimk3 Documentation](https://github.com/obeezzy/lpminimk3)
- [lpminimk3 Examples](https://github.com/obeezzy/lpminimk3/tree/main/lpminimk3/examples)
- [API Reference](https://lpminimk3.readthedocs.io/)

## Support

If you encounter issues after migration:
1. Check that `lpminimk3>=0.6.4` is installed
2. Verify your Launchpad is in Programmer mode
3. Review the examples in lpminimk3 library
4. Check existing tests in `launchpad_osc_lib/tests/`

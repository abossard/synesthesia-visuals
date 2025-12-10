# Making `launchpad_osc_lib` Generic for Multiple MIDI Devices

## Current State Analysis

| File | Launchpad-Specific | Already Generic |
|------|-------------------|-----------------|
| launchpad.py | **100%** — entire file | — |
| model.py | ~25% — PadId, colors, brightness | PadMode, OscCommand, effects, FSM states |
| fsm.py | ~5% — hardcoded color imports | Pure functions, mode logic, learn FSM |
| engine.py | ~10% — LED calls | Pad mapping, group management |
| banks.py | ~15% — grid size, top row | Multi-bank logic, persistence |
| osc_client.py | **0%** | Completely generic |
| synesthesia_osc.py | **0%** | Completely generic |

---

## Proposed Architecture

```
launchpad_osc_lib/  →  midi_osc_lib/
├── controllers/
│   ├── base.py           # Protocol + ColorPalette + Layout
│   ├── launchpad_mk3.py  # Launchpad Mini MK3 implementation
│   ├── midimix.py        # Akai MIDImix implementation
│   └── registry.py       # Auto-detection factory
├── model.py              # Generic: PadIdentifier protocol, effects, states
├── fsm.py                # Generic: no device imports, colors from palette
├── engine.py             # Generic: accepts any MidiController
├── banks.py              # Generic: configurable grid size
├── osc_client.py         # Already generic
└── synesthesia_osc.py    # Already generic
```

---

## Key Abstractions

### 1. Controller Protocol
```python
class MidiController(Protocol):
    layout: ControllerLayout
    colors: ColorPalette
    
    async def connect(self) -> bool
    def set_pad_callback(self, cb: Callable[[PadIdentifier, int], None])
    def set_led(self, pad_id: PadIdentifier, color: int)
    def clear_all_leds(self)
```

### 2. Generic Pad Identifier
```python
@dataclass(frozen=True)
class PadIdentifier:
    device: str        # "launchpad", "midimix"
    index: int         # Unique within device
    x: int = -1        # Optional grid coords
    y: int = -1
    
    def __str__(self) -> str:
        return f"{self.device}:{self.index}"
```

### 3. Controller Layout
```python
@dataclass
class ControllerLayout:
    device_name: str
    grid_rows: int           # 8 for Launchpad, 2 for MIDImix buttons
    grid_cols: int           # 8 for Launchpad, 8 for MIDImix
    has_velocity: bool       # True for LP (127 levels), False for MIDImix (on/off)
    supports_rgb: bool       # True for LP, False for MIDImix
    bank_button_count: int   # How many bank switch buttons
```

### 4. Color Palette (per-device)
```python
@dataclass
class ColorPalette:
    off: int
    on: int                  # For simple on/off devices like MIDImix
    colors: Dict[str, tuple] # For RGB devices: name → (dim, normal, bright)
    
    def get(self, name: str, brightness: float = 1.0) -> int
```

---

## Refactoring Steps

1. **Extract device-specific code** — Move `launchpad.py` to `controllers/launchpad_mk3.py`

2. **Create base protocol** — `controllers/base.py` with `MidiController`, `ControllerLayout`, `ColorPalette`

3. **Generalize PadId** — Replace with `PadIdentifier` that has device field

4. **Inject colors** — FSM/engine receive color palette, don't import constants

5. **Config key format** — Change from `"x,y"` to `"device:index"` or `"device:x,y"`

6. **Add MIDImix adapter** — `controllers/midimix.py` implementing same protocol

---

## MIDImix Device Specifics

### Hardware Capabilities
- **16 buttons** with LED feedback (Mute row + Solo/Rec Arm row)
- **LEDs**: Single color, on/off only (no RGB)
- **MIDI**: Buttons send Note On/Off (configurable in MIDImix Editor)
- **Faders/Knobs**: 9 faders + 24 knobs send CC (continuous values)

### Button-to-Note Mapping (default)
| Row | Function | Notes |
|-----|----------|-------|
| Mute | 8 buttons | Notes 1-8 (configurable) |
| Solo/Rec Arm | 8 buttons | Notes 9-16 (configurable) |

### LED Control
- Send Note On with velocity > 0 → LED on
- Send Note On with velocity 0 → LED off

---

## Design Decisions to Make

### 1. Scope
- [ ] **Option A**: Buttons only (16 MIDImix buttons as additional pads)
- [ ] **Option B**: Full support including faders/knobs for continuous OSC params

### 2. Library Rename
- [ ] Keep `launchpad_osc_lib` (just generalize internals)
- [ ] Rename to `midi_osc_lib` or `vj_controller_lib`

### 3. Config Migration
- [ ] Auto-migrate existing `"x,y"` configs on load
- [ ] Support both formats temporarily
- [ ] Breaking change, require manual migration

### 4. Learn Mode UX
- [ ] Launchpad-only visual feedback (MIDImix has no blinking)
- [ ] Show "press any button on any device" message
- [ ] First button pressed on any device wins

---

## Further Considerations

### LED Mode Differences
- **Launchpad**: STATIC, PULSE, FLASH via MIDI channels
- **MIDImix**: just on/off
- **Solution**: `LedMode` enum per controller, `set_led()` ignores mode on simple devices

### Button vs Fader
- **Launchpad**: all buttons (note on/off)
- **MIDImix**: buttons (note) + faders (CC continuous)
- **Solution**: Separate `button_callback` and `cc_callback`, FSM only handles buttons initially

### Multi-Device Orchestration
- Both devices connect in parallel
- Single FSM instance receives events from both
- Effects tagged with device for LED routing

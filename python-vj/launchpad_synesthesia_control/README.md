# Launchpad Synesthesia Control

A bi-directional controller bridge between Launchpad Mini Mk3 and Synesthesia Pro with beat-synced LED feedback and easy Learn Mode.

## Features

- 🎛️ **8x8 Grid Control**: Full Launchpad grid + top row + right column (82 buttons)
- 🎨 **LED Feedback**: Active pads blink in sync with Synesthesia's beat
- 🎓 **Learn Mode**: 5-second OSC recording for easy pad mapping
- 🔄 **Bi-directional Sync**: Launchpad → Synesthesia → Launchpad state sync
- 📊 **Terminal UI**: Beautiful Textual-based dashboard
- 🛡️ **Graceful Degradation**: Works without hardware, auto-reconnects
- ⚡ **Low Latency**: Async I/O throughout, 20 FPS LED updates
- 🎯 **Functional Core**: Type-safe, testable, pure functions

## Quick Start

### Installation

```bash
cd python-vj
pip install -r requirements.txt
```

### Run Standalone

```bash
python -m launchpad_synesthesia_control
```

### First-Time Setup

1. **Launchpad**: Put in Programmer mode (hold Session → press orange → release)
2. **Synesthesia**: Configure OSC
   - Output Port: 9001 (sends to our app)
   - Input Port: 9000 (receives from our app)
3. **Learn Your First Pad**:
   - Press `L` to enter Learn Mode
   - Press any Launchpad pad
   - Click a scene/preset in Synesthesia
   - Wait 5 seconds
   - Select the OSC command (WIP - manual config for now)

## Usage

### Key Bindings

- `L` - Enter Learn Mode
- `ESC` - Cancel Learn Mode
- `Q` - Quit
- `TAB` - Cycle focus between panels

### UI Panels

```
┌─────────────────────────┬──────────────┬──────────────┐
│                         │ Connection   │              │
│   Launchpad Grid        │ Status       │              │
│   (8x8 + top + right)   ├──────────────┤              │
│                         │              │              │
│   ● = Active/On         │ Learn Mode   │              │
│   ○ = Inactive/Off      │ Panel        │              │
│   · = Unmapped          │              │              │
├─────────────────────────┼──────────────┴──────────────┤
│                         │                             │
│ OSC Configuration       │  Event Log                  │
│                         │                             │
└─────────────────────────┴─────────────────────────────┘
```

### Pad Modes

**SELECTOR (Radio Buttons)**
- Only one active per group (scenes, presets, colors, banks)
- Active pad blinks with beat
- Example: Scene selection pads

**TOGGLE (On/Off Switch)**
- Press to toggle between two states
- No blinking
- Example: Strobe effect, filters

**ONE-SHOT (Momentary)**
- Triggers action on press
- No persistent state
- Example: Next/previous buttons, bangs

## Configuration

Config file: `~/.config/launchpad-synesthesia/config.yaml`

### Example Configuration

```yaml
version: "1.0"
pads:
  "0,0":  # Bottom-left pad
    mode: SELECTOR
    group: scenes
    idle_color: 0    # Off
    active_color: 5  # Red
    label: "Alien Cavern"
    osc_action:
      address: "/scenes/AlienCavern"
      args: []
  
  "1,0":
    mode: TOGGLE
    idle_color: 0
    active_color: 21  # Green
    label: "Strobe"
    osc_on:
      address: "/controls/global/strobe"
      args: [1]
    osc_off:
      address: "/controls/global/strobe"
      args: [0]
  
  "7,-1":  # Top-right button
    mode: ONE_SHOT
    active_color: 45  # Blue
    label: "Next Scene"
    osc_action:
      address: "/playlist/next"
      args: []
```

### Color Palette

```python
0  = Off           17 = Green Dim
1  = Red Dim       21 = Green
3  = White         37 = Cyan
5  = Red           41 = Blue Dim
9  = Orange        45 = Blue
13 = Yellow        53 = Purple
                   57 = Pink
```

## OSC Messages

### Controllable (Can be mapped)

```
/scenes/{name}                 - Activate scene
/presets/{name}                - Activate preset
/favslots/{0-7}                - Favorite slots
/playlist/next                 - Next scene
/playlist/previous             - Previous scene
/controls/meta/hue {0.0-1.0}   - Master hue
/controls/meta/saturation
/controls/meta/brightness
/controls/global/{param} {val} - Global controls
```

### State Sync (Received only)

```
/audio/beat/onbeat {0|1}       - Beat pulse for LED sync
/audio/bpm {float}             - Current BPM
/audio/level {float}           - Audio level
```

## Learn Mode Workflow

1. **Press `L`** → Enter learn mode
2. **Press a pad** → Selected for configuration
3. **Trigger in Synesthesia** → Click scene/preset/control
4. **Timer starts** → On first controllable OSC message
5. **Wait 5 seconds** → Recording captures all OSC
6. **Select command** → Choose from filtered candidates
7. **Configure pad** → Type (selector/toggle/one-shot), group, colors
8. **Save** → Config persisted to YAML

## Advanced Usage

### Manual Config Editing

Edit `~/.config/launchpad-synesthesia/config.yaml` directly for bulk changes.

### Troubleshooting

**Launchpad not detected**:
- Ensure it's in Programmer mode
- Linux: Check user in `audio` group

**OSC not connecting**:
- Check Synesthesia OSC settings match (9000 in, 9001 out)
- Firewall blocking localhost UDP?

**Pads not responding**:
- Check Event Log for OSC messages
- Verify OSC address matches Synesthesia exactly
- Check connection status panel

### Running Tests

```bash
cd python-vj
python -m pytest launchpad_synesthesia_control/tests/
```

### Type Checking

```bash
mypy launchpad_synesthesia_control/
```

## Architecture

### Functional Core / Imperative Shell

**Pure Functions** (`app/domain/`):
- `model.py` - Immutable dataclasses
- `fsm.py` - State transitions (handle_pad_press, handle_osc_event)
- `blink.py` - Beat sync calculations

**Imperative Shell** (`app/io/`, `app/ui/`):
- `midi_launchpad.py` - MIDI I/O
- `osc_synesthesia.py` - OSC I/O
- `config.py` - File I/O
- `tui.py` - UI rendering

Benefits: Easy testing, no side effects in logic, clear boundaries

## VJ Console Integration (Coming Soon)

Will be integrated as Screen #8 in the main VJ Console:

```bash
python vj_console.py
# Press 8 to access Launchpad config
```

## Contributing

See `LLMS.txt` for AI assistant guidelines on editing mappings and extending functionality.

## License

See main repository LICENSE

## Credits

Part of the [Synesthesia Visuals](https://github.com/abossard/synesthesia-visuals) project.

## Multi-Bank Support

### Overview

Organize your Launchpad into **multiple banks** for different control layouts. Switch between banks on the fly during performances.

### Default Banks

- **Bank 0 (Default)**: General-purpose controls
- **Bank 1 (Scenes)**: Scene selection pads
- **Bank 2 (Effects)**: Effect toggles and triggers
- **Bank 3 (Colors)**: Color/hue controls

### Switching Banks

Click the bank buttons (B0, B1, B2, B3) in the Bank Selector panel. The active bank is highlighted in green and shown in the Status panel.

### Bank-Specific Configurations

Currently, pad mappings are shared across banks. For per-bank configurations, extend your YAML:

```yaml
active_bank_index: 1
active_bank_name: "Scenes"
banks:
  0:
    name: "Default"
    pads: { ... }
  1:
    name: "Scenes"
    pads: { ... }
```

### Learn Mode Without Hardware

**New Feature**: Configure pads entirely from the TUI!

1. Press `L` for Learn Mode
2. **Click a pad in the TUI grid** (no Launchpad needed)
3. Trigger action in Synesthesia
4. Wait 5 seconds for OSC recording
5. Configure pad type, group, colors

The TUI grid is fully interactive - you can map all 82 pads without connecting hardware.

### Programmer Mode Setup

If you have a physical Launchpad, put it in Programmer mode:

1. Hold **Session** button
2. Press the **orange pad** (top-right)
3. Release both buttons

The Status panel shows these instructions when Launchpad is not detected.

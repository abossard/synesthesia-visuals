# Launchpad Synesthesia Control

A bi-directional controller bridge between Novation Launchpad Mini Mk3 and Synesthesia Pro VJ software with beat-synced LED feedback, colorful terminal UI, and intuitive Learn Mode.

## Features

- **Colorful Terminal UI**: Rich terminal colors representing actual Launchpad LED colors
- **8x8 Grid Control**: Full Launchpad grid + top row + right column (82 buttons)
- **LED Feedback**: Active pads blink in sync with Synesthesia's beat
- **Learn Mode**: 5-second OSC recording for easy pad mapping
- **Bi-directional Sync**: Launchpad → Synesthesia → Launchpad state sync
- **Graceful Degradation**: Works without hardware using virtual grid
- **Auto-Reconnect**: Automatically reconnects when devices become available
- **Low Latency**: Async I/O throughout, 20 FPS LED updates
- **Comprehensive Tests**: 118 unit tests covering all domain logic

## Terminal UI Screenshot

```
╔═══ LAUNCHPAD MINI MK3 ════════════════════╗
│ · │ · │ · │ · │ · │ · │ · │ · │    │  <- Top Row
├────────────────────────────────────────────┤
│ ● │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │  <- Grid with colors
│ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │
│ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │
│ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │
│ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │
│ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │
│ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │
│ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │ ○ │
╚══════════════════════════════════════════╝

╔════ STATUS ═════════════════╗    ╔════ HELP ═══════════════════╗
│ Launchpad: ● CONNECTED      │    │ Keyboard Shortcuts:         │
│ OSC:       ● CONNECTED      │    │  L   Enter Learn Mode       │
│                             │    │  Q   Quit Application       │
│ Mode:  ● NORMAL             │    │  Esc Cancel / Exit          │
│ Beat:  ♫                    │    │                             │
│                             │    │ Mouse:                      │
│ Scene:  AlienCavern         │    │  Click pads to activate     │
│ Preset: None                │    │                             │
│                             │    │ Status:                     │
│ Mapped Pads: 15/82          │    │  ● Active selector          │
╚═════════════════════════════╝    │  ◉ Toggle ON                │
                                   │  ○ Inactive/OFF             │
                                   ╚═════════════════════════════╝
```

## Quick Start

> **📖 For detailed Programmer Mode documentation, see [Launchpad Programming Mode Guide](../LAUNCHPAD_PROGRAMMING_MODE.md)**

### Installation

```bash
cd python-vj/launchpad_synesthesia_control
pip install textual mido python-rtmidi python-osc pyyaml
```

### Run

```bash
python -m launchpad_synesthesia_control
```

### First-Time Setup

1. **Launchpad**: Put in Programmer mode (hold Session → press orange → release)
2. **Synesthesia**: Configure OSC
   - Output Port: 8000 (sends state to our app)
   - Input Port: 9000 (receives commands from our app)
3. **Learn Your First Pad**:
   - Press `L` to enter Learn Mode
   - Click any pad on the grid (or press on hardware)
   - Click a scene/preset in Synesthesia
   - Wait for 5-second recording to complete
   - Press 1-9 to select the OSC command

## Usage

### Key Bindings

| Key | Action |
|-----|--------|
| `L` | Enter Learn Mode |
| `Esc` | Cancel Learn Mode |
| `Q` | Quit Application |
| `1-9` | Select OSC command (in Learn Mode) |

### Pad Visual Indicators

| Symbol | Meaning |
|--------|---------|
| `●` | Active selector (blinking with beat) |
| `◉` | Toggle ON |
| `○` | Inactive/Off (mapped) |
| `·` | Unmapped pad |
| `▶` | Selected pad (Learn Mode) |

### Color Mapping

The terminal UI shows actual Launchpad colors:

| Velocity | Color | Terminal |
|----------|-------|----------|
| 0 | Off | Dark gray |
| 5 | Red | #ff0000 |
| 9 | Orange | #ff6600 |
| 13 | Yellow | #ffff00 |
| 21 | Green | #00ff00 |
| 37 | Cyan | #00ffff |
| 45 | Blue | #0066ff |
| 53 | Purple | #9900ff |
| 57 | Pink | #ff00ff |
| 3 | White | #ffffff |

## Pad Modes

### SELECTOR (Radio Buttons)
- Only one active per group (scenes, presets, colors)
- Active pad blinks with beat
- Perfect for: Scene selection, preset banks

### TOGGLE (On/Off Switch)
- Press to toggle between on/off states
- Sends different OSC for each state
- Perfect for: Strobe, filters, effects

### ONE-SHOT (Momentary)
- Triggers action on press, no persistent state
- Perfect for: Next/previous, triggers, bangs

## Configuration

Config file: `~/.config/launchpad-synesthesia/config.yaml`

### Example Configuration

```yaml
version: "1.0"
pads:
  "0,0":
    mode: SELECTOR
    group: scenes
    idle_color: 0
    active_color: 21  # Green
    label: "Alien Cavern"
    osc_action:
      address: "/scenes/AlienCavern"
      args: []

  "1,0":
    mode: TOGGLE
    idle_color: 0
    active_color: 5  # Red
    label: "Strobe"
    osc_on:
      address: "/controls/global/strobe"
      args: [1]
    osc_off:
      address: "/controls/global/strobe"
      args: [0]

  "7,-1":
    mode: ONE_SHOT
    active_color: 45  # Blue
    label: "Next Scene"
    osc_action:
      address: "/playlist/next"
      args: []
```

## Learn Mode Workflow

```
┌─────────────────────────────────────────────────────────────┐
│  NORMAL                                                      │
│    │                                                         │
│    │ Press L                                                 │
│    ▼                                                         │
│  LEARN_WAIT_PAD  ─────────────────────────────────────────┐ │
│    │                                                       │ │
│    │ Click/press a pad                                     │ │
│    ▼                                                       │ │
│  LEARN_RECORD_OSC                                          │ │
│    │                                                       │ │
│    │ 5 seconds recording                                   │ │
│    │ (starts on first OSC)                                 │ │
│    ▼                                                       │ │
│  LEARN_SELECT_MSG                                          │ │
│    │                                                       │ │
│    │ Press 1-9 to select command                           │ │
│    ▼                                                       │ │
│  NORMAL (config saved!)                                    │ │
│                                               ┌────────────┘ │
│                              Press Esc ──────▶│              │
└─────────────────────────────────────────────────────────────┘
```

## OSC Messages

### Controllable (Can be mapped to pads)

```
/scenes/{name}               - Activate scene
/presets/{name}              - Activate preset
/favslots/{0-7}              - Favorite slots
/playlist/next               - Next scene
/playlist/previous           - Previous scene
/controls/meta/hue           - Master hue (0.0-1.0)
/controls/meta/saturation    - Master saturation
/controls/meta/brightness    - Master brightness
/controls/global/{param}     - Global controls
```

### State Sync (Received from Synesthesia)

```
/audio/beat/onbeat {0|1}     - Beat pulse for LED sync
/audio/bpm {float}           - Current BPM
/audio/level {float}         - Audio level
```

## Testing

### Run All Tests

```bash
cd python-vj/launchpad_synesthesia_control
pip install pytest pytest-asyncio
python -m pytest tests/ -v
```

### Test Coverage

| Module | Tests | Description |
|--------|-------|-------------|
| `test_model.py` | 36 | Data structures, immutability |
| `test_fsm.py` | 27 | State machine transitions |
| `test_blink.py` | 22 | Beat sync logic |
| `test_config.py` | 22 | YAML persistence |
| `test_tui.py` | 11 | UI components (requires textual.testing) |

### Test Architecture

Tests use pytest with:
- **Fixtures** for common state setups
- **Parametrized tests** for boundary conditions
- **Pure function testing** - no mocks needed for domain logic
- **Injectable time function** for timer testing

## Architecture

### Functional Core / Imperative Shell

```
┌────────────────────────────────────────────────────────────┐
│                      Imperative Shell                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ tui.py      │  │ midi_       │  │ osc_synesthesia.py  │ │
│  │ (UI)        │  │ launchpad.py│  │ (OSC I/O)           │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
│         │                │                     │            │
│         └────────────────┼─────────────────────┘            │
│                          │                                  │
│                   Effects│& Events                          │
│                          │                                  │
│  ┌───────────────────────┼────────────────────────────────┐ │
│  │                Functional Core                         │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐             │ │
│  │  │ model.py │  │ fsm.py   │  │ blink.py │             │ │
│  │  │ (Data)   │  │ (Logic)  │  │ (Calc)   │             │ │
│  │  └──────────┘  └──────────┘  └──────────┘             │ │
│  │                                                        │ │
│  │  - Immutable dataclasses                              │ │
│  │  - Pure functions: (state, event) → (state, effects)  │ │
│  │  - No I/O, no side effects                            │ │
│  └────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

**Benefits:**
- Domain logic is fully testable without mocks
- Clear separation of concerns
- Effects are data, executed by shell
- Easy to reason about state transitions

## Troubleshooting

### Launchpad not detected
- Ensure it's in Programmer mode (hold Session → press orange → release)
- Linux: Check user is in `audio` group (`sudo usermod -aG audio $USER`)
- Check USB connection

### OSC not connecting
- Verify Synesthesia OSC ports: Send 8000, Receive 9000
- Check firewall isn't blocking localhost UDP
- Look for "OSC connected" in status panel

### Pads not responding
- Check Event Log panel for incoming OSC
- Verify OSC address matches exactly
- Ensure pad is mapped (not showing `·`)

### Colors not showing
- Requires terminal with true color support
- Try: `export COLORTERM=truecolor`
- Works best in modern terminals (iTerm2, Windows Terminal, etc.)

## Contributing

1. Run tests before submitting: `python -m pytest tests/ -v`
2. Follow functional core pattern for domain logic
3. Keep UI code in imperative shell
4. See `LLMS.txt` for AI assistant guidelines

## License

See main repository LICENSE

## Credits

Part of the [Synesthesia Visuals](https://github.com/abossard/synesthesia-visuals) project.

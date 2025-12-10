# Launchpad Standalone

**Device-driven learn mode without TUI** - configure your Launchpad pads using only the Launchpad itself.

## Features

- 🎹 **Full Launchpad control** - no computer screen needed during configuration
- 🎨 **Color preview** - see colors directly on the pads while selecting
- ⚡ **Smart OSC recording** - auto-detects scenes/presets and stops immediately
- 💾 **Persistent config** - saves to `~/.config/launchpad_standalone/config.yaml`

## Quick Start

```bash
cd python-vj
python -m launchpad_standalone
```

## Learn Mode Workflow

### 1. Enter Learn Mode
Press the **bottom-right scene button** (note 19) - all pads will blink red.

### 2. Select a Pad
Press any pad on the 8x8 grid - that pad will blink orange while recording.

### 3. Trigger an OSC Event
In Synesthesia (or your OSC source), trigger the control you want to map:
- **Scene selection** → Stops recording immediately
- **Preset selection** → Stops recording immediately
- **Control change** → Stops recording immediately
- Other events → Records for 5 seconds

### 4. Configure the Mapping
After recording, you enter the config phase:

**Top Row (Register Selection):**
- Pad 0: OSC command selection
- Pad 1: Mode selection (Toggle/Push/One-shot/Selector)
- Pad 2: Color selection

**Content Area (varies by register):**
- OSC Select: 8 commands shown, pagination with top-right pads
- Mode Select: 4 mode options (Toggle, Push, One-shot, Selector)
- Color Select: 4x4 idle colors (left) + 4x4 active colors (right)

**Bottom Row (Actions):**
- Pad 0 (Green): Save
- Pad 1 (Blue): Test (sends selected OSC)
- Pad 7 (Red): Cancel

## Launchpad Layout

```
┌─────────────────────────────────┬─────┐
│ [REG1] [REG2] [REG3] ... [◄] [►]│ [X] │  ← Top row (y=7)
├─────────────────────────────────┤     │
│                                 │     │
│         Content Area            │ Scene
│        (varies by register)     │ Buttons
│                                 │     │
├─────────────────────────────────┤     │
│ [SAVE] [TEST] ... ... [CANCEL]  │[LRN]│  ← Bottom row (y=0)
└─────────────────────────────────┴─────┘
```

## Color Preview

When in Color Selection register, the grid shows:

```
Row 7: [OSC] [Mode] [Color] [ ] [ ] [ ] [◄] [►]  ← Register tabs
Row 6: [ ] [IDLE] [ ] [ ]    [ ] [ACT] [ ] [ ]   ← Preview of selected colors
Row 5: [D] [N] [B] [ ]       [ ] [D] [N] [B]     ← Brightness level indicator (DIM/NORMAL/BRIGHT)
Row 4: [Pk][Wh][ ] [ ]       [ ] [ ] [Pk][Wh]    ← Extra colors (pink, white)
Row 3: [Cy][Bl][Pu][ ]       [ ] [Cy][Bl][Pu]    ← Colors row 2
Row 2: [Rd][Or][Yw][Li][Gr]  [Rd][Or][Yw][Li]    ← Colors row 1 (10 base colors each side)
Row 1: [▼] [▲] [ ] [ ]       [ ] [ ] [▼] [▲]     ← Brightness ▼/▲ buttons
Row 0: [SAVE] [TEST] ...     ... [CANCEL]        ← Action buttons
       └─── Idle side ───┘   └─── Active side ──┘
```

### Color Selection Features

- **10 Base Colors**: Red, Orange, Yellow, Lime, Green, Cyan, Blue, Purple, Pink, White
- **3 Brightness Levels**: DIM (33%), NORMAL (66%), BRIGHT (100%)
- **Independent Brightness**: Idle and Active colors have separate brightness controls

### Brightness Controls (Row 1)

| Position | Function |
|----------|----------|
| Col 0 (▼) | Decrease idle brightness |
| Col 1 (▲) | Increase idle brightness |
| Col 6 (▼) | Decrease active brightness |
| Col 7 (▲) | Increase active brightness |

- Brightness buttons show **bright blue** when adjustment is available
- Buttons show **dim blue** when at limit (can't go lower/higher)

### Brightness Level Indicator (Row 5)

- Three pads per side showing current brightness level
- **Green** = current level, **Dim green** = other levels
- Click any level pad to jump directly to that brightness

### Default Brightness

- **Idle**: NORMAL (66%) - visible but not distracting
- **Active**: BRIGHT (100%) - stands out when triggered

## OSC Smart Detection

The app categorizes incoming OSC by type:

| Priority | Type | Example | Behavior |
|----------|------|---------|----------|
| 1 | Scene | `/scenes/AlienCavern` | Stop immediately, suggest SELECTOR |
| 2 | Preset | `/presets/Preset1` | Stop immediately, suggest SELECTOR |
| 3 | Control | `/controls/global/mirror` | Stop immediately, suggest TOGGLE |
| 99 | Audio | `/audio/level` | Ignored (noise) |

## File Structure

```
launchpad_standalone/
├── __init__.py      # Package info
├── __main__.py      # Entry point
├── model.py         # Data structures (PadId, LearnState, etc.)
├── display.py       # LED rendering (state → LedEffect list)
├── fsm.py           # State machine (pure functions)
├── osc_categories.py # OSC address categorization
├── launchpad.py     # Launchpad MIDI driver
├── osc.py           # OSC client
├── config.py        # YAML persistence
└── app.py           # Main orchestrator
```

## Architecture

This app follows **Functional Core, Imperative Shell** design:

- **Pure functions** (`fsm.py`, `display.py`): State transitions, no I/O
- **Imperative shell** (`app.py`): I/O handling, effect execution

All state changes produce a list of **effects** that are executed by the shell:
- `LedEffect` → Set Launchpad LED
- `SendOscEffect` → Send OSC message
- `SaveConfigEffect` → Persist to YAML
- `LogEffect` → Console logging

## Dependencies

- `mido` + `python-rtmidi` - MIDI communication
- `python-osc` - OSC communication
- `pyyaml` - Config persistence

## Differences from launchpad_synesthesia_control

| Feature | Standalone | TUI App |
|---------|-----------|---------|
| UI | Launchpad LEDs only | Textual TUI |
| Config screen | On-device | Modal dialog |
| Complexity | Simple | Full-featured |
| Use case | Quick setup | Advanced config |

# MIDI Router

A Python MIDI router integrated into the VJ Console that sits between hardware controllers (Launchpad, MIDImix) and Magic Music Visuals, providing:
- **Toggle state management** with LED feedback
- **Absolute state synchronization** to Magic (prevents toggle ambiguity)
- **Learn mode** for easy MIDI mapping
- **Pass-through** for non-enhanced controls
- **Real-time debug view** of all MIDI traffic

## Why Use This?

Magic Music Visuals can receive MIDI but cannot:
1. Maintain logical toggle state (buttons are momentary only)
2. Send MIDI feedback back to controllers (no LED state)

This router solves both problems by acting as a **stateful middleware** that:
- Owns the authoritative toggle state for each button
- Keeps LEDs in sync with state
- Sends absolute on/off values to Magic (no ambiguity)
- Restores state on startup

## Quick Start

### 1. Create Virtual MIDI Port (macOS)

1. Open **Audio MIDI Setup** (in `/Applications/Utilities/`)
2. Go to **Window → Show MIDI Studio**
3. Double-click **IAC Driver**
4. Check **Device is online**
5. Add a port named `MagicBus`

### 2. Launch VJ Console

```bash
cd python-vj
pip install -r requirements.txt
python vj_console.py
```

### 3. Navigate to MIDI Router Screen

- Press `5` to switch to the MIDI Router screen
- The router initializes automatically with default config

### 4. Learn Your First Toggle

1. Press `l` to enter learn mode
2. The status will show "🎹 LEARN MODE ACTIVE"
3. Press a pad on your controller (e.g., Launchpad pad 40)
4. Router captures it and adds to config
5. Press the same pad again → LED lights up, Magic receives value 127
6. Press again → LED turns off, Magic receives value 0

### 5. Configure Magic

In Magic Music Visuals:
1. Create a Global parameter (e.g., "TwisterOn")
2. Right-click → MIDI Learn
3. Press the pad you learned (router sends MIDI via MagicBus)
4. Add a Range modifier: Input 0-127 → Output 0.0-1.0
5. Use Global to control effects/layers

## VJ Console MIDI Screen Layout

## VJ Console MIDI Screen Layout

```
┌─────────────────────────────────────────────────────────────┐
│ Left Column                │ Right Column                   │
├────────────────────────────┼────────────────────────────────┤
│ ═══ MIDI Router ═══        │ ═══ MIDI Toggles ═══           │
│ ● Router Running           │   Note  40: TwisterOn    ● ON  │
│ Controller: Launchpad →    │   Note  41: LyricsOn     ○ OFF │
│            MagicBus        │ ▸ Note  42: StrobeOn     ○ OFF │
│                            │   Note  43: GlitchOn     ● ON  │
│ Learn mode: inactive       │                                │
│                            │ ═══ MIDI Traffic ═══           │
│ ═══ Actions ═══            │ 14:23:45 → Note On  ch0 #42 val=127│
│ l     Enter learn mode     │ 14:23:45 → Note On  ch0 #42 val=127│
│ r     Rename selected      │ 14:23:44 ← Note On  ch0 #42 val=100│
│ d     Delete selected      │ 14:23:40 → Note On  ch0 #41 val=0  │
│ k/j   Navigate up/down     │ 14:23:40 → Note On  ch0 #41 val=0  │
│ space Toggle test          │ 14:23:39 ← Note On  ch0 #41 val=100│
│                            │                                │
│ ═══ Configuration ═══      │                                │
│ Controller: Launchpad      │                                │
│ Virtual Port: MagicBus     │                                │
│ Toggles: 4                 │                                │
│ Config: ~/.midi_router/... │                                │
└────────────────────────────┴────────────────────────────────┘
```

### Panel Descriptions

**MIDI Router (top left)**: Current router status and device info  
**Actions (middle left)**: Available keyboard shortcuts for MIDI management  
**Configuration (bottom left)**: Router configuration details  
**MIDI Toggles (top right)**: List of configured toggles with current state  
**MIDI Traffic (bottom right)**: Real-time log of MIDI messages (← incoming, → outgoing)

## Keyboard Controls (MIDI Screen)

| Key | Action |
|-----|--------|
| `l` | Enter learn mode (capture next pad press) |
| `k` / `↑` | Navigate up in toggle list |
| `j` / `↓` | Navigate down in toggle list |
| `space` | Test toggle selected item (simulates button press) |
| `r` | Rename selected toggle (shows instruction for now) |
| `d` | Delete selected toggle |
| `5` | Switch to MIDI screen |
| `q` | Quit VJ Console |

## Configuration Format

`~/.midi_router/config.json`:

```json
{
  "controller": {
    "name_pattern": "Launchpad",
    "input_port": null,
    "output_port": null
  },
  "virtual_output": {
    "name_pattern": "MagicBus",
    "input_port": null,
    "output_port": null
  },
  "toggles": {
    "40": {
      "name": "TwisterOn",
      "state": false,
      "message_type": "note",
      "led_on_velocity": 127,
      "led_off_velocity": 0,
      "output_on_velocity": 127,
      "output_off_velocity": 0
    },
    "41": {
      "name": "LyricsOn",
      "state": true,
      "message_type": "note",
      "led_on_velocity": 127,
      "led_off_velocity": 0,
      "output_on_velocity": 127,
      "output_off_velocity": 0
    }
  }
}
```

### Configuration Fields

**Device Config:**
- `name_pattern` - Substring to match device name (e.g., "Launchpad", "MIDImix")
- `input_port` - Optional explicit port name (leave null for auto-detect)
- `output_port` - Optional explicit port name (leave null for auto-detect)

**Toggle Config:**
- `name` - Human-readable name (for display/debugging)
- `state` - Current state (true = ON, false = OFF)
- `message_type` - "note" or "cc"
- `led_on_velocity` - Velocity to send for ON LED (0-127)
- `led_off_velocity` - Velocity to send for OFF LED (0-127)
- `output_on_velocity` - Velocity to send to Magic for ON (0-127)
- `output_off_velocity` - Velocity to send to Magic for OFF (0-127)

## How State Stays in Sync

### Python as Source of Truth

Python owns the toggle state. When you press a button:

1. Python flips state: `False → True` or `True → False`
2. Python sends LED feedback to controller (velocity = new state)
3. Python sends **absolute** state to Magic (velocity = new state)

Magic doesn't toggle internally - it just mirrors Python's state.

### On Startup

1. Python loads config (with last-known states)
2. Python sends one MIDI message per toggle to MagicBus
3. Magic updates its Globals to match Python's state
4. Controller LEDs update to match Python's state

Result: **No ambiguity**. Python, Magic, and controller LEDs all agree on state.

## Use Cases

### 1. Simple Feature Toggle

**Use Case:** Turn effect on/off (e.g., "Twister" shader layer)

**Setup:**
1. Learn pad 40 as "TwisterOn"
2. In Magic: Create Global "TwisterOn", MIDI learn to pad 40
3. Link Global to layer opacity or effect parameter

**Behavior:**
- Press pad → LED lights, Magic receives 127, effect turns on
- Press again → LED off, Magic receives 0, effect turns off
- Restart router → state restored, LED and Magic sync

### 2. Multiple Layers with Visual Feedback

**Use Case:** Control 8 layers with 8 pads

**Setup:**
1. Learn pads 11-18 as "Layer1" through "Layer8"
2. In Magic: Create 8 Globals, MIDI learn each to its pad
3. Use Globals to control layer visibility/opacity

**Behavior:**
- See at a glance which layers are on (LED state)
- Toggle any layer on/off with physical pad
- State persists across restarts

### 3. Scene Selection with Color Feedback

**Use Case:** Select between 4 scenes with different LED colors

**Advanced:** Edit config to set different `led_on_velocity` per scene:
- Scene 1 (pad 11): `led_on_velocity: 5` (red)
- Scene 2 (pad 12): `led_on_velocity: 21` (green)
- Scene 3 (pad 13): `led_on_velocity: 45` (blue)
- Scene 4 (pad 14): `led_on_velocity: 9` (amber)

**Behavior:**
- Press Scene 1 → Red LED, others turn off
- Magic receives: pad 11 = 127, all others = 0
- Use Globals to control which scene is visible

## OSC Broadcasting (VJ Bus Integration)

The MIDI router automatically broadcasts toggle state changes via OSC to integrate with the VJ bus architecture.

### OSC Addresses

**Toggle State Changes:**
```
/midi/toggle/{note}  [name, state]
```
- **note**: MIDI note number (e.g., 40)
- **name**: Toggle name string (e.g., "TwisterOn")
- **state**: Float 0.0 (OFF) or 1.0 (ON)

**Example:**
```
/midi/toggle/40  ["TwisterOn", 1.0]   # Toggle ON
/midi/toggle/40  ["TwisterOn", 0.0]   # Toggle OFF
```

**Learn Mode:**
```
/midi/learn  [note, name]
```
Sent when a new toggle is learned.

**Startup Sync:**
```
/midi/sync  [count]
```
Sent on router startup, followed by all toggle states.

### Use Cases

**1. Processing Sketches**
React to MIDI controller state in Processing:
```java
import oscP5.*;
OscP5 oscP5;

void setup() {
  oscP5 = new OscP5(this, 9000);
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/midi/toggle/40")) {
    String name = msg.get(0).stringValue();  // "TwisterOn"
    float state = msg.get(1).floatValue();   // 1.0 or 0.0
    
    if (state > 0.5) {
      // Trigger particle burst
    }
  }
}
```

**2. Synesthesia Shaders**
Use MIDI state to control shader parameters via OSC receiver.

**3. Audio Analyzer Coordination**
Log MIDI state changes alongside audio analysis for synchronized visuals.

**4. Multi-App Sync**
- Magic receives MIDI directly for immediate control
- Other VJ apps receive OSC for coordinated effects
- Single controller controls entire visual pipeline

### OSC Configuration

**Default:** OSC messages sent to `127.0.0.1:9000`

To change OSC target, edit `python-vj/osc_manager.py`:
```python
osc = OSCManager(host="192.168.1.100", port=9001)
```

## Pass-Through Mode

Any MIDI message that's **not** a configured toggle is forwarded unchanged:
- Faders → passed through
- Knobs → passed through
- Unconfigured pads → passed through
- Pitch bend, aftertouch, etc. → passed through

This allows mixing:
- Smart toggle pads with LED feedback
- Plain MIDI controls that work like direct MIDI

## CLI Commands

```bash
# List available MIDI devices
python midi_router_cli.py list

# Initialize config
python midi_router_cli.py init --controller Launchpad --virtual MagicBus

# Run router (interactive mode)
python midi_router_cli.py run

# Run with custom config
python midi_router_cli.py run --config /path/to/config.json
```

## Troubleshooting

### No MIDI devices found

Check:
1. Controller is connected via USB
2. Virtual MIDI port (IAC Driver) is enabled in Audio MIDI Setup
3. Run `python midi_router_cli.py list` to see available devices

### Router connects but no messages

Check:
1. Controller is in correct mode (e.g., Launchpad in Programmer mode)
2. MIDI Monitor (free app) to verify controller sends MIDI
3. Magic is listening to the virtual port (MagicBus)

### LEDs don't light up

Check:
1. Controller has external LED feedback enabled (Launchpad settings)
2. `led_on_velocity` is in valid range (1-127)
3. Some controllers use SysEx for LED control (not supported by basic router)

### Magic doesn't respond

Check:
1. Magic MIDI input is set to virtual port (MagicBus)
2. Global parameter is MIDI learned correctly
3. Range modifier is applied (0-127 → 0.0-1.0)

## Design Philosophy

This module follows **Grokking Simplicity** and **A Philosophy of Software Design**:

### Deep Modules

- `midi_domain.py` - Pure calculations (immutable data, no side effects)
- `midi_infrastructure.py` - Device I/O (hides rtmidi complexity)
- `midi_router.py` - Orchestration (dependency injection for testability)

### Immutable State

All domain models are frozen dataclasses:
- `ToggleConfig.toggle()` returns new instance
- `RouterConfig.with_toggle()` returns new instance
- `process_toggle()` is pure function (no mutations)

### Testability

100% test coverage of pure functions:
- MIDI parsing/creation
- Toggle logic
- State sync messages
- Config serialization

Infrastructure (rtmidi) is mockable via dependency injection.

## Future Extensions

Once the foundation is in place, you can add:

1. **Macros** - One button triggers multiple MIDI/OSC messages
2. **Banks** - Switch between banks so same pad sends different notes
3. **CC Support** - Use toggles with control change messages
4. **SysEx** - Advanced controller configuration (custom LED modes)
5. **OSC Bridge** - Send toggle state to other VJ tools (Resolume, VPT)

## Related Documentation

- [MIDI Controller Setup](../docs/midi-controller-setup.md) - Launchpad/MIDImix configuration
- [Live VJ Setup Guide](../docs/live-vj-setup-guide.md) - Complete rig with Syphon/Magic
- [Python VJ Tools](README.md) - VJ Console and Karaoke Engine

## License

Same as repository - see individual files for details.

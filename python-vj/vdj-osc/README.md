# VirtualDJ OSC Integration

Documentation for integrating VirtualDJ with external applications via OSC (Open Sound Control).

## Overview

VirtualDJ supports bidirectional OSC communication, allowing external applications to:
- **Receive** track information, playback state, BPM, and other real-time data
- **Send** commands to control VirtualDJ remotely

This is particularly useful for VJ applications, lighting control, and synchronized visualizations.

---

## VirtualDJ OSC Configuration

### Settings (Options → Internet)

| Setting | Description |
|---------|-------------|
| `oscPort` | Port to receive incoming OSC messages. Set to 0 to disable OSC server. VirtualDJ answers to commands like `/vdj/{vdjscript}`. **Requires VDJ PRO license.** |
| `oscPortBack` | Port for sending responses. OSC queries (`/vdj/query/{vdjscript}`) and subscriptions (`/vdj/{un}subscribe/{vdjscript}`) send answers to this port. |

### Example Configuration

```
oscPort = 8000      # VirtualDJ listens on port 8000
oscPortBack = 9000  # VirtualDJ sends responses to port 9000
```

---

## OSC Protocol

### Sending Commands to VirtualDJ

Send OSC messages to VirtualDJ's `oscPort` using the pattern:

```
/vdj/{vdjscript_command}
```

**Examples:**
```
/vdj/deck/1/play           # Start deck 1
/vdj/deck/2/pause          # Pause deck 2
/vdj/crossfader 0.5        # Set crossfader to center
/vdj/deck/1/volume 0.8     # Set deck 1 volume to 80%
/vdj/deck/1/effect_active 1 "echo" on   # Enable echo effect
```

### Querying Values

Use the `/vdj/query/` prefix to get current values:

```
/vdj/query/deck/1/get_bpm     # Returns current BPM of deck 1
/vdj/query/deck/1/get_artist  # Returns artist name
/vdj/query/deck/1/get_title   # Returns track title
/vdj/query/crossfader         # Returns crossfader position (0.0-1.0)
```

Responses are sent to `oscPortBack`.

### Subscribing to Changes

Subscribe to receive updates whenever a value changes:

```
/vdj/subscribe/deck/1/get_bpm      # Get BPM updates whenever it changes
/vdj/subscribe/deck/1/get_title    # Get title updates on track change
/vdj/subscribe/deck/1/play         # Get play state changes
```

Unsubscribe with:
```
/vdj/unsubscribe/deck/1/get_bpm
```

---

## VDJScript Reference

VDJScript is the scripting language used in VirtualDJ for all commands, mappings, and automation. OSC commands use VDJScript syntax.

### Basic Syntax

```
{deck} verb {param1} {param2} {while_pressed}
```

- **deck**: Optional deck specifier (`deck 1`, `deck 2`, `deck left`, `deck right`, `deck active`)
- **verb**: The action to perform (see verb categories below)
- **params**: Parameters depend on the verb
- **while_pressed**: Action is temporary while button is held

### Chaining Commands

```
command1 & command2 & command3     # Execute in sequence
command1 ? command2 : command3     # Conditional: if command1 then command2 else command3
command1 && command2               # Both must be true for LED queries
```

### Parameter Types

| Type | Example | Description |
|------|---------|-------------|
| Text | `'myfile.mp3'` or `"myfile.mp3"` | Strings in quotes |
| Boolean | `on`, `off`, `toggle` | True/false/invert |
| Time | `+100ms` | Milliseconds |
| Beat | `4bt` | Beats |
| Integer | `+1` | Whole numbers |
| Decimal | `0.5` | Floating point |
| Percentage | `50%` | Percentage value |

### Variables

| Prefix | Scope | Persistent |
|--------|-------|------------|
| `$myvar` | Global (all decks) | Session only |
| `#myvar` | Local to deck | Session only |
| `%myvar` | Local to logical deck | Session only |
| `@$myvar` | Global | Saved across sessions |
| `@%myvar` | Local to deck | Saved across sessions |

---

## Master Deck Detection

For VJ applications, it's critical to know which deck is "on-air" — the one the audience hears. VirtualDJ provides several mechanisms to determine the active/master deck.

### Key Verbs for Master Deck Detection

| Verb | Description | Use Case |
|------|-------------|----------|
| `is_audible` | Returns true if deck is playing AND volume is up (on-air) | **Primary method** - directly answers "can the audience hear this?" |
| `masterdeck` | Select/query this deck as the master deck for sync reference | Explicit master selection for multi-deck setups |
| `masterdeck_auto` | Remove manual masterdeck selection, return to automatic behavior | Let VDJ decide based on crossfader/volume |
| `get_activedeck` | Get the number of the current sync master deck | Find which deck others sync to |
| `get_crossfader_result` | Get volume balance between deck 1 and 2 based on crossfader, levels, and play state | Precise mix position (0.0 = left, 1.0 = right) |
| `select` | Select this deck as the "working deck" (beat display, default for shortcuts) | UI focus, not necessarily audible |

### Recommended Approach: `is_audible`

The `is_audible` verb is the most useful for VJ applications because it tells you if a deck is actually being heard by the audience.

**OSC Subscription Pattern:**
```
/vdj/subscribe/deck/1/is_audible    # Get notified when deck 1 goes on/off air
/vdj/subscribe/deck/2/is_audible    # Get notified when deck 2 goes on/off air
```

**Response:** VirtualDJ will send to `oscPortBack`:
```
/vdj/deck/1/is_audible  [1]    # Deck 1 is audible (on-air)
/vdj/deck/1/is_audible  [0]    # Deck 1 is not audible
```

### Crossfader Position for Blending

For smooth VJ transitions synced to the DJ's mix:

```
/vdj/subscribe/crossfader              # Crossfader position (0.0 = left, 1.0 = right)
/vdj/subscribe/get_crossfader_result   # Actual volume balance considering levels + play state
```

**Example:** Use `get_crossfader_result` to blend between two visual sources:
- `0.0` = Show 100% of Deck 1's visuals
- `0.5` = Show 50/50 blend
- `1.0` = Show 100% of Deck 2's visuals

### Deck Selection Verbs

| Verb | Description |
|------|-------------|
| `get_deck` | Get the number of this deck (1, 2, 3, 4) |
| `get_leftdeck` | Get the number of the left deck |
| `get_rightdeck` | Get the number of the right deck |
| `get_activedeck` | Get the number of the sync master deck |
| `get_defaultdeck` | Get the number of the default deck |
| `leftdeck` / `rightdeck` | Assign a deck as left/right |
| `invert_deck` | Swap left deck between 1↔3 or right deck between 2↔4 |

### Python Example: Master Deck Detection

```python
from pythonosc import udp_client, dispatcher, osc_server
import threading

vdj = udp_client.SimpleUDPClient("127.0.0.1", 8000)

# Track which deck is currently on-air
deck1_audible = False
deck2_audible = False
crossfader = 0.5

def on_deck1_audible(address, *args):
    global deck1_audible
    deck1_audible = bool(args[0]) if args else False
    update_master_deck()

def on_deck2_audible(address, *args):
    global deck2_audible
    deck2_audible = bool(args[0]) if args else False
    update_master_deck()

def on_crossfader(address, *args):
    global crossfader
    crossfader = args[0] if args else 0.5
    print(f"Crossfader: {crossfader:.2f} (Deck 1: {1-crossfader:.0%}, Deck 2: {crossfader:.0%})")

def update_master_deck():
    if deck1_audible and not deck2_audible:
        print("Master: Deck 1 (solo)")
    elif deck2_audible and not deck1_audible:
        print("Master: Deck 2 (solo)")
    elif deck1_audible and deck2_audible:
        print(f"Both decks audible - use crossfader position ({crossfader:.2f}) for blend")
    else:
        print("No deck audible")

# Subscribe to audibility changes
vdj.send_message("/vdj/subscribe/deck/1/is_audible", [])
vdj.send_message("/vdj/subscribe/deck/2/is_audible", [])
vdj.send_message("/vdj/subscribe/crossfader", [])

# Set up receiver
disp = dispatcher.Dispatcher()
disp.map("/vdj/deck/1/is_audible", on_deck1_audible)
disp.map("/vdj/deck/2/is_audible", on_deck2_audible)
disp.map("/vdj/crossfader", on_crossfader)

server = osc_server.ThreadingOSCUDPServer(("127.0.0.1", 9000), disp)
server.serve_forever()
```

### Multi-Deck Setups (4 Decks)

For 4-deck configurations:

```
/vdj/subscribe/deck/1/is_audible
/vdj/subscribe/deck/2/is_audible
/vdj/subscribe/deck/3/is_audible
/vdj/subscribe/deck/4/is_audible
/vdj/query/get_activedeck           # Which deck is the sync master
```

Use `leftcross` and `rightcross` to see which decks are assigned to crossfader sides:
- `deck 3 leftcross` assigns deck 3 to left side
- `deck 4 rightcross` assigns deck 4 to right side

---

## Essential VDJScript Verbs for VJ Integration

### Playback Information

| Verb | Description | Returns |
|------|-------------|---------|
| `play` | Query play state / Start playback | Boolean / Action |
| `pause` | Query pause state / Pause | Boolean / Action |
| `get_bpm` | Get current BPM | Float |
| `get_bpm absolute` | Get original BPM (ignoring pitch) | Float |
| `get_time` | Get elapsed time in ms | Integer |
| `get_time "remain"` | Get remaining time | Integer |
| `get_time_min` / `get_time_sec` | Get minutes/seconds | Integer |
| `song_pos` | Get/set position in song | Percentage |
| `get_position` | Get position in song | Percentage |

### Track Metadata

| Verb | Description | Returns |
|------|-------------|---------|
| `get_artist` | Artist name | String |
| `get_title` | Track title | String |
| `get_album` | Album name | String |
| `get_genre` | Genre | String |
| `get_key` | Musical key | String |
| `get_comment` | Comment field | String |
| `get_songlength` | Length in seconds | Float |
| `get_filepath` | Full file path | String |

### Beat & Sync Information

| Verb | Description | Returns |
|------|-------------|---------|
| `get_beat` | Beat intensity at current position | 0-100% |
| `get_beatgrid` | Beat intensity from beatgrid | 0-100% |
| `get_beatpos` | Position in beats from start | Float |
| `get_beat_num` | Beat number in measure (1-4) | Integer |
| `get_phrase_num` | Measure number in phrase (1-4) | Integer |
| `get_bar` | Current bar number | Integer |
| `is_sync` | Tracks are synchronized | Boolean |

### Audio Levels

| Verb | Description | Returns |
|------|-------------|---------|
| `get_level` | Signal level before master | 0.0-1.0 |
| `get_level_peak` | Peak signal level | 0.0-1.0 |
| `get_level_left` / `get_level_right` | Channel levels | 0.0-1.0 |
| `get_vu_meter` | Level after master volume | 0.0-1.0 |
| `get_spectrum_band 1` | Get spectrum band level (32 bands) | 0.0-1.0 |
| `get_spectrum_band 1 8` | Get band 1 of 8 bands | 0.0-1.0 |

### Mixer Controls

| Verb | Description | Range |
|------|-------------|-------|
| `volume` | Deck volume | 0-100% |
| `crossfader` | Crossfader position | 0% (left) - 100% (right) |
| `gain` | Deck gain | Percentage |
| `eq_high` / `eq_mid` / `eq_low` | EQ bands | Percentage |
| `filter` | Filter position | 0-100% (50% = off) |
| `master_volume` | Master output | Percentage |

### Effects

| Verb | Description |
|------|-------------|
| `effect_active 1 "echo"` | Check/toggle effect in slot 1 |
| `effect_select 1 "flanger"` | Select effect for slot 1 |
| `effect_slider 1 1 50%` | Set effect parameter |
| `get_effect_name` | Get active effect name |

### Loop & Cue

| Verb | Description |
|------|-------------|
| `loop` | Query loop state |
| `loop 4` | Set 4-beat loop |
| `get_loop` | Get loop length in beats |
| `hot_cue 1` | Jump to/set hotcue 1 |
| `cue_pos 1` | Get position of cue 1 |
| `cue_name 1` | Get name of cue 1 |

---

## VJ-Specific Use Cases

### Real-time Beat Synchronization

Subscribe to beat information for visual sync:

```
/vdj/subscribe/deck/1/get_beat       # Beat intensity (0-100%)
/vdj/subscribe/deck/1/get_beatgrid   # Grid-aligned beat
/vdj/subscribe/deck/1/get_bpm        # BPM changes
```

### Track Change Detection

Subscribe to track metadata:

```
/vdj/subscribe/deck/1/get_title
/vdj/subscribe/deck/1/get_artist
/vdj/subscribe/deck/1/loaded         # True when song loaded
```

### Audio Levels for Visualization

Query spectrum data at 60Hz:

```python
# Python example - polling spectrum bands
for band in range(8):
    osc_client.send_message(f"/vdj/query/deck/master/get_spectrum_band", [band + 1, 8])
```

### Mix Position Tracking

```
/vdj/subscribe/crossfader            # Crossfader position
/vdj/subscribe/deck/1/is_audible     # Deck 1 is on-air
/vdj/subscribe/deck/2/is_audible     # Deck 2 is on-air
```

---

## Python Integration Example

```python
from pythonosc import udp_client, dispatcher, osc_server
import threading

# Send commands to VirtualDJ
vdj_client = udp_client.SimpleUDPClient("127.0.0.1", 8000)

# Subscribe to BPM changes
vdj_client.send_message("/vdj/subscribe/deck/1/get_bpm", [])
vdj_client.send_message("/vdj/subscribe/deck/1/get_title", [])
vdj_client.send_message("/vdj/subscribe/deck/1/get_beat", [])

# Handle incoming OSC from VirtualDJ
def handle_bpm(address, *args):
    print(f"BPM: {args[0]}")

def handle_title(address, *args):
    print(f"Now Playing: {args[0]}")

def handle_beat(address, *args):
    # Trigger visual effect on beat
    beat_intensity = args[0]
    if beat_intensity > 0.8:
        trigger_flash()

disp = dispatcher.Dispatcher()
disp.map("/vdj/deck/1/get_bpm", handle_bpm)
disp.map("/vdj/deck/1/get_title", handle_title)
disp.map("/vdj/deck/1/get_beat", handle_beat)

# Start OSC server to receive VDJ responses
server = osc_server.ThreadingOSCUDPServer(("127.0.0.1", 9000), disp)
server_thread = threading.Thread(target=server.serve_forever)
server_thread.start()

# Query current state
vdj_client.send_message("/vdj/query/deck/1/get_artist", [])
vdj_client.send_message("/vdj/query/deck/1/get_title", [])
```

---

## OS2L Protocol (Open Sound 2 Light)

VirtualDJ also supports OS2L for DMX/lighting integration:

| Setting | Description |
|---------|-------------|
| `os2l` | Enable/disable OS2L |
| `os2lDirectIp` | IP:port of DMX application |
| `os2lBeatOffset` | Beat timing correction (ms) |

OS2L verbs:
```
os2l_button "blackout"           # Trigger lighting command
os2l_scene "mypage" "myscene"    # Activate lighting scene
os2l_cmd 42 on                   # Send numeric command
```

---

## Python OSC Library Comparison

Several Python libraries are available for OSC communication:

| Library | Install | Bundles | Dependencies | Notes |
|---------|---------|---------|--------------|-------|
| **python-osc** | `pip install python-osc` | ✅ Yes | Pure Python | **Recommended** - Most popular (564⭐), actively maintained (Dec 2024), UDP+TCP support |
| **oscpy** | `pip install oscpy` | ✅ Yes | Pure Python | Kivy project, has CLI tool, but stale since 2021 |
| **pyliblo3** | `pip install pyliblo3` | ✅ Yes | liblo (C) | Fastest performance, but requires native library |
| **aiosc** | `pip install aiosc` | ❌ No | Pure Python | Minimalist asyncio-native, no bundle support |

### Recommended: python-osc

```python
from pythonosc import udp_client, dispatcher, osc_server
```

This library follows OSC 1.0 spec strictly and provides the best combination of features, community support, and ease of installation.

---

## Troubleshooting

### Warning: "Could not identify content type of dgram"

When using `python-osc` with VirtualDJ subscriptions, you may see warnings like:

```
WARNING - Could not identify content type of dgram b'...'
WARNING - Unhandled parameter type (d)
```

**Cause:** VirtualDJ sends OSC bundle acknowledgments for subscriptions that contain non-standard or empty content. The `python-osc` library is strict about OSC spec compliance and logs warnings when it encounters unexpected data formats.

**Impact:** These warnings are **cosmetic only** - your actual data (track info, BPM, levels) comes through correctly. The warnings occur during the subscription handshake, not during normal data flow.

**Solutions:**

1. **Suppress warnings** (recommended for production):
   ```python
   import logging
   logging.getLogger('pythonosc').setLevel(logging.ERROR)
   ```

2. **Filter specific loggers:**
   ```python
   import logging
   logging.getLogger('pythonosc.osc_bundle').setLevel(logging.ERROR)
   logging.getLogger('pythonosc.osc_message').setLevel(logging.ERROR)
   ```

3. **Use a catch-all handler** to silently consume unmatched messages:
   ```python
   def catch_all(address, *args):
       pass  # Ignore unknown messages
   
   dispatcher.set_default_handler(catch_all)
   ```

### VirtualDJ Not Responding to OSC

1. **Check license:** OSC features require VirtualDJ PRO license
2. **Verify ports:** Ensure `oscPort` and `oscPortBack` are set in VDJ Options → Internet
3. **Firewall:** Allow UDP traffic on configured ports
4. **VDJ running:** VirtualDJ must be running before sending OSC messages

### No Subscription Updates

- Subscriptions only send updates when values **change**
- Query first to get current value: `/vdj/query/deck/1/get_bpm`
- Then subscribe for changes: `/vdj/subscribe/deck/1/get_bpm`

---

## References

- [VDJScript Documentation](https://www.virtualdj.com/wiki/VDJscript.html)
- [VDJScript Verbs List](https://www.virtualdj.com/manuals/virtualdj/appendix/vdjscriptverbs.html)
- [VirtualDJ Options List](https://www.virtualdj.com/manuals/virtualdj/appendix/optionslist.html)
- [Controller Definition (MIDI)](https://www.virtualdj.com/wiki/ControllerDefinitionMIDI.html)

---

## License Requirements

⚠️ **Note**: OSC features (`oscPort`, `oscPortBack`) require a **VirtualDJ PRO license**.
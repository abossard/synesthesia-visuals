# MIDI Router - Quick Reference

## What Is This?

A stateful MIDI router built into the VJ Console (Screen 5) that manages toggle buttons with LED feedback between your MIDI controller and Magic Music Visuals.

## Why?

Magic can't remember toggle state or send LED feedback. This router:
- ✅ Remembers which buttons are ON/OFF
- ✅ Lights up LEDs on your controller
- ✅ Sends absolute values to Magic (no confusion)
- ✅ Restores state on restart

## Quick Start

### 1. Setup Virtual MIDI (One Time)
- Open **Audio MIDI Setup** → Window → Show MIDI Studio
- Double-click **IAC Driver** → Check "Device is online"
- Add port named **MagicBus**

### 2. Launch VJ Console
```bash
cd python-vj
python vj_console.py
```

### 3. Press `5` for MIDI Screen

### 4. Learn a Toggle
1. Press `l` (learn mode activates - yellow status)
2. Press any pad on your Launchpad
3. Toggle captured! Press same pad → LED lights up

### 5. Use in Magic
- Create Global parameter
- MIDI Learn → press the pad
- Add Range modifier (0-127 → 0.0-1.0)
- Done!

## VJ Console Screen 5 Layout

```
Left Side:                    Right Side:
┌─ MIDI Router ─────────┐   ┌─ MIDI Toggles ─────────┐
│ ● Running             │   │   40: TwisterOn  ● ON  │
│ Launchpad → MagicBus  │   │ ▸ 41: LyricsOn   ○ OFF │
└───────────────────────┘   └────────────────────────┘
┌─ Actions ─────────────┐   ┌─ MIDI Traffic ─────────┐
│ l   Learn mode        │   │ 14:23:45 → Note #42=127│
│ k/j Navigate          │   │ 14:23:44 ← Note #42=100│
│ d   Delete toggle     │   │ 14:23:40 → Note #41=0  │
│ space Test toggle     │   │ (real-time MIDI log)   │
└───────────────────────┘   └────────────────────────┘
```

## Keyboard Controls (MIDI Screen)

| Key | Action |
|-----|--------|
| `5` | Go to MIDI screen |
| `l` | Learn mode (capture next pad) |
| `k` / `↑` | Navigate up |
| `j` / `↓` | Navigate down |
| `d` | Delete selected toggle |
| `space` | Test toggle (simulate press) |
| `q` | Quit |

## Config Location

`~/.midi_router/config.json` - automatically created on first run

## Troubleshooting

**No MIDI devices found?**
- Check USB connection
- Check IAC Driver is enabled
- Run `python midi_router_cli.py list` to see devices

**LEDs don't light?**
- Put Launchpad in Programmer mode (Session + orange button)
- Check external LED feedback is enabled

**Magic doesn't respond?**
- Set Magic MIDI input to MagicBus
- Verify MIDI Learn on Global parameter
- Check Range modifier is applied

## Architecture

**Pure domain logic** (midi_domain.py)
- Immutable data structures
- Pure functions (no side effects)
- All business logic testable

**Infrastructure** (midi_infrastructure.py)  
- Device discovery
- MIDI I/O (wraps python-rtmidi)

**Orchestration** (midi_router.py)
- State management
- Config persistence
- Dependency injection

**UI** (midi_console.py)
- Reactive Textual panels
- Real-time updates
- Integrated into vj_console.py

## Tests

Run tests:
```bash
python test_midi_router.py
```

33 tests covering:
- MIDI message parsing
- Toggle state logic
- Config serialization
- State sync messages

## Design Philosophy

Follows **Grokking Simplicity** and **A Philosophy of Software Design**:
- Deep modules (simple interface, complex implementation)
- Pure calculations separated from actions
- Immutable data (thread-safe)
- Testable architecture (DI)

## Related Docs

- [Full MIDI Router Guide](MIDI_ROUTER.md)
- [MIDI Controller Setup](../docs/midi-controller-setup.md)
- [Live VJ Setup Guide](../docs/live-vj-setup-guide.md)

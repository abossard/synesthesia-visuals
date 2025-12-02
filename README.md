# Synesthesia Visuals

A toolkit for VJ performances combining Synesthesia shaders, Processing games, and MIDI controller integration.

## Repository Structure

```
├── synesthesia-shaders/    # Synesthesia scene files and GLSL shaders
├── processing-vj/          # Processing games and interactive visuals
│   ├── examples/           # Example game implementations
│   └── lib/                # Shared utilities
├── python-vj/              # Python VJ control and karaoke engine
│   ├── vj_console.py       # Terminal UI for managing VJ apps
│   └── karaoke_engine.py   # Lyrics via OSC from Spotify/VirtualDJ
└── docs/                   # Documentation and guides
```

## Quick Start

### Synesthesia Shaders
The `synesthesia-shaders/` folder contains `.synScene` directories with GLSL shaders for use with [Synesthesia](https://synesthesia.live/).

### Processing Games
The `processing-vj/` folder contains Processing sketches for interactive visuals controlled by Launchpad Mini Mk3.

**Requirements:**
- [Processing 4.x](https://processing.org/download)
- [The MidiBus library](http://www.smallbutdigital.com/projects/themidibus/)
- Launchpad Mini Mk3 (in Programmer mode)

### Python VJ Tools
The `python-vj/` folder contains professional VJ control tools:

**VJ Console** - Terminal UI for managing Processing apps with daemon mode (auto-restart on crash)  
**Karaoke Engine** - Monitors Spotify/VirtualDJ, fetches synced lyrics, and sends them via OSC  
**MIDI Router** - Stateful MIDI middleware with toggle management and LED feedback for Magic Music Visuals

**Installation:**
```bash
cd python-vj
pip install -r requirements.txt
python vj_console.py          # Launch VJ console
python midi_router_cli.py run # Launch MIDI router
```

### MIDI Controllers
This project uses:
- **Akai MIDImix** - VJ/lighting control (faders, knobs)
- **Launchpad Mini Mk3** - Interactive games (pad grid)

## Documentation

| Guide | Description |
|-------|-------------|
| [Live VJ Setup Guide](docs/live-vj-setup-guide.md) | **Complete live rig**: Processing + Syphon + Synesthesia + Magic + BlackHole |
| [MIDI Controller Setup](docs/midi-controller-setup.md) | How to configure MIDImix and Launchpad |
| [MIDI Router](python-vj/MIDI_ROUTER.md) | **Toggle state manager** for Magic Music Visuals with LED feedback |
| [Processing Games Guide](docs/processing-games-guide.md) | Creating interactive VJ games in Java |
| [Python VJ Tools](python-vj/README.md) | VJ Console and Karaoke Engine documentation |
| [ISF to Synesthesia Migration](docs/isf-to-synesthesia-migration.md) | Converting shaders to SSF format |

## Controller Roles

| Controller | Primary Use | Mode |
|------------|-------------|------|
| Akai MIDImix | VJ / lighting control | Standard MIDI |
| Launchpad Mini Mk3 | Processing games | Programmer mode |

## License

See individual shader files for licensing. Original shader credits are preserved in scene metadata.

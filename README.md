# Synesthesia Visuals

A toolkit for VJ performances combining Synesthesia shaders, Processing games, and MIDI controller integration.

## Repository Structure

```
├── synesthesia-shaders/    # Synesthesia scene files and GLSL shaders
├── processing-vj/          # Processing games and interactive visuals
│   ├── examples/           # Example game implementations
│   └── lib/                # Shared utilities
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

### MIDI Controllers
This project uses:
- **Akai MIDImix** - VJ/lighting control (faders, knobs)
- **Launchpad Mini Mk3** - Interactive games (pad grid)

## Documentation

| Guide | Description |
|-------|-------------|
| [Live VJ Setup Guide](docs/live-vj-setup-guide.md) | **Complete live rig**: Processing + Syphon + Synesthesia + Magic + BlackHole |
| [MIDI Controller Setup](docs/midi-controller-setup.md) | How to configure MIDImix and Launchpad |
| [Processing Games Guide](docs/processing-games-guide.md) | Creating interactive VJ games in Java |
| [ISF to Synesthesia Migration](docs/isf-to-synesthesia-migration.md) | Converting shaders to SSF format |

## Controller Roles

| Controller | Primary Use | Mode |
|------------|-------------|------|
| Akai MIDImix | VJ / lighting control | Standard MIDI |
| Launchpad Mini Mk3 | Processing games | Programmer mode |

## License

See individual shader files for licensing. Original shader credits are preserved in scene metadata.

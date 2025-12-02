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
The `python-vj/` folder contains the VJ Console and Karaoke Engine:

**VJ Console** - Terminal UI for managing Processing apps with daemon mode (auto-restart on crash)
**Karaoke Engine** - Monitors Spotify/VirtualDJ, fetches synced lyrics, and sends them via OSC

**Installation:**
```bash
cd python-vj
pip install -r requirements.txt
python vj_console.py
```

### MIDI Controllers
This project uses:
- **Akai MIDImix** - VJ/lighting control (faders, knobs)
- **Launchpad Mini Mk3** - Interactive games (pad grid)

## Documentation

### Essential Guides

| Guide | Description |
|-------|-------------|
| **[Processing VJ Guides](docs/processing-guides/README.md)** | **NEW**: Comprehensive guide series for creating interactive, audio-reactive simulations |
| [Live VJ Setup Guide](docs/live-vj-setup-guide.md) | **Complete live rig**: Processing + Syphon + Synesthesia + Magic + BlackHole |
| [MIDI Controller Setup](docs/midi-controller-setup.md) | How to configure MIDImix and Launchpad |
| [Processing Games Guide](docs/processing-games-guide.md) | Creating interactive VJ games in Java |
| [Python VJ Tools](python-vj/README.md) | VJ Console and Karaoke Engine documentation |
| [ISF to Synesthesia Migration](docs/isf-to-synesthesia-migration.md) | Converting shaders to SSF format |

### Processing VJ Guide Series (NEW)

Master creating **interactive, living, efficient simulations** in Processing for VJ performances:

- **[Overview](docs/processing-guides/00-overview.md)** - System architecture, quick start, performance targets
- **[Core Concepts](docs/processing-guides/01-core-concepts.md)** - Module lifecycle, coordinate systems, anti-patterns
- **[Audio Reactivity](docs/processing-guides/02-audio-reactivity.md)** - FFT analysis, beat detection, BPM calculation
- **[Particle Systems](docs/processing-guides/03-particle-systems.md)** - CPU & GPU particles, PixelFlow (100k+ particles)
- **[Fluid Simulations](docs/processing-guides/04-fluid-simulations.md)** - Reaction-diffusion, flow fields, GPU fluids
- **[Code Patterns](docs/processing-guides/08-code-patterns.md)** - Copy-paste ready modules and algorithms
- **[Resources](docs/processing-guides/09-resources.md)** - Libraries, tools, examples, learning materials

**Features**: Modern 2024 techniques, GPU acceleration, mermaid diagrams, AI-optimized structure

## Controller Roles

| Controller | Primary Use | Mode |
|------------|-------------|------|
| Akai MIDImix | VJ / lighting control | Standard MIDI |
| Launchpad Mini Mk3 | Processing games | Programmer mode |

## License

See individual shader files for licensing. Original shader credits are preserved in scene metadata.

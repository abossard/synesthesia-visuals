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

**[📚 Complete Documentation](docs/)** - Organized by purpose: Setup, Operation, Reference, Development, Archive

### Quick Links by Purpose

**🚀 Setup & Installation**
- [Quick Start: OSC Pipeline](docs/setup/QUICK_START_OSC_PIPELINE.md) - Get running in 5 minutes
- [Live VJ Setup Guide](docs/setup/live-vj-setup-guide.md) - Complete live rig setup
- [MIDI Controller Setup](docs/setup/midi-controller-setup.md) - Configure hardware

**🎮 Using the System**
- [Processing Games Guide](docs/operation/processing-games-guide.md) - Interactive VJ games
- [Magic Music Visuals Guide](docs/operation/magic-music-visuals-guide.md) - MMV operations
- [MMV Master Pipeline](docs/operation/mmv-master-pipeline-guide.md) - Production setup

**📚 Technical Reference**
- [Processing VJ Guides](docs/reference/processing-guides/README.md) - Comprehensive development series
- [Processing Levels](docs/reference/processing-levels/README.md) - 14 visual concept implementations
- [ISF to Synesthesia Migration](docs/reference/isf-to-synesthesia-migration.md) - Shader conversion
- [Python VJ Tools](python-vj/README.md) - VJ Console, audio analyzer, MIDI router

**🔧 Development**
- [Active Development Plans](docs/development/) - Implementation roadmaps
- [Python VJ Refactor Plan](docs/development/python-vj-refactor-plan.md) - Architecture improvements

### Processing VJ Guide Highlights

Master creating **interactive, living, efficient simulations** for VJ performances:
- Audio Reactivity (FFT, beat detection, BPM)
- Particle Systems (100k+ particles with GPU)
- Fluid Simulations (reaction-diffusion, flow fields)
- Code Patterns (copy-paste ready modules)

Full series: [docs/reference/processing-guides/](docs/reference/processing-guides/README.md)

## Controller Roles

| Controller | Primary Use | Mode |
|------------|-------------|------|
| Akai MIDImix | VJ / lighting control | Standard MIDI |
| Launchpad Mini Mk3 | Processing games | Programmer mode |

## License

See individual shader files for licensing. Original shader credits are preserved in scene metadata.

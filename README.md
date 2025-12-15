# Synesthesia Visuals

A toolkit for VJ performances combining Synesthesia shaders, Processing games, and MIDI controller integration.

## Repository Structure

```
├── synesthesia-shaders/    # Synesthesia scene files and GLSL shaders
├── swift-vj/               # Swift Metal VJ app (replaces VJUniverse + KaraokeOverlay)
│   ├── Sources/SwiftVJ/    # Metal shader renderer with karaoke overlay
│   ├── Shaders/            # Metal shaders (.metal files)
│   └── README.md           # Swift VJ documentation
├── processing-vj/          # Processing interactive visuals and shader engines
│   ├── examples/           # VJ game implementations (Launchpad-controlled)
│   ├── src/                # Main applications:
│   │   ├── VJSims/         # Simulation framework with Synesthesia Audio OSC
│   │   ├── VJUniverse/     # GLSL shader engine (legacy - use swift-vj)
│   │   ├── KaraokeOverlay/ # Lyrics display (legacy - use swift-vj)
│   │   └── ImageOverlay/   # AI-generated image display
│   └── lib/                # Shared utilities (LaunchpadUtils)
├── python-vj/              # Python VJ control and automation
│   ├── vj_console.py       # Terminal UI for managing Processing apps
│   ├── karaoke_engine.py   # Lyrics via OSC from Spotify/VirtualDJ
│   ├── ai_services.py      # LLM integration (Ollama/LM Studio)
│   └── midi_router.py      # MIDI middleware with state management
├── archive/                # Deprecated components (ISF shaders, old audio analyzers)
└── docs/                   # Documentation and guides
```

## Quick Start

### Synesthesia Shaders
The `synesthesia-shaders/` folder contains `.synScene` directories with GLSL shaders for use with [Synesthesia](https://synesthesia.live/).

**Convert shaders from Shadertoy/ISF**: Use the [Shadertoy to Synesthesia Converter](.github/prompts/shadertoy-to-synesthesia-converter.prompt.md) prompt for AI-powered conversion with intelligent audio reactivity.

### Swift VJ Application (Recommended for Apple Silicon)
The `swift-vj/` folder contains a native macOS Metal-based VJ application:

**SwiftVJ** - High-performance Metal shader renderer with karaoke overlay
- Native Apple Silicon support (also runs on Intel)
- Metal shader rendering with audio reactivity
- Multiple Syphon channels (shader, lyrics, refrain, song info)
- OSC integration with python-vj pipeline
- ~10x more efficient than Processing (150MB RAM vs 600MB+)
- **Replaces**: VJUniverse + KaraokeOverlay with single efficient app

**Build and Run:**
```bash
cd swift-vj
swift build -c release
.build/release/SwiftVJ
```

See [swift-vj/README.md](swift-vj/README.md) for detailed documentation.

### Processing Visual Applications
The `processing-vj/` folder contains multiple applications:

**VJSims** - Simulation framework for creating interactive audio-reactive visuals
- Launchpad Mini Mk3 control
- Synesthesia Audio OSC support (TODO)  
- Syphon output for VJ software integration

**VJUniverse** (Legacy - consider SwiftVJ) - GLSL shader engine with LLM-powered shader selection
- 100+ GLSL shaders (.glsl, .txt, .frag)
- Ollama/LM Studio integration for mood-based shader selection
- Synesthesia Audio OSC reactivity
- **Note**: ISF format no longer supported (use converter above)

**KaraokeOverlay** (Legacy - consider SwiftVJ) - AI-powered lyrics display
- AI refrain detection for chorus highlighting  
- Multiple display modes (full lyrics, refrain only, word-by-word)

**Interactive Games** - VJ performance games (examples/ directory)
- Snake, Whack-a-Mole, and more with Launchpad control

**Requirements:**
- [Processing 4.x](https://processing.org/download)
- [The MidiBus library](http://www.smallbutdigital.com/projects/themidibus/)
- Launchpad Mini Mk3 (in Programmer mode)

### Python VJ Tools
The `python-vj/` folder contains professional VJ control tools:

**VJ Console** - Terminal UI for managing Processing apps with daemon mode (auto-restart on crash)  
**Karaoke Engine** - Monitors Spotify/VirtualDJ, fetches synced lyrics, sends via OSC  
**AI Services** - LLM integration for shader analysis, lyrics analysis, image generation
**MIDI Router** - Stateful MIDI middleware with toggle management and LED feedback

**Installation:**
```bash
cd python-vj
pip install -r requirements.txt
python vj_console.py          # Launch VJ console
python midi_router_cli.py run # Launch MIDI router
```

## Audio Analytics

**Primary Engine**: [Synesthesia](https://synesthesia.live/) provides professional audio analysis with:
- Per-band energy (bass, mid, high)
- Beat detection and BPM estimation  
- Spectral features (centroid, flux)
- Low-latency OSC output (~10-30ms)

**Note**: Python/Essentia-based audio analyzer has been removed. Use Synesthesia for all audio analysis needs.

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
- [ISF to Synesthesia Migration](docs/reference/isf-to-synesthesia-migration.md) - Manual shader conversion
- [Shadertoy to Synesthesia Converter](.github/prompts/shadertoy-to-synesthesia-converter.prompt.md) - AI-powered conversion prompt
- [Python VJ Tools](python-vj/README.md) - VJ Console, audio analyzer, MIDI router, AI services

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

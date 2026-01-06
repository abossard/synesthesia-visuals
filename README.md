# Synesthesia Visuals

A toolkit for VJ performances combining Synesthesia shaders, Swift-VJ control application, and MIDI controller integration.

## Repository Structure

```
├── synesthesia-shaders/    # Synesthesia scene files and GLSL shaders
├── swift-vj/               # Swift VJ control application (macOS native)
│   ├── Sources/
│   │   ├── SwiftVJApp/     # SwiftUI application
│   │   │   ├── Rendering/  # Metal-based shader/text/image rendering
│   │   │   └── Views/      # Master control, OSC debug, shader browser
│   │   └── SwiftVJCore/    # Core library
│   │       ├── Modules/    # Playback, Lyrics, AI, Shaders, Pipeline
│   │       ├── Adapters/   # LyricsFetcher, OSCHub, VDJMonitor, etc.
│   │       └── Launchpad/  # MIDI controller support
│   └── Tests/              # 197 tests (TDD from day one)
├── magic/                  # Magic Music Visuals integration
├── archive/                # Deprecated components (python-vj, processing-vj, ISF shaders)
└── docs/                   # Documentation and guides
```

## Quick Start

### Synesthesia Shaders
The `synesthesia-shaders/` folder contains `.synScene` directories with GLSL shaders for use with [Synesthesia](https://synesthesia.live/).

**Convert shaders from Shadertoy/ISF**: Use the [Shadertoy to Synesthesia Converter](.github/prompts/shadertoy-to-synesthesia-converter.prompt.md) prompt for AI-powered conversion with intelligent audio reactivity.

### Swift-VJ Control Application
The `swift-vj/` folder contains a native macOS application for VJ control and visual rendering.

**Features:**
- **Playback Monitoring** - VirtualDJ (OSC) and Spotify (AppleScript) support
- **Lyrics System** - LRCLIB API + AI refrain detection, synced to playback
- **AI Analysis** - LLM-powered song categorization, mood/energy scoring
- **Shader Engine** - Metal-based rendering with 100+ GLSL shaders
- **MIDI Control** - Launchpad Mini Mk3 support with learn mode
- **OSC Hub** - Multi-target forwarding with pattern matching
- **Syphon Output** - For VJ software integration (Magic, Resolume, VDMX)

**Requirements:**
- macOS 14.0+ (Sonoma)
- Xcode 15+ / Swift 5.9+

**Installation:**
```bash
cd swift-vj
swift build
swift run swift-vj  # Launch application
```

See [swift-vj/README.md](swift-vj/README.md) for detailed documentation.

### Archived: Python-VJ and Processing-VJ
**Note:** The Python and Processing-based systems have been archived and replaced by Swift-VJ. See [PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md](PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md) for feature parity and migration guide.

The archived implementations are available in:
- `archive/python-vj/` - Python VJ control system (Textual TUI)
- `archive/processing-vj/` - Processing sketches and games (Java)

## Audio Analytics

**Primary Engine**: [Synesthesia](https://synesthesia.live/) provides professional audio analysis with:
- Per-band energy (bass, mid, high)
- Beat detection and BPM estimation  
- Spectral features (centroid, flux)
- Low-latency OSC output (~10-30ms)

**Integration**: Swift-VJ receives audio data via OSC from Synesthesia and uses it for:
- Audio-reactive shader parameters
- Beat-synced animations
- BPM-based LED blinking (Launchpad)

**Note**: Python/Essentia-based audio analyzer has been removed. Use Synesthesia for all audio analysis needs.

### MIDI Controllers
This project uses:
- **Akai MIDImix** - VJ/lighting control (faders, knobs)
- **Launchpad Mini Mk3** - Interactive control (pad grid, learn mode)

Swift-VJ includes full Launchpad support via CoreMIDI with:
- 4 pad modes (SELECTOR, TOGGLE, ONE_SHOT, PUSH)
- Button groups with radio behavior
- LED control (10 colors × 3 brightness levels)
- Learn mode for interactive pad mapping
- Beat-synced LED blinking

## Documentation

**[📚 Complete Documentation](docs/)** - Organized by purpose: Setup, Operation, Reference, Development, Archive

### Quick Links by Purpose

**🚀 Setup & Installation**
- [Quick Start: OSC Pipeline](docs/setup/QUICK_START_OSC_PIPELINE.md) - Get running in 5 minutes
- [Live VJ Setup Guide](docs/setup/live-vj-setup-guide.md) - Complete live rig setup
- [MIDI Controller Setup](docs/setup/midi-controller-setup.md) - Configure hardware

**🎮 Using the System**
- [Swift-VJ Documentation](swift-vj/README.md) - Native macOS VJ control application
- [Swift-VJ Rewrite Plan](swift-vj/REWRITE_PLAN.md) - Complete feature inventory and architecture
- [Magic Music Visuals Guide](docs/operation/magic-music-visuals-guide.md) - MMV operations
- [MMV Master Pipeline](docs/operation/mmv-master-pipeline-guide.md) - Production setup

**📚 Technical Reference**
- [OSC Architecture](OSC.md) - Current OSC communication system
- **[OSC Future Plan](OSC_FUTURE_PLAN.md)** - 🚀 Planned OSC evolution (VDJ queries, forwarding, Launchpad)
- [ISF to Synesthesia Migration](docs/reference/isf-to-synesthesia-migration.md) - Manual shader conversion
- [Shadertoy to Synesthesia Converter](.github/prompts/shadertoy-to-synesthesia-converter.prompt.md) - AI-powered conversion prompt

**🔧 Development**
- [Active Development Plans](docs/development/) - Implementation roadmaps
- [Swift-VJ Code Examples](swift-vj/CODE_EXAMPLES.md) - Design patterns and code samples

**📦 Migration & Archive**
- **[Python-VJ/Processing-VJ Migration Guide](PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md)** - Feature parity and migration checklist
- [Archived Components](archive/README.md) - Legacy systems (python-vj, processing-vj)

## Controller Roles

| Controller | Primary Use | Mode | Integration |
|------------|-------------|------|-------------|
| Akai MIDImix | VJ / lighting control | Standard MIDI | Synesthesia, Swift-VJ |
| Launchpad Mini Mk3 | VJ control and scene triggering | Programmer mode | Swift-VJ (CoreMIDI with learn mode) |

**Launchpad Features in Swift-VJ:**
- Banks 0-3: Synesthesia scene/effect control
- Banks 4-7: Swift-VJ shader selection and parameters
- Learn mode for custom pad mappings
- Beat-synced LED feedback
- JSON config persistence

See [OSC_FUTURE_PLAN.md](OSC_FUTURE_PLAN.md#step-04-launchpad-controller-architecture) for planned architecture.

## License

See individual shader files for licensing. Original shader credits are preserved in scene metadata.

# Documentation

Documentation for the VJ/visual performance toolkit, organized by purpose.

## 📁 Documentation Categories

### 🚀 [Setup](setup/)
**Installation and configuration guides**
- Quick Start: OSC Pipeline
- Live VJ Setup Guide  
- MIDI Controller Setup

Start here if you're setting up the system for the first time.

### 🎮 [Operation](operation/)
**Using the system in performance**
- Swift-VJ Application Guide
- Magic Music Visuals Guide
- MMV Master Pipeline Guide
- ⚠️ Processing Games Guide (archived)

Your guide for live VJ work and creative sessions.

### 📚 [Reference](reference/)
**Technical documentation and APIs**
- Swift-VJ Architecture and Modules
- ISF to Synesthesia Migration
- Audio analysis via Synesthesia
- ⚠️ Processing VJ Guides (archived)

Deep technical details and API references.

### 🔧 [Development](development/)
**Implementation plans and future work**
- **Swift-VJ Rewrite Plan** ⭐ ACTIVE
- **Shader Generation Implementation Plan** ⭐ NEW
- Shader Orchestrator Plan
- Pipeline Planner Improvements
- ⚠️ Python VJ Refactor Plan (archived)
- ⚠️ Processing Implementation Plan (archived)

Active development roadmaps and architecture improvements.

### 📦 [Archive](archive/)
**Historical documentation**
- Python-VJ and Processing-VJ implementations
- Completed investigations
- Superseded content

Preserved for reference but not actively maintained.

## Quick Navigation

### I want to...

**Get started quickly**
→ [Setup: Quick Start OSC Pipeline](setup/QUICK_START_OSC_PIPELINE.md)

**Set up for a live show**
→ [Setup: Live VJ Setup Guide](setup/live-vj-setup-guide.md)

**Learn about Swift-VJ architecture**
→ [Swift-VJ: Rewrite Plan](../swift-vj/REWRITE_PLAN.md)

**Use Magic Music Visuals**
→ [Operation: Magic Music Visuals Guide](operation/magic-music-visuals-guide.md)

**Understand the system architecture**
→ [Development: Swift-VJ Rewrite Plan](../swift-vj/REWRITE_PLAN.md)

**Generate shaders dynamically with AI**
→ [Development: Shader Generation Implementation Plan](development/SHADER_GENERATION_IMPLEMENTATION_PLAN.md)

**Convert shaders to Synesthesia**
→ [Reference: ISF to Synesthesia Migration](reference/isf-to-synesthesia-migration.md)

**Control with MIDI (Launchpad)**
→ [Swift-VJ: Launchpad Module](../swift-vj/README.md#launchpad-midi-control)

**Migrate from Python-VJ or Processing-VJ**
→ [Migration Guide](../PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md)

## Component Documentation

Beyond this docs folder:

- **[Swift-VJ](../swift-vj/README.md)** - Native macOS VJ control application (current)
- **[Migration Guide](../PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md)** - Python-VJ/Processing-VJ to Swift-VJ
- **[Synesthesia Shaders](../synesthesia-shaders/README.md)** - GLSL shader scenes

### Archived Components
- **[Python VJ Tools](../archive/python-vj/README.md)** - Legacy VJ Console, audio analyzer, MIDI router (archived 2026-01-05)
- **[Processing Projects](../archive/processing-vj/README.md)** - Interactive visuals and games (archived 2026-01-05)

## Quick Reference

### Controllers
| Controller | Use | Mode |
|------------|-----|------|
| Akai MIDIMix | VJ/lighting control | Standard MIDI |
| Launchpad Mini Mk3 | Swift-VJ shader control | Programmer mode |

### Technologies
- **Swift 5.9+** for VJ control application (macOS 14.0+)
- **Metal** for GPU-accelerated shader rendering
- **Synesthesia** for GLSL shader playback and audio analysis
- **Syphon** (macOS) for frame sharing to VJ software

### Key Conventions
- Launchpad grid: notes 11-88 (8x8 pads)
- MIDIMix faders: CC 20-27 (layers 1-8)
- Processing resolution: 1920x1080 for VJ output
- Synesthesia uniforms: `syn_*` prefix for audio reactivity

## Additional Resources

- [PixelFlow](https://diwi.github.io/PixelFlow/) - GPU-accelerated Processing library
- [Synesthesia](https://synesthesia.live/) - Live visual performance software
- [Processing](https://processing.org/) - Creative coding platform
- [Essentia](https://essentia.upf.edu/) - Audio analysis library

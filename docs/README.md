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
- Processing Games Guide
- Magic Music Visuals Guide
- MMV Master Pipeline Guide

Your guide for live VJ work and creative sessions.

### 📚 [Reference](reference/)
**Technical documentation and APIs**
- Processing VJ Guides (comprehensive series)
- Processing Levels (14 visual concepts)
- ISF to Synesthesia Migration
- Audio analysis and MIDI routing

Deep technical details and copy-paste ready code patterns.

### 🔧 [Development](development/)
**Implementation plans and future work**
- **Shader Generation Implementation Plan** ⭐ NEW
- Shader Generation Quick Reference
- Processing Implementation Plan
- Python VJ Refactor Plan
- Shader Orchestrator Plan
- Pipeline Planner Improvements

Active development roadmaps and architecture improvements.

### 📦 [Archive](archive/)
**Historical documentation**
- Completed implementations
- Resolved investigations
- Superseded content

Preserved for reference but not actively maintained.

## Quick Navigation

### I want to...

**Get started quickly**
→ [Setup: Quick Start OSC Pipeline](setup/QUICK_START_OSC_PIPELINE.md)

**Set up for a live show**
→ [Setup: Live VJ Setup Guide](setup/live-vj-setup-guide.md)

**Learn to create Processing visuals**
→ [Reference: Processing VJ Guides](reference/processing-guides/README.md)

**Use Magic Music Visuals**
→ [Operation: Magic Music Visuals Guide](operation/magic-music-visuals-guide.md)

**Understand the system architecture**
→ [Development: Python VJ Refactor Plan](development/python-vj-refactor-plan.md)

**Generate shaders dynamically with AI**
→ [Development: Shader Generation Implementation Plan](development/SHADER_GENERATION_IMPLEMENTATION_PLAN.md)

**Convert shaders to Synesthesia**
→ [Reference: ISF to Synesthesia Migration](reference/isf-to-synesthesia-migration.md)

**Control with MIDI**
→ [Setup: MIDI Controller Setup](setup/midi-controller-setup.md)

## Component Documentation

Beyond this docs folder:

- **[Python VJ Tools](../python-vj/README.md)** - VJ Console, audio analyzer, MIDI router
- **[Processing Projects](../processing-vj/README.md)** - Interactive visuals and games  
- **[Synesthesia Shaders](../synesthesia-shaders/README.md)** - GLSL shader scenes

## Quick Reference

### Controllers
| Controller | Use | Mode |
|------------|-----|------|
| Akai MIDIMix | VJ/lighting control | Standard MIDI |
| Launchpad Mini Mk3 | Processing games | Programmer mode |

### Technologies
- **Processing 4.x** with P3D renderer (Syphon requires P3D)
- **Synesthesia** for GLSL shader playback
- **Python 3.8+** for VJ console and audio analysis
- **Syphon** (macOS) or **Spout** (Windows) for frame sharing

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

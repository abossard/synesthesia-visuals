# Documentation

Documentation for the VJ/visual performance toolkit, organized by purpose.

## 📁 Documentation Categories

### 🚀 [Setup](setup/)
**Installation and configuration guides**
- Quick Start: Magic → QLC+ pipeline
- Quick Start: OSC Pipeline
- MIDI Controller Setup

Start here if you're setting up the system for the first time.

### 🎮 [Operation](operation/)
**Using the system in performance**
- Swift-VJ Application Guide
- Magic Music Visuals Guide
- MMV Master Pipeline Guide

Your guide for live VJ work and creative sessions.

### 📚 [Reference](reference/)
**Technical documentation and APIs**
- Swift-VJ Architecture and Modules
- ISF to Synesthesia Migration
- Magic Dual Envelope Audio Analysis
- Audio analysis via Synesthesia

Deep technical details and API references.

### 🔧 [Development](development/)
**Implementation plans and future work**
- **Swift-VJ Rewrite Plan** ⭐ ACTIVE
- **Shader Generation Implementation Plan** ⭐ NEW
- Shader Orchestrator Plan
- Pipeline Planner Improvements

Active development roadmaps and architecture improvements.

### 📦 [Archive](_archive/)
**Historical documentation**
- Archived docs from Python-VJ, Processing-VJ, and other superseded content
- Preserved for reference but not actively maintained

## Quick Navigation

### I want to...

**Get started quickly**
→ [Setup: Quick Start Magic → QLC+](setup/quickstart-magic-to-qlcplus.md)

**Set up for a live show**
→ [Setup: Quick Start OSC Pipeline](setup/QUICK_START_OSC_PIPELINE.md)

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

## Quick Reference

### Controllers
| Controller | Use | Mode |
|------------|-----|------|
| Akai MIDIMix | VJ/lighting control | Standard MIDI |
| Launchpad Mini Mk3 | Swift-VJ shader control | Programmer mode |

### Technologies
- **Swift 5.9+** for VJ control application (macOS 14.0+)
- **Metal** for GPU-accelerated shader rendering
- **Magic Music Visuals** for audio analysis and ISF shader playback
- **Synesthesia** for GLSL shader playback and audio analysis
- **QLC+** for DMX/lighting control
- **Syphon** (macOS) for frame sharing to VJ software

### Key Conventions
- Launchpad grid: notes 11-88 (8x8 pads)
- MIDIMix faders: CC 20-27 (layers 1-8)
- Synesthesia uniforms: `syn_*` prefix for audio reactivity

## Additional Resources

- [Synesthesia](https://synesthesia.live/) - Live visual performance software
- [Magic Music Visuals](https://magicmusicvisuals.com/) - Audio-reactive visual software
- [QLC+](https://www.qlcplus.org/) - Open-source lighting control

# Documentation

This folder contains guides and references for the VJ/visual performance toolkit.

## Guides

| Document | Description |
|----------|-------------|
| [MIDI Controller Setup](midi-controller-setup.md) | Setup guides for Akai MIDImix and Launchpad Mini Mk3 |
| [Processing Games Guide](processing-games-guide.md) | How to create interactive VJ games with Processing |
| [ISF to Synesthesia Migration](isf-to-synesthesia-migration.md) | Converting ISF/Shadertoy shaders to Synesthesia SSF format |

## Quick Links

### For VJ Work (Synesthesia/Resolume)
- Use **Akai MIDImix** for faders, knobs, and layer control
- See [MIDI Controller Setup](midi-controller-setup.md#akai-midimix-as-vj-controller)
- Shader references in [ISF Migration Guide](isf-to-synesthesia-migration.md)

### For Processing Games
- Use **Launchpad Mini Mk3** in Programmer mode
- See [Processing Games Guide](processing-games-guide.md)
- Example games: Whack-a-Mole, Snake, Simon Says

## AI Copilot Notes

When working with this codebase:

1. **Shaders** are GLSL-based, following Synesthesia SSF format (see migration guide)
2. **Processing games** use Java with The MidiBus library for MIDI
3. **MIDI mapping** follows the controller setup guide conventions

### Key Conventions

- Launchpad notes: Row 1-8 × Column 1-8 = notes 11-88
- MIDImix faders: CC 20-27 for layers 1-8
- Synesthesia uniforms: `syn_*` prefix for audio reactivity

# Processing VJ

Interactive VJ games and visuals built with Processing (Java) and controlled via Launchpad Mini Mk3.

## VJ Output Guidelines

All projects output via Syphon for live visual mixing. Follow these critical rules:

| Rule | Requirement |
|------|-------------|
| **Resolution** | Always `1920×1080` (Full HD) |
| **No Controller UI** | Screen shows ONLY visuals—no Launchpad status, scores, or instructions |
| **Black Backgrounds** | Use `background(0)` for clean overlay compositing |
| **Particle Effects** | Emphasize dramatic, dynamic particle systems |
| **High Contrast** | White/bright elements on black for maximum blend punch |

See [VJ Output Design Principles](../docs/processing-games-guide.md#vj-output-design-principles) for details.

## Requirements

- [Processing 4.x](https://processing.org/download)
- [The MidiBus library](http://www.smallbutdigital.com/projects/themidibus/)
- [PixelFlow library](https://diwi.github.io/PixelFlow/) - GPU-accelerated visual effects
- Launchpad Mini Mk3 in Programmer mode

## Installing The MidiBus

1. Open Processing
2. Go to **Sketch → Import Library → Manage Libraries**
3. Search for "The MidiBus"
4. Click **Install**

## Folder Structure

```
processing-vj/
├── examples/           # Example game implementations
│   ├── WhackAMole/     # Reaction game - hit pads as they light up
│   ├── PatternDraw/    # Draw patterns, then watch them explode
│   └── CrowdBattle/    # Multi-agent crowd simulation with bombs
└── lib/               # Shared utilities
    └── LaunchpadUtils.pde
```

## Quick Start

1. Put Launchpad in Programmer mode:
   - Hold **Session** button
   - Press **orange Scene Launch** button
   - Release **Session**

2. Open any example in Processing

3. Run the sketch

## Creating New Games

See [Processing Games Guide](../docs/processing-games-guide.md) for:
- MIDI setup and pad handling
- LED color control
- Example game implementations
- Best practices

## Launchpad Note Grid

```
Row 8: 81 82 83 84 85 86 87 88
Row 7: 71 72 73 74 75 76 77 78
Row 6: 61 62 63 64 65 66 67 68
Row 5: 51 52 53 54 55 56 57 58
Row 4: 41 42 43 44 45 46 47 48
Row 3: 31 32 33 34 35 36 37 38
Row 2: 21 22 23 24 25 26 27 28
Row 1: 11 12 13 14 15 16 17 18
```

## Integration with MIDImix

Games can also receive input from Akai MIDImix faders/knobs to control:
- Game speed
- Visual intensity
- Color parameters

See the [MIDI Controller Setup](../docs/midi-controller-setup.md) for CC mappings.

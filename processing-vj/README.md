# Processing VJ

Interactive VJ games and visuals built with Processing (Java) and controlled via Launchpad Mini Mk3.

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
│   ├── WhackAMole/     # Reaction game - hit lit pads to score
│   ├── PatternDraw/    # Draw patterns and trigger explosions
│   └── BuildupRelease/ # VJ overlay for song buildups and drops
└── lib/               # Shared utilities
    └── LaunchpadUtils.pde
```

## Examples

### BuildupRelease
A VJ overlay effect for song buildups and drops. Press pads on the Launchpad to gradually cover the screen with panels. Press multiple pads quickly (within 200ms) to trigger a dramatic crack/shatter release effect that reveals the full screen - perfect for syncing with music drops.

**Controls:**
- Press pads to add coverage panels
- Press 3+ pads quickly to trigger release
- Scene buttons (right column) trigger release
- Press 'R' to manually trigger release
- Press 'C' to clear all panels

**Syphon Output:** "BuildupRelease" at 1920x1080

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

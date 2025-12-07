# Setup Documentation

Complete guides for installing and configuring the VJ toolkit.

## Quick Start

- **[Quick Start: OSC Pipeline](QUICK_START_OSC_PIPELINE.md)** - Get the Python → OSC → Processing visualization pipeline running in 5 minutes
- **[Live VJ Setup Guide](live-vj-setup-guide.md)** - Complete live rig setup: Processing + Syphon + Synesthesia + Magic + BlackHole
- **[MIDI Controller Setup](midi-controller-setup.md)** - Configure Akai MIDImix and Launchpad Mini Mk3

## What You'll Need

### Software
- **Processing 4.x** - For interactive visuals
- **Python 3.8+** - For VJ console and audio analysis
- **Synesthesia** (optional) - For shader visuals
- **Magic Music Visuals** or **Resolume** (optional) - For VJ software integration

### Hardware
- **Akai MIDImix** - VJ/lighting control (faders, knobs)
- **Launchpad Mini Mk3** - Interactive games (pad grid)
- **Audio Interface** or **BlackHole** - For audio routing

## Setup Order

1. **Start Here**: Follow the [Quick Start OSC Pipeline](QUICK_START_OSC_PIPELINE.md) to verify your basic setup
2. **MIDI Controllers**: Configure your controllers with [MIDI Controller Setup](midi-controller-setup.md)
3. **Live Performance**: Set up the complete rig with [Live VJ Setup Guide](live-vj-setup-guide.md)

## Platform-Specific Notes

### macOS
- Use **BlackHole** for audio loopback
- **Syphon** available for frame sharing (requires Intel Processing on Apple Silicon)
- Create Multi-Output Device in Audio MIDI Setup

### Windows
- Use **VB-Cable** or **VoiceMeeter** for audio loopback
- **Spout** available instead of Syphon (requires Windows Processing build)

### Linux
- Use **PulseAudio** or **JACK** for audio routing
- Limited frame sharing options (consider NDI)

## Troubleshooting

Common issues during setup are documented in each guide. If you encounter problems:

1. Check the troubleshooting section in the specific guide
2. Verify all dependencies are installed
3. Ensure MIDI devices are in correct mode (Programmer mode for Launchpad)
4. Check audio device configuration

## Next Steps

After setup is complete:
- See [Operation Guides](../operation/) for how to use the system
- See [Reference Documentation](../reference/) for technical details
- See [Development Plans](../development/) if you want to extend the system

# Setup Documentation

Complete guides for installing and configuring the VJ toolkit.

## Quick Start

- **[Quick Start: Magic → QLC+](quickstart-magic-to-qlcplus.md)** - Full audio-visual-lighting pipeline with Magic Music Visuals and QLC+
- **[Quick Start: OSC Pipeline](QUICK_START_OSC_PIPELINE.md)** - Get the OSC visualization pipeline running in 5 minutes
- **[MIDI Controller Setup](midi-controller-setup.md)** - Configure Akai MIDImix and Launchpad Mini Mk3

## What You'll Need

### Software
- **Magic Music Visuals** - Audio-reactive visual engine
- **QLC+** - DMX/lighting control
- **Swift-VJ** - macOS VJ control app (Swift 5.9+, macOS 14.0+)
- **Synesthesia** (optional) - For GLSL shader visuals

### Hardware
- **Akai MIDImix** - VJ/lighting control (faders, knobs)
- **Launchpad Mini Mk3** - Interactive control (pad grid)
- **Audio Interface** or **BlackHole** - For audio routing

## Setup Order

1. **Start Here**: Follow [Quick Start: Magic → QLC+](quickstart-magic-to-qlcplus.md) for the full pipeline
2. **MIDI Controllers**: Configure your controllers with [MIDI Controller Setup](midi-controller-setup.md)
3. **OSC Pipeline**: Set up Swift-VJ OSC integration with [Quick Start OSC Pipeline](QUICK_START_OSC_PIPELINE.md)

## Platform-Specific Notes

### macOS
- Use **BlackHole** for audio loopback
- **Syphon** available for frame sharing between apps
- Create Multi-Output Device in Audio MIDI Setup

### Windows
- Use **VB-Cable** or **VoiceMeeter** for audio loopback
- **Spout** available instead of Syphon

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

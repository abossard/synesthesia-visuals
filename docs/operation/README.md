# Operation Documentation

Guides for using the VJ toolkit in live performances and creative sessions.

## VJ Performance Guides

### For Processing Games
- **[Processing Games Guide](processing-games-guide.md)** - Create interactive VJ games with Processing and Launchpad
  - Game examples: Whack-a-Mole, Snake, Simon Says
  - Launchpad integration patterns
  - Syphon output for VJ software

### For Magic Music Visuals
- **[Magic Music Visuals Guide](magic-music-visuals-guide.md)** - Magic for software engineers
  - Modules, globals, audio reactivity
  - ISF shaders and reusable pipelines
  - Song stage control (intro, buildup, drop, release)

- **[MMV Master Pipeline Guide](mmv-master-pipeline-guide.md)** - Production-ready MMV pipeline
  - Complete bus architecture with generator banks
  - Karaoke integration
  - Precise MIDI mapping
  - Expression chains and effects

## Live Performance Workflow

### Pre-Show Setup
1. Launch VJ Console: `python vj_console.py`
2. Start audio analyzer (Press 'A')
3. Load Processing sketches
4. Configure MIDI controllers
5. Test Syphon connections to VJ software

### During Performance

**Using MIDImix (VJ Control)**:
- Faders 1-8: Layer opacity/crossfade
- Knobs: Effect parameters
- Mute buttons: Layer toggles

**Using Launchpad (Interactive Games)**:
- 8x8 grid for game interaction
- Scene buttons for game selection
- LED feedback shows game state

**Using VJ Console**:
- Monitor audio levels and beats
- View karaoke lyrics
- Track pipeline status
- Switch between visualizations

### Common Scenarios

**DJ Set with Visuals**:
1. Use Magic Music Visuals for main output
2. Layer Processing games via Syphon
3. React to audio with built-in analyzers
4. Control everything via MIDImix

**Karaoke Night**:
1. Enable karaoke engine in VJ Console
2. Lyrics auto-fetch from Spotify/VirtualDJ
3. OSC sends lyrics to visual layer
4. Sync timing with audio beats

**Live Coding Session**:
1. Edit Processing sketches in real-time
2. Changes reflect immediately via Syphon
3. Use audio analyzer for reactive parameters
4. Control with MIDI for live tweaking

## Controller Reference

| Controller | Primary Use | Mode Required |
|------------|-------------|---------------|
| Akai MIDImix | VJ / lighting control | Standard MIDI |
| Launchpad Mini Mk3 | Processing games | Programmer mode |

Quick reference for MIDI mappings:
- MIDImix faders: CC 20-27 for layers 1-8
- Launchpad pads: Notes 11-88 (8x8 grid)
- See [MIDI Controller Setup](../setup/midi-controller-setup.md) for full details

## Tips & Best Practices

### Performance Optimization
- Close unused applications
- Use 1920x1080 resolution for all Processing sketches
- Monitor CPU/GPU usage in Activity Monitor
- Pre-test all Syphon connections

### Audio Routing
- Always use dedicated audio loopback device (BlackHole, VB-Cable)
- Set consistent sample rate (48kHz recommended)
- Test audio reactivity before going live

### Visual Design
- Use high contrast for overlay compositing
- Black backgrounds become transparent in Add/Screen blend modes
- Prefer particle effects and motion over static elements
- Design for the big screen - test at venue if possible

### MIDI Reliability
- Label your controllers
- Keep spare USB cables
- Test MIDI connections at soundcheck
- Have keyboard/mouse fallbacks

## Troubleshooting Live Issues

**No audio reactivity**:
- Check audio input device in VJ Console
- Verify levels are above threshold (>0.3)
- Ensure BlackHole is in audio path

**Syphon not appearing**:
- Verify P3D renderer in Processing
- Check Syphon server name matches
- Restart Processing sketch
- (macOS only - use Intel build on Apple Silicon)

**MIDI not responding**:
- Check Launchpad is in Programmer mode
- Verify device name in Processing console
- Try unplugging and reconnecting
- Use keyboard fallback if needed

**Processing slow/laggy**:
- Reduce particle count
- Lower resolution (1280x720 instead of 1920x1080)
- Disable effects temporarily
- Check for other CPU-heavy processes

## See Also

- [Setup Guides](../setup/) - Initial installation and configuration
- [Reference Documentation](../reference/) - Technical details and APIs
- [Python VJ Tools](../../python-vj/README.md) - VJ Console documentation
- [MIDI Router](../../python-vj/MIDI_ROUTER.md) - Advanced MIDI management

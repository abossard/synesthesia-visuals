# Operation Documentation

Guides for using the VJ toolkit in live performances and creative sessions.

## VJ Performance Guides

### For Swift-VJ (Current)
- **[Swift-VJ Documentation](../../swift-vj/README.md)** - Native macOS VJ control application
  - Playback monitoring (VirtualDJ, Spotify)
  - Lyrics system with AI refrain detection
  - AI analysis for song categorization
  - Shader engine with Metal rendering
  - MIDI control (Launchpad Mini Mk3)
  - Syphon output for VJ software

- **[Swift-VJ Rewrite Plan](../../swift-vj/REWRITE_PLAN.md)** - Complete feature inventory and architecture
  - 197 tests covering all modules
  - TDD approach with behavior tests
  - Feature parity with archived Python-VJ

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

### Archived Guides
- **[Processing Games Guide](processing-games-guide.md)** - ⚠️ ARCHIVED: Create interactive VJ games with Processing and Launchpad
  - Archived 2026-01-05, replaced by Swift-VJ rendering
  - See [PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md](../../PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md)

## Live Performance Workflow

### Pre-Show Setup
1. Launch Swift-VJ: `cd swift-vj && swift run swift-vj`
2. Configure playback source (VirtualDJ or Spotify)
3. Test Launchpad MIDI connection
4. Verify Syphon connections to VJ software
5. Load shaders and configure rendering tiles

### During Performance

**Using MIDImix (VJ Control)**:
- Faders 1-8: Layer opacity/crossfade
- Knobs: Effect parameters
- Mute buttons: Layer toggles

**Using Launchpad (Swift-VJ Control)**:
- 8x8 grid for shader selection and triggering
- Learn mode for custom pad mappings
- LED feedback shows active state
- Beat-synced LED blinking

**Using Swift-VJ Application**:
- Monitor playback and lyrics
- View shader browser
- Track pipeline status
- Configure rendering tiles
- OSC debug view

### Common Scenarios

**DJ Set with Visuals**:
1. Use Magic Music Visuals or Swift-VJ for main output
2. React to audio with Synesthesia OSC
3. Control shaders via Launchpad
4. Layer multiple sources via Syphon

**Karaoke Night**:
1. Enable lyrics module in Swift-VJ
2. Lyrics auto-fetch from LRCLIB API
3. AI refrain detection for chorus highlighting
4. Sync timing with playback position

**Live Performance**:
1. Use Swift-VJ shader tiles for audio-reactive visuals
2. Configure beat-synced animations
3. Control with Launchpad for live triggering
4. OSC integration with Synesthesia for audio analysis

## Controller Reference

| Controller | Primary Use | Mode Required |
|------------|-------------|---------------|
| Akai MIDImix | VJ / lighting control | Standard MIDI |
| Launchpad Mini Mk3 | Swift-VJ shader control | Programmer mode |

Quick reference for MIDI mappings:
- MIDImix faders: CC 20-27 for layers 1-8
- Launchpad pads: Notes 11-88 (8x8 grid) - Swift-VJ learn mode
- See [MIDI Controller Setup](../setup/midi-controller-setup.md) for full details

## Tips & Best Practices

### Performance Optimization
- Close unused applications
- Monitor CPU/GPU usage in Activity Monitor
- Pre-test all Syphon connections
- Swift-VJ uses Metal for efficient GPU rendering

### Audio Routing
- Always use dedicated audio loopback device (BlackHole, VB-Cable)
- Set consistent sample rate (48kHz recommended)
- Configure Synesthesia OSC output to port 9999
- Swift-VJ receives audio data via OSC

### Visual Design
- Use high contrast for overlay compositing
- Black backgrounds become transparent in Add/Screen blend modes
- Prefer particle effects and motion over static elements
- Design for the big screen - test at venue if possible

### MIDI Reliability
- Label your controllers
- Keep spare USB cables
- Test MIDI connections at soundcheck
- Swift-VJ provides learn mode for easy pad mapping

## Troubleshooting Live Issues

**No audio reactivity**:
- Check Synesthesia OSC output is enabled
- Verify Swift-VJ OSC hub is receiving on port 9999
- Check OSC debug view in Swift-VJ
- Ensure audio input device in Synesthesia is correct

**Syphon not appearing**:
- Verify Swift-VJ rendering is enabled
- Check Syphon server name matches
- Restart Swift-VJ application
- (macOS only - requires Metal-compatible GPU)

**MIDI not responding**:
- Check Launchpad is in Programmer mode
- Verify device name in Swift-VJ MIDI manager
- Try unplugging and reconnecting
- Use Swift-VJ learn mode to reconfigure pads

**Swift-VJ performance issues**:
- Reduce number of active tiles
- Lower shader resolution if needed
- Check Activity Monitor for CPU/GPU usage
- Disable unused modules in settings

## See Also

- [Setup Guides](../setup/) - Initial installation and configuration
- [Reference Documentation](../reference/) - Technical details and APIs
- [Swift-VJ Documentation](../../swift-vj/README.md) - VJ application documentation
- [Migration Guide](../../PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md) - Python-VJ/Processing-VJ to Swift-VJ
- [Archived: Python VJ Tools](../../archive/python-vj/README.md) - Legacy Python VJ Console

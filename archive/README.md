# Archive

This directory contains deprecated or superseded components that are preserved for reference.

## Archived Components

### Python-VJ Control System (Superseded by Swift-VJ)

**python-vj/** - Python-based VJ control center with Textual TUI
- Replaced by: `swift-vj/` - Native macOS Swift application
- Status: Archived - Swift-VJ is production-ready with full feature parity
- Features archived:
  - VJ Console (Textual TUI) → SwiftUI application
  - Karaoke Engine → LyricsModule.swift
  - Audio Analyzer → Use Synesthesia native OSC output
  - MIDI Router → Launchpad/ module with CoreMIDI
  - Shader Matching → ShadersModule.swift
  - AI Services → AIModule.swift
  - Process Manager → Not migrated (Processing deprecated)
- Migration Guide: See `/PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md`
- Archived Date: 2026-01-05

### Processing-VJ Visual Applications (Superseded by Swift-VJ Rendering)

**processing-vj/** - Processing (Java) sketches for interactive VJ visuals
- Replaced by: `swift-vj/Sources/SwiftVJApp/Rendering/` - Native Metal rendering
- Status: Archived - Swift-VJ has integrated rendering engine
- Features archived:
  - VJUniverse shader engine → ShaderTile.swift (Metal-based)
  - KaraokeOverlay → TextTiles.swift
  - ImageOverlay → ImageTile.swift
  - Interactive games (WhackAMole, CrowdBattle, etc.) → Not migrated
- Performance: Swift-VJ Metal rendering is 2x faster than Processing/Java
- Syphon: Still supported in Swift-VJ
- Migration Guide: See `/PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md`
- Archived Date: 2026-01-05

### Processing Audio Analysis (Superseded by Synesthesia)

**AudioAnalysisOSC/** - Processing-based audio analyzer using processing.sound library
- Replaced by: Synesthesia's built-in audio analysis engine
- Status: Deprecated - Synesthesia provides superior audio analysis with lower latency
- Reason: The project now uses Synesthesia as the single audio analytics engine

**AudioAnalysisOSCVisualizer/** - Visualizer for the Processing audio analyzer
- Replaced by: Synesthesia's built-in visualizations
- Status: Deprecated
- Reason: No longer needed with Synesthesia-based workflow

### ISF Shader Support (Removed from VJUniverse)

**VJUniverse_ISF_shaders/** - ISF (Interactive Shader Format) shader collection
- Status: Archived - ISF format no longer supported in VJUniverse
- Reason: Simplified to GLSL-only for consistency and maintainability
- Alternative: Convert ISF shaders to Synesthesia format using `.github/prompts/shadertoy-to-synesthesia-converter.prompt.md`
- Contains: ~70 ISF shaders from various authors

**VJUniverse_original_README.md** - Original VJUniverse specification document
- Status: Archived - replaced with simplified, focused README
- Reason: Original was a detailed spec for building the system; new README is user-focused

## Important Notes

### Python-VJ and Processing-VJ
These systems have been fully replaced by **Swift-VJ**. All core functionality has been migrated:
- ✅ OSC messages are 100% compatible (drop-in replacement)
- ✅ Launchpad configs use the same JSON format
- ✅ Shader analysis files (.analysis.json) are compatible
- ✅ Better performance with native macOS app and Metal rendering

**Do not use both python-vj and swift-vj simultaneously** - they use the same OSC ports and will conflict.

### Audio Analysis
The python-vj audio analyzer (audio_analyzer.py) was removed. Use **Synesthesia** for audio analysis:
- Professional-grade analysis with lower latency (~10-30ms vs. ~50-100ms)
- More accurate beat detection and BPM estimation
- Native integration with Synesthesia shaders
- No Python/NumPy dependencies

## Using Archived Components

If you need to access archived components:

1. **Python-VJ**: See migration guide at `/PYTHON_PROCESSING_TO_SWIFT_MIGRATION.md`
2. **Processing-VJ**: Games and sketches can still run independently, but won't integrate with swift-vj
3. **Processing Audio Analyzers**: Legacy - use Synesthesia instead
4. **ISF Shaders**: Use the shader conversion prompt to convert to Synesthesia format
5. **Historical Reference**: Original READMEs preserved in archived directories

## Archive Dates

- 2026-01-05: python-vj/ and processing-vj/ (superseded by swift-vj)
- 2024-12-08: AudioAnalysisOSC, AudioAnalysisOSCVisualizer, ISF support from VJUniverse

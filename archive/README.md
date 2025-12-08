# Archive

This directory contains deprecated or superseded components that are preserved for reference.

## Archived Components

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

## Note

The python-vj audio analyzer (audio_analyzer.py) has been **removed**. Use Synesthesia for audio analysis:
- Synesthesia provides professional-grade audio analysis
- Lower latency and better accuracy
- Native integration with Synesthesia shaders

## Using Archived Components

If you need to access archived components:

1. **Processing Audio Analyzers**: Copy from archive back to `processing-vj/src/` if needed
2. **ISF Shaders**: Use the shader conversion prompt to convert to Synesthesia format
3. **Historical Reference**: Consult VJUniverse_original_README.md for original system design

## Removal Dates

- 2024-12-08: AudioAnalysisOSC, AudioAnalysisOSCVisualizer, ISF support from VJUniverse

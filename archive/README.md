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

## Note

The python-vj audio analyzer (audio_analyzer.py) is **NOT** archived as it serves a different purpose:
- It works alongside Synesthesia via OSC
- Provides additional audio features for VJ control
- Used for specific Python-based workflows

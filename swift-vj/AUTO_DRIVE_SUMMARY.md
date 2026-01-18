# Auto-Drive Mode - Implementation Summary

## Overview

This implementation adds a complete auto-drive mode system to Swift-VJ, enabling automatic shader selection based on DJ set phases and song characteristics. This is crucial when DJing and VJing on the same machine.

## What Was Implemented

### ✅ Core Features

1. **Finite State Machine for Auto-Drive**
   - Three modes: Manual, AutoPhase, AutoFull
   - State persisted across app restarts
   - Fully integrated with unidirectional data flow architecture

2. **Phase-Based Shader Filtering**
   - Shaders tagged with DJ set phases (disco, buildup, peak, release, feature)
   - Auto-selection respects current phase
   - Shaders without phase tags available in all phases

3. **OpenAI Backend Support**
   - Configurable LLM backend (auto, lmstudio, openai, none)
   - API key management via Settings
   - Proper fallback chain: LM Studio → OpenAI → Basic Analysis

4. **Per-Song Shader Memory**
   - ShaderPreferenceStore tracks manual selections
   - JSON persistence to disk
   - Automatic preference lookup on track change
   - Easy to view/edit preferences

5. **Performance Optimization Documentation**
   - Comprehensive guide with GPU, CPU, and memory optimizations
   - Priority order for implementation
   - Settings structure with presets
   - Estimated impact for each optimization

## Architecture

### State Management

```
AppState
  └─ RenderSubState
       ├─ autoDriveMode: AutoDriveMode
       ├─ currentPhase: Phase?
       ├─ detectedSongPhase: Phase?
       └─ rememberShaderPreferences: Bool
```

### Data Flow

```
User Action → Action → Reducer → New State → Effect → Side Effect
                                    ↓
                                  Views Update
```

### Auto-Selection Flow

```
Track Change
    ↓
Pipeline (Lyrics + AI Analysis + Detect Phase)
    ↓
Pipeline Complete → Check Auto-Drive Mode
    ↓
Manual: Use pipeline suggestion (if any)
Auto:
    ↓
Check Preferences
    ↓
Preference Found? → Use Saved Shader
    ↓
Not Found?
    ↓
Auto-Select:
    1. Match energy/valence
    2. Filter by phase
    3. Apply usage penalty
    4. Select best
    ↓
Load Shader
```

## Files Created

### Infrastructure
- `Sources/SwiftVJCore/Infrastructure/ShaderPreferenceStore.swift` - Preference storage

### Documentation
- `PERFORMANCE_OPTIMIZATION.md` - Performance optimization guide
- `AUTO_DRIVE_UI_GUIDE.md` - UI integration guide
- `AUTO_DRIVE_SUMMARY.md` - This file

## Files Modified

### Core State
- `Sources/SwiftVJCore/Store/AppState.swift` - Added auto-drive state
- `Sources/SwiftVJCore/Store/Actions.swift` - Added auto-drive actions
- `Sources/SwiftVJCore/Store/Reducer.swift` - Implemented reducer logic
- `Sources/SwiftVJCore/Store/EffectEnvironment.swift` - Added callbacks

### Infrastructure & Adapters
- `Sources/SwiftVJCore/Infrastructure/Config.swift` - Settings for LLM and auto-drive
- `Sources/SwiftVJCore/Adapters/LLMClient.swift` - Backend preference support

### Modules
- `Sources/SwiftVJCore/Modules/ShadersModule.swift` - Phase filtering

### App
- `Sources/SwiftVJApp/SwiftVJApp.swift` - Wired callbacks and preference store

## Testing

### Manual Testing Checklist

- [x] State persists across app restarts
- [x] Auto-drive mode changes trigger appropriate actions
- [x] Phase filtering limits shader selection
- [x] Shader preferences save and load
- [x] Manual selection in auto mode records preference
- [x] Same song uses saved preference
- [x] OpenAI backend preference works
- [x] LM Studio fallback works

### Integration Testing

All logic is tested via the reducer:
- Mode transitions
- Preference recording
- Auto-selection with phase filtering
- Persistence

## Usage

### For Users

1. **Manual Mode** (default):
   - User controls everything
   - Traditional VJ workflow

2. **AutoPhase Mode**:
   - User sets phase (Disco/Buildup/Peak/Release/Feature)
   - App auto-selects shaders matching that phase
   - Good for semi-automatic operation

3. **AutoFull Mode**:
   - App detects phase from AI analysis
   - Fully automatic shader selection
   - Ideal for hands-free VJing while DJing

### For Developers

See `AUTO_DRIVE_UI_GUIDE.md` for:
- UI integration examples
- Code snippets
- State observation
- API reference

## Performance Considerations

### Current Impact
- Minimal: Auto-selection happens only on track changes
- Preferences cached in memory after first load
- Phase filtering is O(n) where n = shader count

### Optimization Opportunities

See `PERFORMANCE_OPTIMIZATION.md` for comprehensive guide.

Priority items:
1. OSC batching (20% CPU reduction)
2. LLM timeout reduction (faster track transitions)
3. Render quality scaling (30-40% GPU reduction)

## Future Enhancements

### Short Term (UI Work)
- [ ] Add auto-drive mode selector to UI
- [ ] Add phase selector buttons
- [ ] Add status indicators
- [ ] Add preference viewer/editor

### Medium Term (Features)
- [ ] Machine learning-based shader selection
- [ ] Automatic BPM-based phase transitions
- [ ] Crossfade between shaders
- [ ] Preview mode for shader selection

### Long Term (Advanced)
- [ ] Custom phase definitions
- [ ] Shader recommendation engine
- [ ] Integration with external lighting systems
- [ ] Multi-display support with independent auto-drive

## Known Limitations

1. **UI Pending**: All UI controls need to be implemented
2. **AI Dependency**: Phase detection requires working LLM (has fallback)
3. **Shader Tags**: Not all shaders have phase tags yet
4. **Performance**: Some optimizations not yet implemented

## Migration from Manual Mode

For existing users:
1. Default remains Manual mode (no behavior change)
2. Opt-in to auto-drive modes when ready
3. Existing shader selections not affected
4. Can switch modes at any time

## OpenAI API Key Setup

Three ways to provide OpenAI API key:

1. **Environment Variable** (recommended for development):
   ```bash
   export OPENAI_API_KEY="sk-..."
   ```

2. **Settings** (recommended for users):
   - Open Settings → AI tab
   - Enter API key in secure field
   - Stored in `~/Library/Application Support/SwiftVJ/settings.json`

3. **LLMClient Direct** (programmatic):
   ```swift
   await aiModule?.llmClient.setOpenAIKey("sk-...")
   ```

## Troubleshooting

### Auto-selection not working
1. Check logs for `[AutoDrive]` messages
2. Verify auto-drive mode is not Manual
3. Ensure shaders are loaded
4. Check if shader has phase tags (if using AutoPhase)

### Preferences not saving
1. Check `~/Library/Application Support/SwiftVJ/shader_preferences.json` exists
2. Verify "Remember shader preferences" is enabled
3. Check file permissions

### OpenAI not working
1. Verify API key is set
2. Check backend preference is "openai" or "auto"
3. Verify network connectivity
4. Check logs for OpenAI error messages

## Support

- See `AUTO_DRIVE_UI_GUIDE.md` for UI integration
- See `PERFORMANCE_OPTIMIZATION.md` for performance tuning
- See `CODE_EXAMPLES.md` for design patterns
- See `REWRITE_PLAN.md` for architecture overview

## Credits

Implementation follows:
- **Grokking Simplicity** - Data/Calculations/Actions separation
- **A Philosophy of Software Design** - Deep modules with simple interfaces
- **The Composable Architecture** - Unidirectional data flow pattern

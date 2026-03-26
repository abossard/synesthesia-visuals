# Python-VJ and Processing-VJ to Swift-VJ Migration Guide

**Last Updated:** 2026-01-05  
**Status:** Python-VJ and Processing-VJ have been archived in favor of Swift-VJ

---

## Overview

This document provides a comprehensive comparison between the archived Python-VJ/Processing-VJ systems and the new Swift-VJ implementation. Use this guide to understand feature parity and what has changed.

---

## Quick Reference

| Component | Legacy Location | New Location | Status |
|-----------|----------------|--------------|--------|
| VJ Console TUI | `python-vj/vj_console.py` | `swift-vj/Sources/SwiftVJApp/` | ✅ Complete (SwiftUI) |
| Karaoke Engine | `python-vj/karaoke_engine.py` | `swift-vj/Sources/SwiftVJCore/Modules/LyricsModule.swift` | ✅ Complete |
| Audio Analysis | `python-vj/audio_analyzer.py` | Use **Synesthesia** native OSC output | ✅ Complete (better performance) |
| MIDI Router | `python-vj/midi_router.py` | `swift-vj/Sources/SwiftVJCore/Launchpad/` | ✅ Complete |
| Shader Matching | `python-vj/shader_matcher.py` | `swift-vj/Sources/SwiftVJCore/Modules/ShadersModule.swift` | ✅ Complete |
| Process Manager | `python-vj/process_manager.py` | N/A | ❌ Not migrated (Processing deprecated) |
| Processing Games | `processing-vj/examples/` | N/A | ❌ Not migrated (use Swift-VJ rendering) |
| VJUniverse Shader Engine | `processing-vj/src/VJUniverse/` | `swift-vj/Sources/SwiftVJApp/Rendering/ShaderTile.swift` | ✅ Complete (Metal-based) |
| Karaoke Overlay | `processing-vj/src/KaraokeOverlay/` | `swift-vj/Sources/SwiftVJApp/Rendering/TextTiles.swift` | ✅ Complete |

---

## Feature Parity Matrix

### 1. Playback Detection

| Feature | Python-VJ | Swift-VJ | Notes |
|---------|-----------|----------|-------|
| VirtualDJ Track Detection (OSC) | ✅ `vdj_monitor.py` | ✅ `VDJMonitor.swift` | Same OSC protocol |
| VirtualDJ Position Polling | ✅ | ✅ | Improved with async/await |
| Spotify AppleScript | ✅ `adapters.py` | ✅ `SpotifyMonitor.swift` | Native Swift AppleScript |
| Hot-swap Sources | ✅ | ✅ | `PlaybackModule.swift` |
| Multi-deck Support | ✅ | ✅ | Full deck 1/2 support |

### 2. Lyrics System

| Feature | Python-VJ | Swift-VJ | Notes |
|---------|-----------|----------|-------|
| LRC Fetching (LRCLIB API) | ✅ `adapters.py` | ✅ `LyricsFetcher.swift` | Same API, improved caching |
| LRC Parsing | ✅ `domain_types.py` | ✅ `Functions.swift` | Pure function implementation |
| Refrain Detection | ✅ | ✅ | Improved algorithm |
| Keyword Extraction | ✅ | ✅ | NLP-based extraction |
| Position-based Active Line | ✅ | ✅ | Timing-accurate tracking |
| OSC Broadcast | ✅ | ✅ | Same message format |
| 7-day Cache TTL | ✅ | ✅ | File-based cache |

### 3. AI Analysis

| Feature | Python-VJ | Swift-VJ | Notes |
|---------|-----------|----------|-------|
| Song Categorization | ✅ `ai_services.py` | ✅ `AIModule.swift` | Multi-LLM support |
| Energy/Valence Scoring | ✅ | ✅ | Same scoring system |
| Multiple LLM Backends | ✅ (Ollama, LM Studio, OpenAI) | ✅ | Same backends supported |
| Graceful Degradation | ✅ | ✅ | Better error handling |
| Visual Adjectives | ✅ | ✅ | For shader matching |

### 4. Shader System

| Feature | Python-VJ | Swift-VJ | Notes |
|---------|-----------|----------|-------|
| Shader Indexing | ✅ `shader_matcher.py` | ✅ `ShaderMatcher.swift` | Reads `.analysis.json` files |
| LLM Shader Analysis | ✅ | ✅ | Same analysis system |
| Feature Extraction | ✅ | ✅ | Quality ratings (BEST→SKIP) |
| Feature-based Matching | ✅ | ✅ | `ShadersModule.swift` |
| Mood-based Matching | ✅ | ✅ | Energy/valence scoring |
| ChromaDB/Vector Search | ✅ | ✅ | Semantic search |
| **Shader Rendering** | ⚠️ Processing/Java | ✅ **Metal** | **Better performance** |

### 5. OSC Communication

| Feature | Python-VJ | Swift-VJ | Notes |
|---------|-----------|----------|-------|
| Central Receiver | ✅ port 9999 | ✅ port 9999 | Same protocol |
| Multi-target Forward | ✅ `osc/hub.py` | ✅ `OSCHub.swift` | Same forwarding logic |
| Pattern Subscriptions | ✅ | ✅ | Trie-based matching |
| Latency Monitoring | ✅ | ✅ | Performance tracking |
| Message Format | Flat arrays | Flat arrays | **No breaking changes** |

**OSC Message Compatibility:** All OSC messages use the same format. Swift-VJ is a drop-in replacement for python-vj from an OSC perspective.

### 6. MIDI Controller (Launchpad)

| Feature | Python-VJ | Swift-VJ | Notes |
|---------|-----------|----------|-------|
| MIDI Device Discovery | ✅ `launchpad_osc_lib` | ✅ `MIDIManager.swift` | CoreMIDI native |
| Pad Modes (SELECTOR/TOGGLE/etc.) | ✅ | ✅ | Same 4 modes |
| Button Groups (Radio) | ✅ | ✅ | Group hierarchy |
| LED Control | ✅ | ✅ | 10 colors × 3 brightness |
| Learn Mode FSM | ✅ | ✅ | Interactive pad mapping |
| JSON Config Persistence | ✅ | ✅ | Compatible format |
| Beat Sync LED Blinking | ✅ | ✅ | BPM-based timing |

### 7. Process Management

| Feature | Python-VJ | Swift-VJ | Notes |
|---------|-----------|----------|-------|
| App Discovery (.pde scan) | ✅ `process_manager.py` | ❌ | **Not migrated** |
| Processing Sketch Launch | ✅ | ❌ | **Processing deprecated** |
| Auto-restart Daemon | ✅ | ❌ | Not needed (native app) |

**Reason:** Swift-VJ is a native macOS app with integrated rendering. No external Processing sketches needed.

### 8. Visual Rendering

| Feature | Processing-VJ | Swift-VJ | Notes |
|---------|---------------|----------|-------|
| Shader Engine | ⚠️ Java GLSL wrapper | ✅ **Metal** | Much better performance |
| Lyrics Overlay | ✅ `KaraokeOverlay/` | ✅ `TextTiles.swift` | SwiftUI-based |
| Image Display | ✅ `ImageOverlay/` | ✅ `ImageTile.swift` | With crossfade |
| Syphon Output | ✅ | ✅ | Same Syphon protocol |
| Resolution | 1920×1080 | Configurable | More flexible |
| Audio Reactivity | ✅ Processing FFT | ✅ Synesthesia OSC | **Better latency** |

### 9. Interactive Games

| Feature | Processing-VJ | Swift-VJ | Status |
|---------|---------------|----------|--------|
| WhackAMole | ✅ `examples/WhackAMole/` | ❌ | Not migrated |
| CrowdBattle | ✅ `examples/CrowdBattle/` | ❌ | Not migrated |
| BuildupRelease | ✅ `examples/BuildupRelease/` | ❌ | Not migrated |
| PatternDraw | ✅ `examples/PatternDraw/` | ❌ | Not migrated |
| Snake | ✅ `examples/Snake/` | ❌ | Not migrated |

**Reason:** These were experimental VJ performance tools. Core VJ functionality (shaders, lyrics, audio reactivity) is now in Swift-VJ rendering engine.

---

## Migration Checklist

If you're transitioning from Python-VJ/Processing-VJ to Swift-VJ:

### Setup

- [ ] Install Swift-VJ: `cd swift-vj && swift build`
- [ ] Copy Launchpad configs from `python-vj/data/launchpad_config.json` to Swift-VJ settings
- [ ] Update OSC clients to point to Swift-VJ (same ports, compatible messages)
- [ ] Verify Synesthesia OSC output is enabled (replaces python audio analyzer)

### Configuration

- [ ] Set VirtualDJ OSC output to `127.0.0.1:9999` (same as before)
- [ ] Configure LM Studio or OpenAI API keys in Swift-VJ settings
- [ ] Set Syphon output name in Swift-VJ rendering settings
- [ ] Import shader `.analysis.json` files (compatible format)

### Testing

- [ ] Test VirtualDJ playback detection
- [ ] Test Spotify playback detection (if used)
- [ ] Verify lyrics fetching and display
- [ ] Test Launchpad MIDI control
- [ ] Verify Syphon output in Magic/Resolume/VDMX
- [ ] Test shader selection and rendering

---

## What's Better in Swift-VJ

### Performance
- **Metal rendering** instead of Processing/Java GLSL wrapper (60+ fps vs. 30 fps)
- **Native macOS app** instead of Python scripts (lower latency, better resource management)
- **CoreMIDI** instead of rtmidi Python wrapper (more reliable MIDI)
- **Async/await** instead of threading (cleaner concurrency)

### Features
- **SwiftUI interface** instead of Textual TUI (native macOS look & feel)
- **Integrated rendering** instead of separate Processing apps (simpler setup)
- **Better error handling** with Swift's type system
- **Test coverage** with 197 tests (TDD from day one)

### Developer Experience
- **Type safety** with Swift instead of Python's duck typing
- **Better IDE support** with Xcode vs. Python editors
- **Faster iteration** with Swift Package Manager hot reload
- **Cleaner architecture** following Grokking Simplicity principles

---

## What's Missing (Not Migrated)

### Processing Games
The experimental VJ games (`WhackAMole`, `CrowdBattle`, etc.) were not migrated. These were proof-of-concept interactive visuals. If you need similar functionality, consider:

1. **Build in Swift-VJ rendering engine** - Add custom tiles with Metal shaders
2. **Use Synesthesia directly** - Its built-in effects are more powerful
3. **External tools** - TouchDesigner, Resolume for interactive effects

### Process Management
Python-VJ could launch and monitor Processing sketches. This is obsolete because Swift-VJ is a native app with integrated rendering.

### Legacy Audio Analyzer
Python's Essentia-based audio analyzer was replaced by **Synesthesia's native OSC output**, which provides:
- Lower latency (~10-30ms vs. ~50-100ms)
- More accurate beat detection
- Professional-grade analysis (used by real VJs)
- No Python/NumPy dependencies

---

## Archived Locations

The original implementations are preserved for reference:

```
archive/
├── python-vj/              # Full Python VJ control system
│   ├── vj_console.py       # Terminal UI
│   ├── karaoke_engine.py   # Lyrics engine
│   ├── audio_analyzer.py   # Audio analysis (replaced by Synesthesia)
│   ├── midi_router.py      # MIDI middleware
│   └── ... (complete source)
└── processing-vj/          # Processing sketches and games
    ├── examples/           # VJ games
    ├── src/                # Main apps (VJUniverse, KaraokeOverlay, etc.)
    └── lib/                # Shared utilities
```

**Documentation:** Original READMEs and guides are preserved in the archived directories.

---

## Getting Help

- **Swift-VJ Documentation:** See `swift-vj/README.md` and `swift-vj/REWRITE_PLAN.md`
- **OSC Protocol:** See `OSC.md` (unchanged from python-vj)
- **Shader Format:** See `docs/reference/isf-to-synesthesia-migration.md`
- **Issues:** If you need a feature from python-vj/processing-vj that's missing, open a GitHub issue

---

## FAQ

**Q: Can I still use my old Launchpad configs?**  
A: Yes! Swift-VJ reads the same JSON format as python-vj's MIDI router.

**Q: Will my OSC clients break?**  
A: No. Swift-VJ sends identical OSC messages to python-vj. It's a drop-in replacement.

**Q: Why was Processing deprecated?**  
A: Swift-VJ's Metal-based rendering is faster and more maintainable than Java/Processing + GLSL.

**Q: Can I run python-vj and swift-vj simultaneously?**  
A: No. They both use the same OSC ports and would conflict. Choose one.

**Q: What about my custom Processing sketches?**  
A: They're still in `archive/processing-vj/`. You can run them independently, but they won't integrate with swift-vj's pipeline. Consider porting to Metal shaders.

**Q: Is Swift-VJ production-ready?**  
A: Yes. All core features are complete with 197 passing tests. See `swift-vj/REWRITE_PLAN.md` for details.

---

**For detailed implementation comparisons, see `swift-vj/REWRITE_PLAN.md` Section 2 (Feature Inventory).**

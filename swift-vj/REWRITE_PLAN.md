# Swift-VJ: Complete Rewrite Plan from Python-VJ

> **Target**: macOS VJ Control Application  
> **Source**: `python-vj/` (~6500 LOC Python)  
> **Principles**: Grokking Simplicity, A Philosophy of Software Design, TDD  
> **Code Examples**: See [CODE_EXAMPLES.md](CODE_EXAMPLES.md)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Feature Inventory](#2-feature-inventory)
3. [Implementation Phases](#3-implementation-phases)
4. [External Service Integration](#4-external-service-integration)
5. [Package Structure](#5-package-structure)
6. [Implementation Notes](#6-implementation-notes)

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    UI Layer (SwiftUI)                   │
└────────────────────────┬────────────────────────────────┘
┌────────────────────────▼────────────────────────────────┐
│                  Module Registry                        │
└────────────────────────┬────────────────────────────────┘
┌────────────────────────▼────────────────────────────────┐
│   Modules: OSC │ Playback │ Lyrics │ AI │ Shaders │    │
│            Pipeline │ Launchpad │ Process │ Images     │
└────────────────────────┬────────────────────────────────┘
┌────────────────────────▼────────────────────────────────┐
│   Adapters: LyricsFetcher │ SpotifyMonitor │ VDJMonitor│
│             LLMClient │ ShaderMatcher │ ImageScraper   │
└────────────────────────┬────────────────────────────────┘
┌────────────────────────▼────────────────────────────────┐
│   Infrastructure: Config │ Settings │ ServiceHealth    │
└────────────────────────┬────────────────────────────────┘
┌────────────────────────▼────────────────────────────────┐
│   Domain: Pure data types │ Pure functions              │
└─────────────────────────────────────────────────────────┘
```

### Design Principles

- **Grokking Simplicity**: Data → Calculations → Actions (separated)
- **Deep Modules**: Simple interfaces hiding complexity (2-5 public methods max)
- **TDD**: Test behaviors, not implementation; no mocking; skip when prerequisites unavailable

---

## 2. Feature Inventory

### 2.1 Playback Detection

| Feature | Status | Source |
|---------|--------|--------|
| VirtualDJ Track Detection (OSC) | ✅ | `vdj_monitor.py` |
| VirtualDJ Position Polling | ✅ | `vdj_monitor.py` |
| VirtualDJ BPM/Beat | ✅ | `vdj_monitor.py` |
| Spotify AppleScript | ✅ | `adapters.py` |
| Hot-swap Sources | ✅ | `modules/playback.py` |
| Track Change Callbacks | ✅ | `modules/playback.py` |
| Multi-deck Support | ✅ | `vdj_monitor.py` |

### 2.2 Lyrics System

| Feature | Status | Source |
|---------|--------|--------|
| LRC Fetching (LRCLIB API) | ✅ | `adapters.py` |
| LRC Parsing | ✅ | `domain_types.py` |
| Refrain Detection | ✅ | `domain_types.py` |
| Keyword Extraction | ✅ | `domain_types.py` |
| Position-based Active Line | ✅ | `domain_types.py` |
| Timing Offset Adjustment | ✅ | `infra.py` |
| 7-day Cache TTL | ✅ | `adapters.py` |
| OSC Broadcast | ✅ | `modules/pipeline.py` |

### 2.3 AI Analysis

| Feature | Status | Source |
|---------|--------|--------|
| Song Categorization | ✅ | `ai_services.py` |
| Energy/Valence Scoring | ✅ | `modules/ai_analysis.py` |
| Multiple LLM Backends | ✅ | `ai_services.py` |
| Graceful Degradation | ✅ | `ai_services.py` |
| Visual Adjectives Extraction | ✅ | `ai_services.py` |
| Combined Single-Call Analysis | ✅ | `ai_services.py` |

### 2.4 Shader System

| Feature | Status | Source |
|---------|--------|--------|
| Shader Indexing | ✅ | `shader_matcher.py` |
| LLM Shader Analysis | ✅ | `shader_matcher.py` |
| Feature Extraction | ✅ | `shader_matcher.py` |
| Quality Ratings (BEST→SKIP) | ✅ | `shader_matcher.py` |
| Feature-based Matching | ✅ | `modules/shaders.py` |
| Mood-based Matching | ✅ | `modules/shaders.py` |
| ChromaDB/Vector Search | ✅ | `shader_matcher.py` |
| Text Search | ✅ | `modules/shaders.py` |

### 2.5 OSC Communication

| Feature | Status | Source |
|---------|--------|--------|
| Central Receiver (port 9999) | ✅ | `osc/hub.py` |
| Multi-target Forward | ✅ | `osc/hub.py` |
| Pattern Subscriptions | ✅ | `osc/hub.py` |
| Prefix Trie Matching | ✅ | `osc/hub.py` |
| Drop Detection | ➖ | `osc/hub.py` |
| Latency Monitoring | ✅ | `osc/hub.py` |
| Active Line OSC (position-driven) | ✅ | `ActiveLineTracker.swift` |
| Keywords/Metadata OSC | ✅ | `PipelineModule.swift` |

#### OSC Messages (Swift ↔ Python Parity)

**Pipeline Messages (on track load):**
- `/textler/track [active, source, artist, title, album, duration, has_lyrics]`
- `/textler/lyrics/reset []` + `/textler/lyrics/line [index, time, text]`
- `/textler/refrain/reset []` + `/textler/refrain/line [index, time, text]`
- `/textler/keywords/reset []` + `/textler/keywords/line [index, time, keywords]`
- `/textler/metadata/keywords`, `/textler/metadata/themes`, `/textler/metadata/visuals`, `/textler/metadata/mood`
- `/ai/analysis [mood, energy, valence]`
- `/shader/load [name, energy, valence]`
- `/image/fit [mode]` + `/image/folder [path]`

**Position Update Messages (during playback):**
- `/textler/line/active [index]`
- `/textler/refrain/active [index, text]` (when line is refrain)
- `/textler/keywords/active [index, keywords]` (when line has keywords)

### 2.6 Pipeline Orchestration

| Feature | Status | Source |
|---------|--------|--------|
| Step-by-step Processing | ✅ | `modules/pipeline.py` |
| Step Callbacks | ✅ | `modules/pipeline.py` |
| Graceful Skip | ✅ | `modules/pipeline.py` |
| OSC Broadcast | ✅ | `modules/pipeline.py` |
| Timing Metrics | ✅ | `modules/pipeline.py` |
| Result Caching | ✅ | `modules/pipeline.py` |
| Parallel Shader+Images | ✅ | `modules/pipeline.py` |
| Cache Serialization | ✅ | `modules/pipeline.py` |

### 2.7 MIDI Controller (Launchpad)

| Feature | Status | Source |
|---------|--------|--------|
| MIDI Device Discovery | ✅ | `Launchpad/MIDIManager.swift` |
| Pad Modes (SELECTOR/TOGGLE/ONE_SHOT/PUSH) | ✅ | `Launchpad/LaunchpadTypes.swift` |
| Button Groups (Radio Behavior) | ✅ | `Launchpad/LaunchpadTypes.swift` |
| LED Control (10 colors × 3 brightness) | ✅ | `Launchpad/LaunchpadTypes.swift` |
| Learn Mode FSM | ✅ | `Launchpad/LaunchpadFSM.swift` |
| Bank System (8×) | ➖ | future enhancement |
| JSON Config Persistence | ✅ | `Launchpad/EffectExecutor.swift` |
| Beat Sync LED Blinking | ✅ | `Launchpad/LaunchpadModule.swift` |
| Group Hierarchy | ✅ | `Launchpad/LaunchpadFSM.swift` |

### 2.8 Process Management

| Feature | Status | Source |
|---------|--------|--------|
| App Discovery (.pde scan) | ❌ | `process_manager.py` |
| Processing Path Detection | ❌ | `process_manager.py` |
| Sketch Launch | ❌ | `process_manager.py` |
| Process Lifecycle | ❌ | `process_manager.py` |
| Auto-restart Daemon | ❌ | `process_manager.py` |
| Graceful Stop | ❌ | `process_manager.py` |

### 2.9 Image System

| Feature | Status | Source |
|---------|--------|--------|
| Image Scraping (web search) | ✅ | `image_scraper.py` |
| Folder Output (by song) | ✅ | `image_scraper.py` |
| OSC Broadcast (folder path) | ✅ | `modules/pipeline.py` |

### 2.10 UI Features

| Feature | Status | Source |
|---------|--------|--------|
| Master Control Panel | ✅ | `SwiftVJApp/MasterControlView.swift` |
| OSC Debug View | ✅ | `SwiftVJApp/OSCDebugView.swift` |
| Log Viewer (500-line buffer) | ✅ | `SwiftVJApp/LogViewerView.swift` |
| Shader Browser | ✅ | `SwiftVJApp/ShaderBrowserView.swift` |
| Pipeline Status | ✅ | `SwiftVJApp/PipelineStatusView.swift` |
| Settings Panel | ✅ | `SwiftVJApp/SettingsView.swift` |

---

## 3. Implementation Phases

### Phase 1: Foundation ✅ COMPLETE

**Goal**: Core types, pure functions, configuration

| Task | Status |
|------|--------|
| Swift Package structure | ✅ |
| Domain types (LyricLine, Track, PlaybackState, etc.) | ✅ |
| Pure functions (parseLRC, extractKeywords, detectRefrains) | ✅ |
| Settings and Config | ✅ |
| ServiceHealth | ✅ |
| Test harness with prerequisites | ✅ |

**Tests**: LRCParsingTests (8), RefrainDetectionTests (9), SettingsTests (7)

---

### Phase 2: Adapters ✅ COMPLETE

**Goal**: Communicate with external world

| Task | Status |
|------|--------|
| LyricsFetcher (LRCLIB API + cache) | ✅ |
| OSCHub (send/receive, pattern routing) | ✅ |
| SpotifyMonitor (AppleScript bridge) | ✅ |
| VDJMonitor (OSC subscription) | ✅ |
| LLMClient (LM Studio / OpenAI / Basic fallback) | ✅ |
| File cache system | ✅ |

**Tests**: LyricsE2ETests (8), OSCE2ETests (15), PlaybackE2ETests, LLMClientTests (15)

---

### Phase 3: Modules Layer ✅ COMPLETE

**Goal**: Business logic modules with lifecycle

| Task | Status | Notes |
|------|--------|-------|
| Module protocol | ✅ | start/stop/getStatus |
| PlaybackModule | ✅ | Track detection + callbacks |
| LyricsModule | ✅ | Fetch + parse + timing |
| AIModule | ✅ | Categorization + energy/valence |
| PipelineModule | ✅ | Full orchestration with shader+images |
| ModuleRegistry | ✅ | Lifecycle management |
| ShaderMatcher adapter | ✅ | Load .analysis.json, feature matching |
| ShadersModule | ✅ | match/matchByMood/search with usage tracking |
| ImageScraper adapter | ✅ | Fetch from 4 sources with rate limiting |
| ImagesModule | ✅ | fetchImages with metadata support |

**Tests**: PlaybackModuleTests (3), LyricsModuleTests (2), AIModuleTests (3), PipelineModuleTests (4), ModuleRegistryTests (5), ShaderMatcherTests (12), ShadersModuleTests (8), ImageScraperTests (5), ImagesModuleTests (8)

---

### Phase 4: SwiftUI Shell ✅ COMPLETE

**Goal**: Minimal UI to drive modules

| Task | Status | Notes |
|------|--------|-------|
| Main window | ✅ | Tab structure with NavigationSplitView sidebar |
| Master control panel | ✅ | Playback status, source selector, timing controls |
| OSC debug view | ✅ | Message log with filtering, send test messages |
| Log viewer | ✅ | Ring buffer, level filtering |
| Shader browser | ✅ | LazyVGrid with quality badges, search |
| Pipeline status | ✅ | Step-by-step progress with icons |
| Settings panel | ✅ | Tabs: General, Playback, AI, Appearance |

**UI Screenshots**: Available at [docs/screenshots/swiftvjapp_main.png](docs/screenshots/swiftvjapp_main.png)

**Files Created**:
- `Sources/SwiftVJApp/SwiftVJApp.swift` - Main app entry + AppState
- `Sources/SwiftVJApp/ContentView.swift` - NavigationSplitView sidebar
- `Sources/SwiftVJApp/MasterControlView.swift` - Playback controls
- `Sources/SwiftVJApp/PipelineStatusView.swift` - Pipeline progress
- `Sources/SwiftVJApp/ShaderBrowserView.swift` - Shader grid browser
- `Sources/SwiftVJApp/OSCDebugView.swift` - OSC debug/test
- `Sources/SwiftVJApp/LogViewerView.swift` - Log viewer
- `Sources/SwiftVJApp/SettingsView.swift` - Settings panel

**Rendering Module** (`Sources/SwiftVJApp/Rendering/`):
- `RenderEngine.swift` - Main orchestrator with TileManager actor
- `RenderingTypes.swift` - AudioState, LyricLine, ShaderUniforms, TileConfig
- `RenderingViews.swift` - SwiftUI views (RenderingView, TilePreviewView, AudioVisualizerView)
- `Tile.swift` - Base Tile protocol and BaseTile/TextTile classes
- `ShaderTile.swift` - GLSL shader rendering with Metal pipeline
- `MaskShaderTile.swift` - Grayscale mask shader for compositing
- `TextTiles.swift` - LyricsTile, RefrainTile, SongInfoTile
- `ImageTile.swift` - Image display with crossfade and beat-sync cycling
- `AudioProcessor.swift` - Audio analysis and smoothing (port of SynesthesiaAudioOSC.pde)
- `SyphonOutput.swift` - Syphon server management (stub implementation)

**Syphon Integration**: See [docs/syphon-integration.md](docs/syphon-integration.md) for XCFramework build instructions

---

### Phase 5: MIDI Controller (Launchpad) ✅ COMPLETE

**Goal**: Full Launchpad Mini MK3 support for live VJ control

| Task | Status |
|------|--------|
| CoreMIDI device discovery | ✅ |
| ButtonId coordinate system | ✅ |
| PadMode enum | ✅ |
| PadBehavior struct | ✅ |
| ControllerState struct | ✅ |
| ButtonGroupType enum | ✅ |
| Group hierarchy | ✅ |
| LED color system | ✅ |
| Pure FSM functions | ✅ |
| Effect execution shell | ✅ |
| Learn mode FSM | ✅ |
| CONFIG phase | ✅ |
| OSC event filtering | ✅ |
| JSON config persistence | ✅ |
| Beat sync LED blinking | ✅ |
| Bank system | ➖ (future enhancement) |
| LaunchpadModule | ✅ |

**Files Created**:
- `Sources/SwiftVJCore/Launchpad/LaunchpadTypes.swift` - Immutable data types (ButtonId, PadMode, PadBehavior, ControllerState, LearnState, etc.)
- `Sources/SwiftVJCore/Launchpad/LaunchpadFSM.swift` - Pure FSM functions (handlePadPress, handlePadRelease, enterLearnMode, etc.)
- `Sources/SwiftVJCore/Launchpad/MIDIManager.swift` - CoreMIDI wrapper for device discovery and communication
- `Sources/SwiftVJCore/Launchpad/EffectExecutor.swift` - Imperative shell executing LaunchpadEffect
- `Sources/SwiftVJCore/Launchpad/LaunchpadModule.swift` - Module wrapper with lifecycle

**TDD Checkpoints**:
- [x] Pad press generates correct OSC effect
- [x] SELECTOR mode deactivates previous in group
- [x] TOGGLE alternates between osc_on/osc_off
- [x] PUSH sends 1.0 on press, 0.0 on release
- [x] Learn mode FSM transitions correctly
- [x] Config saves and loads pad mappings
- [x] Group hierarchy resets child groups on parent change
- [x] Beat sync blinks LEDs correctly (BPM-based timer + beat pulse)

---

### Phase 6: Process Management ❌ NOT STARTED

**Goal**: Launch and manage Processing sketches

| Task | Description |
|------|-------------|
| ProcessingApp struct | name, path, description, process state |
| App discovery | Scan processing-vj/src/ for .pde files |
| Description extraction | Parse first comment line |
| processing-java detection | Find in PATH or common locations |
| Sketch launch | processing-java --sketch=<path> --run |
| Process lifecycle | Track Popen with proper cleanup |
| Graceful stop | terminate() → wait 3s → kill() |
| Auto-restart daemon | Monitor thread with cooldown |
| Restart cooldown | Exponential: min(30, 5 * (count + 1)) |
| ProcessModule | Module wrapper with lifecycle |

**TDD Checkpoints**:
- [ ] Discovery finds all .pde sketches
- [ ] Launch starts Processing sketch
- [ ] Stop terminates gracefully
- [ ] Crashed app restarts with cooldown

---

### Phase 7: Advanced OSC Features ❌ NOT STARTED

**Goal**: Production-ready OSC hub

| Task | Description |
|------|-------------|
| Prefix trie for routing | O(k) pattern matching |
| Queue with drop detection | 4096-message queue, track overflow |
| Latency monitoring | Track message delays |
| Statistics collection | Messages/sec, drops, latency histogram |
| OSC recording/playback | Record sessions for debugging |

**TDD Checkpoints**:
- [ ] Trie matches patterns correctly
- [ ] Drop detection triggers on overflow
- [ ] Latency stats accurate within 1ms

---

### Phase 8: CLI Tools ❌ NOT STARTED

**Goal**: Standalone CLI for testing modules

| Task | Description |
|------|-------------|
| PlaybackCommand | --source vdj/spotify |
| LyricsCommand | --artist --title |
| ShadersCommand | --energy --valence --mood |
| PipelineCommand | Full pipeline with output |
| OSCCommand | Send/receive test messages |
| LaunchpadCommand | LED test, config dump |

---

## 4. External Service Integration

### OSC Ports

| Service | Direction | Port |
|---------|-----------|------|
| OSC Hub | Receive | 9999 |
| VJUniverse | Send | 10000 |
| Magic Music | Send | 11111 |
| VirtualDJ | Send | 9009 |
| Synesthesia | Send | 7777 |

### HTTP APIs

| Service | URL |
|---------|-----|
| LRCLIB | https://lrclib.net/api |
| LM Studio | http://localhost:1234/v1 |
| OpenAI | https://api.openai.com/v1 |

---

## 5. Package Structure

```
swift-vj/
├── Package.swift
├── Sources/
│   ├── SwiftVJ/                    # CLI
│   │   └── Commands/
│   ├── SwiftVJCore/
│   │   ├── Domain/                 # Types.swift, Functions.swift
│   │   ├── Infrastructure/         # Config, Settings, ServiceHealth, Cache
│   │   ├── Adapters/               # LyricsFetcher, OSCHub, VDJMonitor, etc.
│   │   ├── Modules/                # Module protocol + all modules
│   │   ├── Launchpad/              # MIDI controller (FSM, Effects, Config)
│   │   └── Rendering/              # Display state types
│   └── SwiftVJUI/                  # SwiftUI App
├── Tests/
│   ├── BehaviorTests/              # Pure function tests
│   └── E2ETests/                   # Integration tests
├── REWRITE_PLAN.md
└── CODE_EXAMPLES.md
```

---

## 6. Implementation Notes

### Python Reference Files

| Feature | Reference |
|---------|-----------|
| LRC Parsing | `domain_types.py:160-187` |
| OSC Hub | `osc/hub.py` |
| VDJ Monitor | `vdj_monitor.py` |
| Pipeline | `modules/pipeline.py` |
| AI Analysis | `modules/ai_analysis.py`, `ai_services.py` |
| Shader Matching | `shader_matcher.py`, `modules/shaders.py` |
| Image Scraping | `image_scraper.py` |
| Launchpad FSM | `launchpad_osc_lib/fsm.py` |
| Process Manager | `process_manager.py` |
| Settings | `infra.py:84-276` |

### Critical Design Decisions

1. **Actors for Modules**: Swift actors for thread safety
2. **AsyncStream for Events**: Better than closures for callbacks
3. **Sendable Types**: All domain types are Sendable (structs)
4. **No Combine**: Prefer async/await for simplicity

### Gotchas from Python

1. **VDJ OSC**: Only sends on change for metadata, needs polling for position
2. **LRC Formats**: Both `[mm:ss.xx]` and `[mm:ss.xxx]` exist
3. **Graceful Degradation**: Every external dependency can fail
4. **Cache Keys**: Use consistent `sanitizeCacheFilename()` for all keys

---

*Last Updated: 2026-01-02*  
*Test Count: 197 tests passing (8 skipped)*

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
| Shader Indexing | ❌ | `shader_matcher.py` |
| LLM Shader Analysis | ❌ | `shader_matcher.py` |
| Feature Extraction | ❌ | `shader_matcher.py` |
| Quality Ratings (BEST→SKIP) | ❌ | `shader_matcher.py` |
| Feature-based Matching | ❌ | `modules/shaders.py` |
| Mood-based Matching | ❌ | `modules/shaders.py` |
| ChromaDB/Vector Search | ❌ | `shader_matcher.py` |
| Text Search | ❌ | `modules/shaders.py` |

### 2.5 OSC Communication

| Feature | Status | Source |
|---------|--------|--------|
| Central Receiver (port 9999) | ✅ | `osc/hub.py` |
| Multi-target Forward | ✅ | `osc/hub.py` |
| Pattern Subscriptions | ✅ | `osc/hub.py` |
| Prefix Trie Matching | ❌ | `osc/hub.py` |
| Drop Detection | ❌ | `osc/hub.py` |
| Latency Monitoring | ❌ | `osc/hub.py` |

### 2.6 Pipeline Orchestration

| Feature | Status | Source |
|---------|--------|--------|
| Step-by-step Processing | ✅ | `modules/pipeline.py` |
| Step Callbacks | ✅ | `modules/pipeline.py` |
| Graceful Skip | ✅ | `modules/pipeline.py` |
| OSC Broadcast | ✅ | `modules/pipeline.py` |
| Timing Metrics | ✅ | `modules/pipeline.py` |
| Result Caching | ✅ | `modules/pipeline.py` |
| Parallel Shader+Images | ❌ | `modules/pipeline.py` |
| Cache Serialization | ❌ | `modules/pipeline.py` |

### 2.7 MIDI Controller (Launchpad)

| Feature | Status | Source |
|---------|--------|--------|
| MIDI Device Discovery | ❌ | `launchpad_osc_lib/` |
| Pad Modes (SELECTOR/TOGGLE/ONE_SHOT/PUSH) | ❌ | `launchpad_osc_lib/model.py` |
| Button Groups (Radio Behavior) | ❌ | `launchpad_osc_lib/model.py` |
| LED Control (10 colors × 3 brightness) | ❌ | `launchpad_osc_lib/model.py` |
| Learn Mode FSM | ❌ | `launchpad_osc_lib/fsm.py` |
| Bank System (8×) | ❌ | `launchpad_osc_lib/banks.py` |
| YAML Config Persistence | ❌ | `launchpad_osc_lib/config.py` |
| Beat Sync LED Blinking | ❌ | `launchpad_osc_lib/blink.py` |
| Group Hierarchy | ❌ | `launchpad_osc_lib/model.py` |

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
| Image Scraping (web search) | ❌ | `image_scraper.py` |
| Folder Output (by song) | ❌ | `image_scraper.py` |
| OSC Broadcast (folder path) | ❌ | `modules/pipeline.py` |

### 2.10 UI Features

| Feature | Status | Source |
|---------|--------|--------|
| Master Control Panel | ❌ | `vj_console.py` |
| OSC Debug View | ❌ | `ui/panels/osc.py` |
| Log Viewer (500-line buffer) | ❌ | `ui/panels/logs.py` |
| Shader Browser | ❌ | `ui/panels/shaders.py` |
| Pipeline Status | ❌ | `ui/panels/pipeline.py` |
| Settings Panel | ❌ | `infra.py` |

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

### Phase 3: Modules Layer 🔄 PARTIAL

**Goal**: Business logic modules with lifecycle

| Task | Status | Notes |
|------|--------|-------|
| Module protocol | ✅ | start/stop/getStatus |
| PlaybackModule | ✅ | Track detection + callbacks |
| LyricsModule | ✅ | Fetch + parse + timing |
| AIModule | ✅ | Categorization + energy/valence |
| PipelineModule | ✅ | Orchestration (basic) |
| ModuleRegistry | ✅ | Lifecycle management |
| **ShaderMatcher adapter** | ❌ | Load/index shaders from disk |
| **ShadersModule** | ❌ | match(energy:valence:), searchByMood() |
| **ImageScraper adapter** | ❌ | Fetch images from web |
| **ImagesModule** | ❌ | fetchImages(for:visualAdjectives:) |

**Tests**: PlaybackModuleTests (3), LyricsModuleTests (2), AIModuleTests (3), PipelineModuleTests (4), ModuleRegistryTests (5)

---

### Phase 3B: Shader & Image System ❌ NOT STARTED

**Goal**: Complete shader matching and image scraping

| Task | Description |
|------|-------------|
| ShaderMatcher adapter | Load .synScene directories, parse scene.json metadata |
| Shader feature extraction | Extract energy, mood, colors, motion, effects from GLSL |
| LLM shader analysis | Use LLM to analyze shader visual characteristics |
| Quality rating system | BEST(1), GOOD(2), NORMAL(3), MASK(4), SKIP(5) |
| Vector similarity matching | Feature-based matching with euclidean distance |
| Mood keyword matching | Match shader mood to song mood |
| Text search | Keyword-based shader search |
| ShadersModule | Module wrapper with match/search interface |
| ImageScraper adapter | Web image search (DuckDuckGo/Bing) |
| Image folder management | Store images by artist-title |
| ImagesModule | Module wrapper with fetch interface |
| Pipeline integration | Add shader+image steps to pipeline |
| Parallel execution | Run shader+image steps concurrently |

**TDD Checkpoints**:
- [ ] Shader indexing loads all .synScene directories
- [ ] Feature extraction returns valid scores
- [ ] match(energy:valence:) returns best shader
- [ ] searchByMood("dark") returns appropriate shaders
- [ ] ImageScraper returns image URLs
- [ ] Images saved to correct folder structure
- [ ] Pipeline runs shader+image steps in parallel

---

### Phase 4: SwiftUI Shell ❌ NOT STARTED

**Goal**: Minimal UI to drive modules

| Task | Description |
|------|-------------|
| Main window | Tab structure with sidebar |
| Master control panel | Playback status, source selector, timing controls |
| OSC debug view | Message log with filtering, send test messages |
| Log viewer | 500-line ring buffer, level filtering |
| Shader browser | List shaders, preview, manual selection |
| Pipeline status | Step-by-step progress, timing display |
| Settings panel | All user preferences |

**TDD Checkpoints**:
- [ ] UI updates on playback change
- [ ] Settings changes persist
- [ ] Log buffer limits to 500 lines
- [ ] Shader browser displays all indexed shaders

---

### Phase 5: MIDI Controller (Launchpad) ❌ NOT STARTED

**Goal**: Full Launchpad Mini MK3 support for live VJ control

| Task | Description |
|------|-------------|
| CoreMIDI device discovery | Find Launchpad, handle connect/disconnect |
| ButtonId coordinate system | (0-8, 0-7) grid addressing |
| PadMode enum | SELECTOR, TOGGLE, ONE_SHOT, PUSH |
| PadBehavior struct | Mode, group, colors, OSC commands |
| ControllerState struct | Immutable state for all pads |
| ButtonGroupType enum | SCENES, PRESETS, COLORS, CUSTOM |
| Group hierarchy | PRESETS resets when SCENES changes |
| LED color system | 10 colors × 3 brightness levels |
| Pure FSM functions | Return (newState, [Effect]) |
| Effect execution shell | Send OSC, set LED, save config, log |
| Learn mode FSM | IDLE → WAIT_PAD → RECORD_OSC → CONFIG |
| CONFIG phase | 3 registers (OSC/Mode/Color selection) |
| OSC event filtering | is_controllable() for learn mode |
| Bank system | 8× pad capacity via banks |
| YAML config persistence | ~/.config/launchpad_osc_lib/ |
| Beat sync LED blinking | Subscribe to /audio/beat/onbeat |
| LaunchpadModule | Module wrapper with lifecycle |

**TDD Checkpoints**:
- [ ] Pad press generates correct OSC effect
- [ ] SELECTOR mode deactivates previous in group
- [ ] TOGGLE alternates between osc_on/osc_off
- [ ] PUSH sends 1.0 on press, 0.0 on release
- [ ] Learn mode FSM transitions correctly
- [ ] Config saves and loads pad mappings
- [ ] Group hierarchy resets child groups on parent change
- [ ] Beat sync blinks LEDs correctly

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
*Test Count: 164 tests passing (8 skipped)*

# Swift-VJ: Complete Rewrite Plan from Python-VJ

> **Target**: macOS VJ Control Application
> **Source**: `python-vj/` (~6500 LOC Python)
> **Principles**: Grokking Simplicity, A Philosophy of Software Design, TDD

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Complete Feature Inventory](#2-complete-feature-inventory)
3. [Domain Types (Immutable Data)](#3-domain-types-immutable-data)
4. [Module System Design](#4-module-system-design)
5. [TDD Strategy](#5-tdd-strategy)
6. [Implementation Phases](#6-implementation-phases)
7. [Swift-Specific Considerations](#7-swift-specific-considerations)
8. [External Service Integration](#8-external-service-integration)
9. [Testing Prerequisites System](#9-testing-prerequisites-system)
10. [Notes for Future Implementation](#10-notes-for-future-implementation)

---

## 1. Architecture Overview

### 1.1 Stratified Architecture (from Python)

```
┌─────────────────────────────────────────────────────────┐
│                    UI Layer (SwiftUI)                   │
│         Thin shell - only coordinates modules           │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│                  Module Registry                        │
│      Lifecycle management, dependency injection         │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│                    Modules Layer                        │
│   OSC │ Playback │ Lyrics │ AI │ Shaders │ Pipeline    │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│                  Adapters Layer                         │
│    LyricsFetcher │ SpotifyMonitor │ VDJMonitor │ LLM    │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│               Infrastructure Layer                      │
│     Config │ Settings │ ServiceHealth │ Cache          │
└────────────────────────┬────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────┐
│                  Domain Layer                           │
│    Pure data types │ Pure functions │ No side effects   │
└─────────────────────────────────────────────────────────┘
```

### 1.2 Design Principles

**Grokking Simplicity**:
- Separate **data** from **calculations** from **actions**
- All domain types are immutable (Swift `struct` with `let`)
- Pure functions have no side effects
- Actions are clearly marked and isolated

**A Philosophy of Software Design**:
- **Deep modules**: Simple interfaces hiding complexity
- Each module exposes 2-5 public methods max
- Internal complexity is hidden
- Avoid shallow modules (many methods, little functionality)

**TDD Philosophy**:
- Test end-to-end behaviors, not implementation details
- No mocking - tests run against real services when available
- Tests skip gracefully when prerequisites unavailable
- Focus on "what happens when X" not "does function Y get called"

---

## 2. Complete Feature Inventory

### 2.1 Playback Detection

| Feature | Description | Source |
|---------|-------------|--------|
| VirtualDJ Track Detection | OSC subscription to deck info | `vdj_monitor.py` |
| VirtualDJ Position Tracking | Polling for continuous position data | `vdj_monitor.py` |
| VirtualDJ BPM/Beat | Subscribe to BPM changes | `vdj_monitor.py` |
| Spotify AppleScript | Query Spotify.app via osascript | `adapters.py` |
| Hot-swap Sources | Switch playback source without restart | `modules/playback.py` |
| Track Change Callbacks | Fire callback when new track detected | `modules/playback.py` |
| Position Callbacks | Fire callback on position updates | `modules/playback.py` |
| Multi-deck Support | Track both VDJ decks, report audible one | `vdj_monitor.py` |

### 2.2 Lyrics System

| Feature | Description | Source |
|---------|-------------|--------|
| LRC Fetching | Fetch synced lyrics from LRCLIB API | `adapters.py` |
| LRC Parsing | Parse [mm:ss.xx]text format | `domain_types.py` |
| Refrain Detection | Mark repeated lines as refrain | `domain_types.py` |
| Keyword Extraction | Extract significant words from lyrics | `domain_types.py` |
| Position-based Active Line | Find current line from playback position | `domain_types.py` |
| Timing Offset Adjustment | User-adjustable offset (+/- milliseconds) | `infra.py` |
| 7-day Cache TTL | Cache lyrics with expiration | `adapters.py` |
| OSC Broadcast | Send lyrics lines to external apps | `modules/pipeline.py` |

### 2.3 AI Analysis

| Feature | Description | Source |
|---------|-------------|--------|
| Song Categorization | Mood/theme classification | `ai_services.py` |
| Energy Scoring | 0.0-1.0 energy level | `modules/ai_analysis.py` |
| Valence Scoring | -1.0 to 1.0 mood brightness | `modules/ai_analysis.py` |
| Multiple LLM Backends | LM Studio, OpenAI, Basic fallback | `ai_services.py` |
| Graceful Degradation | Works offline with basic analysis | `ai_services.py` |
| LLM Metadata Fetch | Keywords, themes, visual adjectives | `adapters.py` |
| Automatic Caching | Cache analysis results | `ai_services.py` |
| **Visual Adjectives** | LLM extracts aesthetic words (neon, cosmic, ethereal) for image search | `ai_services.py` |
| Combined Single-Call | `analyze_song_complete()` merges metadata + categorization in one LLM call | `ai_services.py` |

### 2.4 Shader System

| Feature | Description | Source |
|---------|-------------|--------|
| Shader Indexing | Load ISF/GLSL shader metadata | `shader_matcher.py` |
| LLM Shader Analysis | Analyze shaders for visual features | `shader_matcher.py` |
| Feature Extraction | Energy, mood, colors, motion, effects | `shader_matcher.py` |
| Quality Ratings | BEST(1), GOOD(2), NORMAL(3), MASK(4), SKIP(5) | `shader_matcher.py` |
| Feature-based Matching | Map energy/valence to shader | `modules/shaders.py` |
| Mood-based Matching | Match by mood keyword | `modules/shaders.py` |
| ChromaDB Search | Semantic vector search | `shader_matcher.py` |
| Text Search | Keyword-based shader search | `modules/shaders.py` |

### 2.5 OSC Communication

| Feature | Description | Source |
|---------|-------------|--------|
| Central Receiver | Port 9999 receives all messages | `osc/hub.py` |
| Multi-target Forward | Forward to 10000, 11111 | `osc/hub.py` |
| Pattern Subscriptions | Subscribe with wildcards | `osc/hub.py` |
| Prefix Trie Matching | Efficient pattern matching | `osc/hub.py` |
| Drop Detection | Track queue overflow | `osc/hub.py` |
| Latency Monitoring | Track message delays | `osc/hub.py` |
| Send Channels | VDJ(9009), Synesthesia(7777), Processing(10000) | `osc/hub.py` |

### 2.6 Pipeline Orchestration

| Feature | Description | Source |
|---------|-------------|--------|
| Step-by-step Processing | Lyrics -> Metadata -> AI -> Shaders -> Images | `modules/pipeline.py` |
| Step Callbacks | on_step_start, on_step_complete | `modules/pipeline.py` |
| Graceful Skip | Each step skippable | `modules/pipeline.py` |
| OSC Broadcast | Send results to Processing | `modules/pipeline.py` |
| Timing Metrics | Track processing time | `modules/pipeline.py` |
| Concurrent Execution | Background thread processing | `modules/pipeline.py` |
| **Result Caching** | Full pipeline results cached per track with TTL (instant replay) | `modules/pipeline.py` |
| **Parallel Phase 3** | Shader + Images run in parallel (ThreadPoolExecutor) | `modules/pipeline.py` |
| **Cache Serialization** | `PipelineResult.to_cache_dict()` / `from_cache_dict()` for JSON storage | `modules/pipeline.py` |

### 2.7 MIDI Controller (Launchpad) - CRITICAL FEATURE

**This is a core feature for live VJ performance control.**

| Feature | Description | Source |
|---------|-------------|--------|
| Launchpad Mini MK3 | Hardware controller support | `launchpad_osc_lib/` |
| Pad Modes | SELECTOR, TOGGLE, ONE_SHOT, PUSH | `launchpad_osc_lib/model.py` |
| Button Groups | Radio-button behavior (SCENES, PRESETS, COLORS, CUSTOM) | `launchpad_osc_lib/model.py` |
| LED Control | Static, Pulse, Flash modes with 10 base colors × 3 brightness levels | `launchpad_osc_lib/model.py` |
| Learn Mode FSM | Configure pads by recording OSC with multi-phase workflow | `launchpad_osc_lib/fsm.py` |
| Bank System | 8 button banks for expanded control | `launchpad_osc_lib/banks.py` |
| Config Persistence | Save/load pad mappings to YAML | `launchpad_osc_lib/config.py` |
| Beat Sync | Blink LEDs with beat from OSC | `launchpad_osc_lib/blink.py` |
| Group Hierarchy | PRESETS resets when parent SCENES changes | `launchpad_osc_lib/model.py` |

#### 2.7.1 Pad Modes (Interaction Patterns)

```
PadMode.SELECTOR
├── Radio-button within a group (only one active at a time)
├── Deactivates previous pad in same group
├── Requires: group, osc_action
├── Example: Scene selection - pressing "AlienCavern" deselects "Nebula"

PadMode.TOGGLE
├── On/Off toggle with two OSC commands
├── Alternates between osc_on and osc_off
├── Requires: osc_on (osc_off optional)
├── Example: Effect enable/disable

PadMode.ONE_SHOT
├── Single action on press only
├── No persistent state - sends once and done
├── Requires: osc_action
├── Example: Trigger a one-time effect

PadMode.PUSH
├── Momentary - sends 1.0 on press, 0.0 on release
├── Like a sustain pedal
├── Requires: osc_action
├── Example: Hold-to-activate effect
```

#### 2.7.2 Button Groups (Radio Behavior)

```
ButtonGroupType.SCENES
├── Primary group for Synesthesia scene selection
├── When changed, resets child groups (PRESETS)

ButtonGroupType.PRESETS
├── Subgroup of SCENES
├── Automatically resets when parent SCENES changes
├── parent_group = SCENES

ButtonGroupType.COLORS
├── Meta color/hue control

ButtonGroupType.CUSTOM
├── User-defined groups
```

#### 2.7.3 LED Color System

```
Base Colors (10): red, orange, yellow, lime, green, cyan, blue, purple, pink, white
Brightness Levels (3): DIM(0), NORMAL(1), BRIGHT(2)

get_color_at_brightness("green", BrightnessLevel.DIM) -> 19
get_color_at_brightness("green", BrightnessLevel.BRIGHT) -> 22

LED Modes:
├── STATIC: Constant on
├── PULSE: Hardware pulsing (uses Launchpad native)
├── FLASH: Blinking effect
```

#### 2.7.4 Learn Mode FSM (Finite State Machine)

```
LearnPhase.IDLE
├── Normal operation - pads execute their configured behaviors
└── Press LEARN_BUTTON → WAIT_PAD

LearnPhase.WAIT_PAD
├── Blinking all pads, waiting for user to press a pad to configure
└── Press any grid pad → RECORD_OSC

LearnPhase.RECORD_OSC
├── Recording incoming OSC messages
├── Filters to only "controllable" addresses (scenes, presets, controls)
├── Press SAVE_PAD → save_from_recording() → IDLE
├── Press CANCEL_PAD → IDLE
└── Wait for timeout or manual finish → CONFIG

LearnPhase.CONFIG
├── Multi-register configuration phase
├── Three registers: OSC_SELECT, MODE_SELECT, COLOR_SELECT
├── Yellow pads at top select active register
├── OSC pagination (8 per page)
├── Bottom row: SAVE (green), TEST (blue), CANCEL (red)
└── Save → create PadBehavior → IDLE
```

#### 2.7.5 Domain Types

```swift
struct ButtonId: Hashable {
    let x: Int  // 0-8 (8 = right scene column)
    let y: Int  // 0-7 (0 = bottom, 7 = top row)
    func isGrid() -> Bool  // True if x < 8
}

struct OscCommand {
    let address: String
    let args: [Any]
}

struct PadBehavior {
    let padId: ButtonId
    let mode: PadMode
    let group: ButtonGroupType?
    let idleColor: Int
    let activeColor: Int
    let label: String
    let oscOn: OscCommand?   // TOGGLE mode
    let oscOff: OscCommand?  // TOGGLE mode
    let oscAction: OscCommand?  // SELECTOR/ONE_SHOT/PUSH
}

struct PadRuntimeState {
    let isActive: Bool
    let isOn: Bool
    let currentColor: Int
    let blinkEnabled: Bool
    let ledMode: LedMode
}

struct ControllerState {  // Immutable, all transitions return new instance
    let pads: [ButtonId: PadBehavior]
    let padRuntime: [ButtonId: PadRuntimeState]
    let activeSelectorByGroup: [ButtonGroupType: ButtonId?]
    let activeScene: String?
    let activePreset: String?
    let activeColorHue: Double?
    let beatPhase: Double
    let beatPulse: Bool
    let learnState: LearnState
    let blinkOn: Bool
}
```

#### 2.7.6 Effect System (Side Effects)

Pure FSM functions return `(newState, [Effect])`. Effects are executed by imperative shell:

```swift
enum Effect {
    case sendOsc(OscCommand)
    case setLed(padId: ButtonId, color: Int, blink: Bool)
    case saveConfig
    case log(message: String, level: LogLevel)
}
```

#### 2.7.7 Config Persistence

Pad configurations saved to YAML:
```yaml
pads:
  "0,0":
    x: 0
    y: 0
    mode: SELECTOR
    group: scenes
    idle_color: 19
    active_color: 22
    label: AlienCavern
    osc_action:
      address: /scenes/AlienCavern
      args: []
```

Default path: `~/.config/launchpad_osc_lib/config.yaml`

### 2.8 Process Management

| Feature | Description | Source |
|---------|-------------|--------|
| App Discovery | Scan `processing-vj/src/` for `.pde` files | `process_manager.py` |
| Processing Path Detection | Find `processing-java` in PATH or common locations | `process_manager.py` |
| Sketch Launch | `processing-java --sketch=<path> --run` | `process_manager.py` |
| Process Lifecycle | Track `subprocess.Popen` with proper cleanup | `process_manager.py` |
| Auto-restart Daemon | Monitor thread restarts crashed apps with cooldown | `process_manager.py` |
| Restart Cooldown | Exponential: `min(30, 5 * (restart_count + 1))` seconds | `process_manager.py` |
| Graceful Stop | `terminate()` → wait 3s → `kill()` | `process_manager.py` |
| Description Extraction | Parse first comment line from `.pde` file | `process_manager.py` |
| Health Tracking | Service availability state | `infra.py` |
| Exponential Backoff | Retry with increasing delay | `infra.py` |

**Key Classes:**
```
ProcessingApp
├── name: str
├── path: Path
├── description: str
├── process: Optional[Popen]
├── restart_count: int
├── last_restart: float
├── enabled: bool

ProcessManager
├── apps: List[ProcessingApp]
├── processing_cmd: Optional[str]
├── discover_apps(project_root) -> List[ProcessingApp]
├── launch_app(app) -> bool
├── stop_app(app)
├── is_running(app) -> bool
├── start_monitoring(daemon_mode)
├── stop_monitoring()
├── cleanup()
```

### 2.9 UI Features (Textual -> SwiftUI)

| Feature | Description | Source |
|---------|-------------|--------|
| Master Control Panel | Dashboard with all controls | `vj_console.py` |
| OSC Debug View | Message log with filtering | `ui/panels/osc.py` |
| Log Viewer | Application logs (500-line buffer) | `ui/panels/logs.py` |
| Shader Browser | Search and match shaders | `ui/panels/shaders.py` |
| Pipeline Status | Step-by-step progress | `ui/panels/pipeline.py` |
| Settings Persistence | JSON-backed settings | `infra.py` |
| Keyboard Shortcuts | Tab switching, timing adjust | `vj_console.py` |

### 2.10 Image System

| Feature | Description | Source |
|---------|-------------|--------|
| Image Scraping | Fetch images for songs | `image_scraper.py` |
| Folder Output | Store images by song | `image_scraper.py` |
| OSC Broadcast | Send folder path to Processing | `modules/pipeline.py` |

---

## 3. Domain Types (Immutable Data)

### 3.1 Core Types (Swift structs)

```
LyricLine
├── timeSec: Double
├── text: String
├── isRefrain: Bool
├── keywords: String

Track
├── artist: String
├── title: String
├── album: String
├── duration: Double
├── key: String (computed)

PlaybackState
├── track: Track?
├── position: Double
├── isPlaying: Bool
├── lastUpdate: Date

SongCategory
├── name: String
├── score: Double

SongCategories
├── scores: [String: Double]
├── primaryMood: String
├── getTop(n:) -> [SongCategory]

PipelineResult
├── artist, title, album
├── success: Bool
├── cached: Bool  // True if loaded from cache
├── lyricsFound, lyricsLineCount
├── lyricsLines: [LyricLine]
├── refrainLines, lyricsKeywords: [String]
├── plainLyrics: String
├── aiAnalyzed: Bool
├── keywords, themes: [String]
├── visualAdjectives: [String]  // LLM-generated: neon, cosmic, ethereal
├── llmRefrainLines: [String]
├── tempo: String
├── mood, energy, valence
├── categories: [String: Double]
├── shaderMatched: Bool
├── shaderName, shaderScore
├── imagesFound: Bool
├── imagesFolder, imagesCount
├── stepsCompleted, stepsSkipped: [String]
├── stepTimings: [String: Int]  // step_name -> ms
├── totalTimeMs: Int
├── func toCacheDict() -> [String: Any]
├── static func fromCacheDict(_:) -> PipelineResult
```

### 3.2 Pure Functions

```
parseLRC(text: String) -> [LyricLine]
extractKeywords(text: String, maxWords: Int) -> String
detectRefrains(lines: [LyricLine]) -> [LyricLine]
getActiveLineIndex(lines: [LyricLine], position: Double) -> Int
sanitizeCacheFilename(artist: String, title: String) -> String
```

### 3.3 Actions (Side Effects)

```
// Network
fetchLRC(artist:title:) async throws -> String?
fetchMetadata(artist:title:) async throws -> Metadata?
sendOSC(address:args:) -> Void

// File System
loadCache(artist:title:) -> CacheData?
saveCache(artist:title:data:) -> Void
loadSettings() -> Settings
saveSettings(_:) -> Void

// Process
querySpotify() async throws -> PlaybackInfo?
startProcess(path:) -> Process
```

---

## 4. Module System Design

### 4.1 Module Protocol

```swift
protocol Module {
    var isStarted: Bool { get }
    func start() async throws
    func stop() async
    func getStatus() -> [String: Any]
}
```

### 4.2 Module Inventory

| Module | Responsibility | Dependencies |
|--------|---------------|--------------|
| `OSCModule` | OSC send/receive, pattern routing | None |
| `PlaybackModule` | Track detection from VDJ/Spotify | OSCModule |
| `LyricsModule` | Fetch, parse, sync lyrics | None (uses LyricsFetcher) |
| `AIModule` | Song categorization | None (uses LLMClient) |
| `ShadersModule` | Shader indexing and matching | None |
| `PipelineModule` | Orchestrate all analysis | All above |
| `LaunchpadModule` | MIDI controller with pure FSM | OSCModule |
| `ProcessModule` | Processing app lifecycle | None |

### 4.3 Registry Pattern

```swift
class ModuleRegistry {
    // Lazy loading
    lazy var osc: OSCModule
    lazy var playback: PlaybackModule
    lazy var lyrics: LyricsModule
    lazy var ai: AIModule
    lazy var shaders: ShadersModule
    lazy var pipeline: PipelineModule

    func startAll() async
    func stopAll() async
    func wireTrackToPipeline(onComplete:)
}
```

---

## 5. TDD Strategy

### 5.1 Testing Philosophy

**DO:**
- Test observable behaviors ("when I do X, Y happens")
- Test integration with real services when available
- Test error handling and graceful degradation
- Test state transitions end-to-end

**DON'T:**
- Mock internal dependencies
- Test implementation details
- Write tests that just verify the language works
- Test private methods directly

### 5.2 Test Categories

```
Tests/
├── E2ETests/                    # Full integration
│   ├── PlaybackE2ETests.swift   # Requires VDJ/Spotify running
│   ├── LyricsE2ETests.swift     # Requires internet
│   ├── PipelineE2ETests.swift   # Full pipeline execution
│   └── OSCE2ETests.swift        # Requires OSC targets
│
├── BehaviorTests/               # No external deps
│   ├── LRCParsingTests.swift    # Pure function tests
│   ├── RefrainDetectionTests.swift
│   ├── ShaderMatchingTests.swift
│   └── CategoryScoreTests.swift
│
└── Prerequisites/               # Test helper
    └── TestPrerequisites.swift  # Check/prompt for services
```

### 5.3 Prerequisite System

From Python's `conftest.py` - adapted for Swift XCTest:

```swift
enum Prerequisite {
    case vdjRunning
    case vdjPlaying
    case spotifyRunning
    case lmStudioAvailable
    case internetConnection
    case vjUniverseListening
}

class PrerequisiteChecker {
    // Cache confirmed prerequisites
    private static var confirmed: Set<Prerequisite> = []

    static func require(_ prereq: Prerequisite) throws {
        if !confirmed.contains(prereq) {
            // Check automatically or skip
            guard check(prereq) else {
                throw XCTSkip("Prerequisite not met: \(prereq)")
            }
            confirmed.insert(prereq)
        }
    }

    private static func check(_ prereq: Prerequisite) -> Bool {
        switch prereq {
        case .internetConnection:
            return canConnect(host: "lrclib.net", port: 443)
        case .lmStudioAvailable:
            return isPortOpen(1234)
        case .vdjRunning:
            return isProcessRunning("VirtualDJ")
        // ...
        }
    }
}
```

### 5.4 Example Test Cases

```swift
// BehaviorTest: No external deps, tests pure logic
func test_parseLRC_extractsTimingsCorrectly() {
    let lrc = "[00:05.12]Hello world\n[00:10.00]Goodbye"
    let lines = parseLRC(lrc)

    XCTAssertEqual(lines.count, 2)
    XCTAssertEqual(lines[0].timeSec, 5.12, accuracy: 0.01)
    XCTAssertEqual(lines[0].text, "Hello world")
}

// E2ETest: Requires real service
func test_fetchLyrics_returnsLRCForKnownSong() async throws {
    try PrerequisiteChecker.require(.internetConnection)

    let fetcher = LyricsFetcher()
    let lrc = try await fetcher.fetch(artist: "Queen", title: "Bohemian Rhapsody")

    XCTAssertNotNil(lrc)
    XCTAssertTrue(lrc!.contains("["))
}

// E2ETest: Full pipeline
func test_pipeline_processesTrackEndToEnd() async throws {
    try PrerequisiteChecker.require(.internetConnection)
    // LM Studio optional - pipeline degrades gracefully

    let pipeline = PipelineModule()
    try await pipeline.start()

    let result = try await pipeline.process(artist: "Queen", title: "Bohemian Rhapsody")

    XCTAssertTrue(result.success)
    XCTAssertTrue(result.stepsCompleted.contains("lyrics"))
}
```

---

## 6. Implementation Phases

### Phase 1: Foundation (Domain + Infrastructure)

**Goal**: Core types, pure functions, configuration

```
Tasks:
1. Create Swift Package structure
2. Implement domain types (LyricLine, Track, etc.)
3. Implement pure functions (parseLRC, extractKeywords, etc.)
4. Implement Settings and Config
5. Implement ServiceHealth
6. Set up test harness with prerequisites
```

**TDD Checkpoints:**
- [x] LRC parsing works for all formats ✅ (LRCParsingTests: 8 tests)
- [x] Refrain detection marks repeated lines ✅ (RefrainDetectionTests: 4 tests)
- [x] Keyword extraction filters stop words ✅ (RefrainDetectionTests: 5 tests)
- [x] Active line detection handles edge cases ✅ (RefrainDetectionTests: 2 tests)
- [x] Settings persist to JSON ✅ (SettingsTests: 7 tests)

### Phase 2: Adapters (External Services)

**Goal**: Communicate with external world

```
Tasks:
1. LyricsFetcher (LRCLIB API)
2. OSCClient (send/receive via OSC framework)
3. SpotifyMonitor (AppleScript bridge)
4. VDJMonitor (OSC subscription)
5. LLMClient (LM Studio / OpenAI)
6. File cache system
```

**TDD Checkpoints:**
- [x] LRCLIB fetch returns lyrics for known songs ✅ (LyricsE2ETests: 8 tests)
- [ ] OSC send delivers messages to target
- [ ] Spotify query returns current track (when playing)
- [ ] VDJ subscription receives track changes
- [x] Cache stores and retrieves correctly ✅ (LyricsFetcher with 7-day TTL)

### Phase 3: Modules Layer

**Goal**: Business logic modules with lifecycle

```
Tasks:
1. OSCModule (hub with pattern routing)
2. PlaybackModule (track detection + callbacks)
3. LyricsModule (fetch + parse + timing)
4. AIModule (categorization + energy/valence)
5. ShadersModule (indexing + matching)
6. PipelineModule (orchestration)
7. ModuleRegistry (lifecycle management)
```

**TDD Checkpoints:**
- [ ] Playback detects track changes
- [ ] Lyrics sync with position
- [ ] AI categorizes with degradation
- [ ] Shader matching returns valid results
- [ ] Pipeline processes end-to-end

### Phase 4: SwiftUI Shell

**Goal**: Minimal UI to drive modules

```
Tasks:
1. Main window with tab structure
2. Master control panel
3. OSC debug view
4. Log viewer
5. Shader browser
6. Pipeline status view
7. Settings panel
```

**TDD Checkpoints:**
- [ ] UI updates on playback change
- [ ] Settings changes persist
- [ ] Log buffer limits to 500 lines

### Phase 5: MIDI Controller (Launchpad) - REQUIRED

**Goal**: Full Launchpad Mini MK3 support for live VJ control

```
Tasks:
1. MIDI device discovery (CoreMIDI)
2. ButtonId coordinate system (0-8, 0-7)
3. Pad modes (SELECTOR, TOGGLE, ONE_SHOT, PUSH)
4. Button groups with parent/child hierarchy
5. LED color system (10 colors × 3 brightness)
6. Immutable ControllerState with all runtime data
7. Pure FSM functions returning (State, [Effect])
8. Effect execution shell (OSC, LED, Config, Log)
9. Learn mode with 4-phase workflow (IDLE → WAIT_PAD → RECORD_OSC → CONFIG)
10. CONFIG phase with 3 registers (OSC/Mode/Color selection)
11. OSC event recording and filtering (is_controllable)
12. Bank system for 8× pad capacity
13. YAML config persistence (~/.config/launchpad_osc_lib/)
14. Beat sync LED blinking from OSC /audio/beat/onbeat
```

**TDD Checkpoints:**
- [ ] Pad press generates correct OSC effect
- [ ] SELECTOR mode deactivates previous in group
- [ ] TOGGLE alternates between osc_on/osc_off
- [ ] PUSH sends 1.0 on press, 0.0 on release
- [ ] Learn mode FSM transitions correctly
- [ ] Config saves and loads pad mappings
- [ ] Group hierarchy resets child groups on parent change

---

## 7. Swift-Specific Considerations

### 7.1 Concurrency Model

Use Swift's structured concurrency:

```swift
// Module as Actor for thread safety
actor PlaybackModule: Module {
    private var state: PlaybackState

    func start() async throws { ... }
    func stop() async { ... }

    // Callbacks via AsyncStream
    var trackChanges: AsyncStream<Track> { ... }
}
```

### 7.2 OSC Library

Recommend: **SwiftOSC** or **OSCKit**

```swift
// Basic pattern
let client = OSCClient(host: "127.0.0.1", port: 10000)
client.send(OSCMessage(address: "/shader/load", arguments: ["shader_name", 0.5, 0.3]))

let server = OSCServer(port: 9999)
server.setHandler { message in
    // Route to subscribers
}
```

### 7.3 AppleScript Bridge

```swift
func querySpotify() async throws -> PlaybackInfo? {
    let script = NSAppleScript(source: """
        tell application "Spotify"
            if player state is playing then
                return "{\\"artist\\":\\"" & artist of current track & "\\",\\"title\\":\\"" & name of current track & "\\"}"
            end if
        end tell
    """)

    var error: NSDictionary?
    guard let result = script?.executeAndReturnError(&error) else {
        throw SpotifyError.scriptFailed
    }
    return try JSONDecoder().decode(PlaybackInfo.self, from: result.stringValue!.data(using: .utf8)!)
}
```

### 7.4 JSON Caching

```swift
struct CacheManager {
    let cacheDirectory: URL
    let ttl: TimeInterval = 7 * 24 * 3600 // 7 days

    func load<T: Decodable>(key: String) -> T? {
        let url = cacheDirectory.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url) else { return nil }

        // Check TTL
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let modified = attrs?[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > ttl {
            return nil
        }

        return try? JSONDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, key: String) {
        let data = try? JSONEncoder().encode(value)
        let url = cacheDirectory.appendingPathComponent("\(key).json")
        try? data?.write(to: url)
    }
}
```

---

## 8. External Service Integration

### 8.1 OSC Ports

| Service | Direction | Port | Purpose |
|---------|-----------|------|---------|
| OSC Hub | Receive | 9999 | All incoming messages |
| VJUniverse | Send | 10000 | Processing app |
| Magic Music | Send | 11111 | Secondary visual |
| VirtualDJ | Send | 9009 | DJ software control |
| Synesthesia | Send | 7777 | Shader control |

### 8.2 HTTP APIs

| Service | URL | Purpose |
|---------|-----|---------|
| LRCLIB | https://lrclib.net/api | Synced lyrics |
| LM Studio | http://localhost:1234/v1 | Local LLM |
| OpenAI | https://api.openai.com/v1 | Cloud LLM (fallback) |

### 8.3 Message Formats

**Track Info** `/textler/track`:
```
[active: Int, source: String, artist: String, title: String, album: String, duration: Float, hasLyrics: Int]
```

**Lyrics Line** `/textler/lyrics/line`:
```
[index: Int, time: Float, text: String]
```

**Shader Load** `/shader/load`:
```
[name: String, energy: Float, valence: Float]
```

---

## 9. Testing Prerequisites System

### 9.1 Automatic Detection

```swift
struct ServiceDetector {
    static func isPortOpen(_ port: UInt16) -> Bool {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(socket) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    static func isProcessRunning(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
```

### 9.2 XCTest Integration

```swift
extension XCTestCase {
    func require(_ prerequisite: Prerequisite, file: StaticString = #file, line: UInt = #line) throws {
        try PrerequisiteChecker.require(prerequisite, file: file, line: line)
    }
}

// Usage in test
func test_vdj_detection() async throws {
    try require(.vdjRunning)
    try require(.vdjPlaying)

    // ... test code
}
```

---

## 10. Notes for Future Implementation

### 10.1 Critical Design Decisions

1. **Use Actors for Modules**: Swift actors provide built-in thread safety, perfect for modules that manage state and handle callbacks.

2. **AsyncStream for Events**: Use `AsyncStream` instead of closures for callbacks - better composability and cancellation.

3. **Sendable Types**: All domain types should be `Sendable` (they're structs, so automatic).

4. **No Combine**: Prefer async/await over Combine - simpler mental model.

### 10.2 Gotchas from Python Implementation

1. **VDJ OSC Behavior**: VDJ only sends on change for metadata, but needs polling for continuous data (position). The Python implementation uses a hybrid approach.

2. **LRC Format Variants**: Both `[mm:ss.xx]` (centiseconds) and `[mm:ss.xxx]` (milliseconds) exist.

3. **Graceful Degradation**: Every external dependency can fail. The system must work with subsets of functionality.

4. **Cache Key Normalization**: Use consistent `sanitizeCacheFilename()` for all cache keys.

### 10.3 Performance Considerations

1. **OSC Hub Queue**: The Python hub uses a 4096-message queue with drop detection. Replicate this.

2. **Prefix Trie for Routing**: Pattern matching uses a trie for O(k) lookup where k = pattern length.

3. **Lazy Module Loading**: Modules are lazy-loaded on first access, not at startup.

### 10.4 SwiftUI Recommendations

1. **Observable Pattern**: Use `@Observable` macro (iOS 17+/macOS 14+) for ViewModels.

2. **Minimal State**: UI should read from modules, not duplicate state.

3. **Background Processing**: All module work happens off main thread.

### 10.5 Files to Reference

When implementing specific features, refer to these Python files:

| Feature | Reference File |
|---------|---------------|
| LRC Parsing | `domain_types.py:160-187` |
| OSC Hub | `osc/hub.py` |
| VDJ Monitor | `vdj_monitor.py` |
| Pipeline | `modules/pipeline.py` |
| AI Analysis | `modules/ai_analysis.py`, `ai_services.py` |
| Shader Matching | `shader_matcher.py`, `modules/shaders.py` |
| Launchpad FSM | `launchpad_osc_lib/fsm.py` |
| Settings | `infra.py:84-276` |

### 10.6 CLI for Testing

Each module should support standalone CLI testing:

```bash
swift run SwiftVJ playback --source vdj
swift run SwiftVJ lyrics --artist "Queen" --title "Bohemian Rhapsody"
swift run SwiftVJ shaders --energy 0.8 --valence 0.5
swift run SwiftVJ pipeline --artist "Queen" --title "Bohemian Rhapsody"
```

---

## Appendix: Swift Package Structure

```
swift-vj/
├── Package.swift
├── Sources/
│   ├── SwiftVJ/
│   │   ├── main.swift                 # CLI entry point
│   │   └── Commands/
│   │       ├── PlaybackCommand.swift
│   │       ├── LyricsCommand.swift
│   │       └── PipelineCommand.swift
│   │
│   ├── SwiftVJCore/
│   │   ├── Domain/
│   │   │   ├── Types.swift            # LyricLine, Track, etc.
│   │   │   └── Functions.swift        # parseLRC, extractKeywords, etc.
│   │   │
│   │   ├── Infrastructure/
│   │   │   ├── Config.swift
│   │   │   ├── Settings.swift
│   │   │   ├── ServiceHealth.swift
│   │   │   ├── Cache.swift
│   │   │   └── ProcessManager.swift   # Processing app lifecycle
│   │   │
│   │   ├── Adapters/
│   │   │   ├── LyricsFetcher.swift
│   │   │   ├── SpotifyMonitor.swift
│   │   │   ├── VDJMonitor.swift
│   │   │   ├── OSCClient.swift
│   │   │   └── LLMClient.swift
│   │   │
│   │   ├── Modules/
│   │   │   ├── Module.swift           # Protocol
│   │   │   ├── OSCModule.swift
│   │   │   ├── PlaybackModule.swift
│   │   │   ├── LyricsModule.swift
│   │   │   ├── AIModule.swift
│   │   │   ├── ShadersModule.swift
│   │   │   ├── PipelineModule.swift
│   │   │   ├── ProcessModule.swift    # Processing app management
│   │   │   └── ModuleRegistry.swift
│   │   │
│   │   └── Launchpad/                 # MIDI Controller (REQUIRED)
│   │       ├── ButtonId.swift         # Grid coordinate system
│   │       ├── Model.swift            # PadMode, PadBehavior, ControllerState
│   │       ├── FSM.swift              # Pure state machine functions
│   │       ├── Effects.swift          # Effect types (SendOsc, SetLed, etc.)
│   │       ├── LearnMode.swift        # Learn mode phases and handlers
│   │       ├── ColorSystem.swift      # 10 colors × 3 brightness
│   │       ├── Config.swift           # YAML persistence
│   │       └── Controller.swift       # Imperative shell executing effects
│   │
│   └── SwiftVJUI/                     # SwiftUI App
│       ├── App.swift
│       ├── Views/
│       │   ├── MasterControlView.swift
│       │   ├── OSCDebugView.swift
│       │   ├── LogView.swift
│       │   └── ShaderBrowserView.swift
│       └── ViewModels/
│           └── AppViewModel.swift
│
├── Tests/
│   ├── E2ETests/
│   ├── BehaviorTests/
│   └── Prerequisites/
│
└── REWRITE_PLAN.md
```

---

*Last Updated: 2026-01-01*
*Source Analysis: python-vj ~6500 LOC across 90+ files*
